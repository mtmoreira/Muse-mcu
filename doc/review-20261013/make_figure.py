#!/usr/bin/env python3
"""Corrected evidence figure for Muse MCU (answers Section 5).

Panel A: D1 demo trace (results/raw/demo_trace.vcd), timescale-aware:
  SPI transactions decoded from MOSI/SCK/CS; UART decoded from the TX pin.
Panel B: C1 preemption zoom from a dedicated tb_preempt VCD capture
  (separate run, separately labelled), PC classified by ELF symbol ranges.
Panel C: context-check excerpts (separate tests, labelled as such).
All times in ms/us derived from the VCD $timescale (1 ps), never raw counts.
"""
import sys, hashlib, json
sys.path.insert(0, "/home/hatch/workspace/mcu-report/answers")
from fig_data import parse_vcd, decode_spi, decode_uart, edges
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

D1 = "/home/hatch/workspace/Muse-mcu/results/raw/demo_trace.vcd"
C1 = "/tmp/c1trace/preempt.vcd"
OUT = "/home/hatch/workspace/mcu-report/answers/fig_evidence.png"
OUT_SVG = "/home/hatch/workspace/mcu-report/answers/fig_evidence.svg"

ts, d = parse_vcd(D1, {"spi_cs_n", "spi_sck", "spi_mosi", "spi_miso", "uart_tx"})
assert ts == 1, "expected 1 ps timescale"
T0 = 9_877_650_000  # ps, first CS fall = window start in the VCD
def ms(t): return (t - T0) / 1e9

txns = decode_spi(d["spi_cs_n"], d["spi_sck"], d["spi_mosi"], d["spi_miso"], ts)
uart = decode_uart(d["uart_tx"], ts, 434 * 20 * 1000)
# assemble UART lines with end times
lines, cur, cur_t = [], bytearray(), None
for t, b, ok in uart:
    if b == 0x0A:
        lines.append((cur_t, t, bytes(cur))); cur = bytearray()
    else:
        if not cur: cur_t = t
        cur.append(b)

fig = plt.figure(figsize=(11.5, 8.6))
gs = fig.add_gridspec(3, 1, height_ratios=[1.25, 1.15, 0.62], hspace=0.52)

# ---------------- Panel A: D1 transactions, first 2 ms ----------------
ax = fig.add_subplot(gs[0])
win = (0, 2.0)  # ms
def plot_digital(ax, series, y, init, color):
    xs, ys = [], []
    prev_t, prev_v = T0, init
    for t, v in edges(series, init):
        if ms(t) > win[1]: break
        xs += [ms(prev_t), ms(t)]; ys += [prev_v, prev_v]
        prev_t, prev_v = t, v
    xs += [ms(prev_t), win[1]]; ys += [prev_v, prev_v]
    ax.plot([x for x in xs], [y + 0.38 * v for v in ys], color=color, lw=0.9)

for y, (sig, init, lab) in enumerate([
        ("uart_tx", 1, "UART TX\n(pin, decoded below)"),
        ("spi_miso", 0, "SPI MISO"),
        ("spi_mosi", 0, "SPI MOSI"),
        ("spi_sck", 0, "SPI SCK"),
        ("spi_cs_n", 1, "SPI CS_N")]):
    plot_digital(ax, d[sig], 4 - y, init, "#1f3864" if y < 4 else "#8b0000")
    ax.text(-0.06, 4 - y + 0.15, lab, ha="right", va="center", fontsize=7.5)

labels = [
    (0, "1: 0xAB flash wake", 0.012),
    (1, "2: 0x03 READ @0x000000, 16 B header", 0.55),
    (2, "3: 0x03 READ @0x000010, msg 0 hdr (id 0, len 0)", 1.18),
]
for i, txt, tx in labels:
    t0 = txns[i][0]
    ax.annotate(txt, xy=(ms(t0), 4.42), xytext=(tx, 4.86),
                fontsize=7.6, color="#333333",
                arrowprops=dict(arrowstyle="-", lw=0.6, color="#666666",
                                connectionstyle="arc3,rad=0.04"))
for (t_start, t_end, txt) in lines:
    if txt.startswith(b"PKT"):
        ax.annotate("", xy=(ms(t_start), 4.02), xytext=(ms(t_start), 4.38),
                    arrowprops=dict(arrowstyle="->", lw=0.9, color="#8b0000"))
        ax.text(ms(t_start) + 0.03, -0.68,
                f"decoded from TX pin: \"{txt.decode()}\"  (id 0, len 0, SHA-256 of empty message; host checker: OK)",
                fontsize=7.6, color="#8b0000")
        break
ax.set_xlim(*win); ax.set_ylim(-0.85, 5.15); ax.set_yticks([])
ax.set_xlabel("time from first SPI chip-select (ms)", fontsize=8.5)
ax.set_title("A · D1 demo: first SPI transactions and first UART packet, decoded from the recorded pins",
             fontsize=9.5, loc="left")
ax.grid(axis="x", alpha=0.25)

# ---------------- Panel B: C1 preemption zoom ----------------
axb = fig.add_subplot(gs[1])
try:
    ts2, d2 = parse_vcd(C1, {"tb_irq", "dbg_pc", "dbg_trap_taken", "dbg_mcause"})
    HP = (0x1D60, 0x1DF8); LP = (0x1C98, 0x1CBC)
    TRAP = (0x1600, 0x1760)  # freertos_risc_v_trap_handler approx span
    pcs = d2["dbg_pc"]
    import bisect as _bs
    pt = [t for t, _ in pcs]
    mcv_list = d2["dbg_mcause"]
    def mcause_at(tc):
        v = None
        for t, vv in mcv_list:
            if t <= tc: v = vv
            else: break
        return v
    trap_rises, _pv = [], 0
    for t, v in d2["dbg_trap_taken"]:
        if v == 1 and _pv == 0: trap_rises.append(t)
        _pv = v
    t_trap = t_hp = None
    for tc in trap_rises:
        if mcause_at(tc) != 0x8000000B: continue
        i0 = _bs.bisect_right(pt, tc)
        for t, v in pcs[i0:i0 + 4000]:
            if HP[0] <= v < HP[1]:
                t_trap, t_hp = tc, t; break
        if t_trap: break
    assert t_trap, "no MEI->HP event found"
    cyc = lambda t: t / 20000.0  # 20 ns per cycle, in cycles rel.
    w0 = t_trap - 200 * 20000
    w1 = t_hp + 260 * 20000
    rel = lambda t: (t - t_trap) / 20000.0
    # classify retired PCs in window
    xs, cs = [], []
    for t, v in pcs:
        if w0 <= t <= w1:
            if HP[0] <= v < HP[1]: c = 3
            elif LP[0] <= v < LP[1]: c = 1
            elif TRAP[0] <= v < TRAP[1] or v < 0x100: c = 2
            else: c = 0
            xs.append(rel(t)); cs.append(c)
    axb.scatter(xs, cs, s=1.5, c="#1f3864", marker="s")
    for yy, lab in [(0, "kernel / port\n(shared code)"), (1, "LP task\n(vLPTask body)"),
                    (2, "trap handler\n(portASM)"), (3, "HP task\n(vHPTask body)")]:
        axb.text(-118, yy, lab, ha="right", va="center", fontsize=7.5)
    axb.axvline(0, color="#8b0000", lw=1.1)
    axb.axvline(rel(t_hp), color="#1e7d32", lw=1.1)
    axb.annotate("T0: MEI trap taken\n(mcause 0x8000000B)", xy=(0, 3.35),
                 fontsize=7.5, color="#8b0000")
    axb.annotate(f"T1: first HP instruction retired\nlatency {int(rel(t_hp))} cycles (bound 2000)",
                 xy=(rel(t_hp), -0.75), fontsize=7.5, color="#1e7d32")
    irq = edges(d2["tb_irq"], 0)
    xs2, ys2 = [], []
    pv_t, pv_v = w0, 0
    for t, v in irq:
        if t < w0: pv_v = v; continue
        if t > w1: break
        xs2 += [rel(pv_t), rel(t)]; ys2 += [3.85 + 0.3 * pv_v, 3.85 + 0.3 * pv_v]
        pv_t, pv_v = t, v
    xs2 += [rel(pv_t), rel(w1)]; ys2 += [3.85 + 0.3 * pv_v, 3.85 + 0.3 * pv_v]
    axb.plot(xs2, ys2, color="#8b0000", lw=0.9)
    axb.text(-118, 3.95, "tb_test_irq\n(tb stimulus)", ha="right", va="center", fontsize=7.5)
    axb.set_ylim(-1.1, 4.5); axb.set_yticks([])
    axb.set_xlim(rel(w0), rel(w1))
    axb.set_xlabel("cycles relative to trap entry T0 (20 ns per cycle)", fontsize=8.5)
    axb.set_title("B · C1 preemption, one event (separate run: tb_preempt VCD captured 2026-10-13, same firmware/RTL)",
                  fontsize=9.5, loc="left")
    axb.grid(axis="x", alpha=0.25)
except Exception as e:
    axb.text(0.02, 0.5, f"Panel B unavailable: {e}", fontsize=9)
    axb.set_title("B · C1 preemption", fontsize=9.5, loc="left")

# ---------------- Panel C: context check excerpts ----------------
axc = fig.add_subplot(gs[2]); axc.axis("off")
axc.set_title("C · Context preservation evidence (separate tests, not the runs above)",
              fontsize=9.5, loc="left")
txt = ("B1 register preservation (tb_rtos, Icarus, rtos_regtest firmware):\n"
       "    UART: MARK regtest 600 ctxsw=633\n"
       "    UART: TEST regtest PASS switches=600 ctxsw=636     [600 verified fill/yield/verify batches; x1, x5-x31 checked]\n"
       "G2 negative control (tb_fault_ctx): saved x5 corrupted to 0xdddddddd at cycle 239384 ->\n"
       "    UART: TEST regtest FAIL: task 1 x6 expected dddddddd   [detected at cycle 443667; checker rejected the run]")
axc.text(0.005, 0.92, txt, fontsize=8.2, family="monospace", va="top")

h = hashlib.sha256(open(D1, "rb").read()).hexdigest()
fig.text(0.01, 0.012,
         f"Sources: D1 VCD sha256 {h[:24]}... (results/raw/demo_trace.vcd, $timescale 1 ps, window 1M cycles from first CS).\n"
         "Panel A excerpt: first 2 ms of the window; SPI bytes decoded MSB-first at SCK rising edges (mode 0); UART 8N1 at 434 cycles/bit.\n"
         "Panel B: separate C1 run and capture; task identity from retired PC vs ELF symbol ranges (nm on preempt_test.elf); shared kernel code labelled as such.",
         fontsize=7.2, color="#555555")
fig.savefig(OUT, dpi=190, bbox_inches="tight")
fig.savefig(OUT_SVG, bbox_inches="tight")
print("wrote", OUT)

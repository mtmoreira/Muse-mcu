#!/usr/bin/env python3
"""Build the walkthrough assets for one run (spec Section 5):
stage03 VCD slice, anchors.json, stage PNGs 01-08, decoded tables.

All displayed values come from the run's captured evidence
(writes.csv / events.csv / uart_capture.bin / tb_result.json) and the
independent reference, never hand-entered.
"""
import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_tools import parse_vcd, decode_spi, slice_vcd  # noqa: E402

import numpy as np  # noqa: E402
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from PIL import Image  # noqa: E402

CYCLE_NS = 20  # 50 MHz


def sha256f(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def load_writes(path):
    rows = []
    with open(path) as f:
        next(f)
        for line in f:
            c, a, d, s = line.strip().split(",")
            rows.append((int(c), int(a, 16), int(d, 16), int(s, 16)))
    return rows


def load_events(path):
    ev = []
    with open(path) as f:
        next(f)
        for line in f:
            c, v = line.strip().split(",")
            ev.append((int(c), int(v, 16)))
    return ev


def committed_sequence(rows, base, size):
    """(cycle, offset, byte) for every committed byte write in range,
    in cycle order; plus final image and first-write cycle per offset."""
    seq = []
    for c, addr, data, strb in rows:
        for lane in range(4):
            if strb & (1 << lane):
                off = addr + lane - base
                if 0 <= off < size:
                    seq.append((c, off, (data >> (8 * lane)) & 0xFF))
    final = bytearray(size)
    first = {}
    for c, off, b in seq:
        final[off] = b
        if off not in first:
            first[off] = c
    return seq, bytes(final), first


def img_from_bytes(b):
    return np.frombuffer(b, np.uint8).reshape(64, 64)


def save_img(arr, path, title=None, cmap="gray"):
    fig, ax = plt.subplots(figsize=(4.2, 4.2))
    ax.imshow(arr, cmap=cmap, vmin=0, vmax=255, interpolation="nearest")
    ax.set_xticks(range(0, 64, 8))
    ax.set_yticks(range(0, 64, 8))
    if title:
        ax.set_title(title, fontsize=9)
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def progressive(seq, size, path, title):
    total = len({off for _c, off, _b in seq})
    fr = [0.25, 0.5, 0.75, 1.0]
    snaps = []
    seen = {}
    order = []
    for _c, off, b in seq:
        if off not in seen:
            order.append(off)
        seen[off] = b
    for f in fr:
        n = int(total * f)
        canvas = np.full((64, 64), -1, dtype=np.int32)
        for off in order[:n]:
            canvas[off // 64, off % 64] = seen[off]
        snaps.append(canvas)
    fig, axes = plt.subplots(1, 4, figsize=(11, 3.0))
    for ax, snap, f in zip(axes, snaps, fr):
        disp = np.where(snap < 0, 0, snap).astype(np.uint8)
        ax.imshow(disp, cmap="gray", vmin=0, vmax=255,
                  interpolation="nearest")
        unwritten = snap < 0
        if unwritten.any():
            overlay = np.zeros((64, 64, 4))
            overlay[unwritten] = (1.0, 0.35, 0.0, 0.85)  # orange = unwritten
            ax.imshow(overlay, interpolation="nearest")
        ax.set_title(f"{int(f*100)}% of bytes written", fontsize=8)
        ax.set_xticks([])
        ax.set_yticks([])
    fig.suptitle(title + "  (orange = not yet written)", fontsize=9)
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def nm_ranges(elf, tc_nm):
    out = subprocess.run([tc_nm, "--print-size", elf], capture_output=True,
                         text=True).stdout
    ranges = []
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 4 and p[2] in "tT":
            try:
                ranges.append((int(p[0], 16), int(p[0], 16) + int(p[1], 16),
                               p[3]))
            except ValueError:
                pass
    return ranges


def classify(pc, ranges):
    for lo, hi, name in ranges:
        if lo <= pc < hi:
            if name == "vImageIOTask":
                return "ImageIO"
            if name in ("prvGradientTask", "vGradientXTask", "vGradientYTask"):
                return "Gradient workers"
            if name == "vCombineTask":
                return "Combine"
            if "trap_handler" in name:
                return "trap handler"
            return "kernel/shared"
    return "kernel/shared"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--kind", required=True)
    ap.add_argument("--input-raw", required=True)
    ap.add_argument("--input-json", required=True)
    ap.add_argument("--ref-dir", required=True)
    ap.add_argument("--flash-bin", required=True)
    ap.add_argument("--elf", required=True)
    ap.add_argument("--tc-nm", required=True)
    args = ap.parse_args()
    R = args.run_dir
    A = os.path.join(R, "assets")
    os.makedirs(A, exist_ok=True)

    syms = json.load(open(os.path.join(R, "symbols.json")))
    base = {k: int(v, 16) for k, v in syms.items() if k.startswith("img_")}
    rows = load_writes(os.path.join(R, "writes.csv"))
    ev = load_events(os.path.join(R, "events.csv"))
    evmap = {}
    for c, v in ev:
        evmap.setdefault(v, c)
    tb = json.load(open(os.path.join(R, "tb_result.json")))
    results = json.load(open(os.path.join(R, "results.json")))
    canonical = open(args.input_raw, "rb").read()
    in_meta = json.load(open(args.input_json))
    gx_ref = np.load(os.path.join(args.ref_dir, "gx.npy"))
    gy_ref = np.load(os.path.join(args.ref_dir, "gy.npy"))
    ref_out = open(os.path.join(args.ref_dir, "ref_out.raw"), "rb").read()

    in_seq, in_final, _ = committed_sequence(rows, base["img_in"], 4096)
    gx_seq, gx_final, _ = committed_sequence(rows, base["img_gx"], 8192)
    gy_seq, gy_final, _ = committed_sequence(rows, base["img_gy"], 8192)
    out_seq, out_final, out_first = committed_sequence(rows, base["img_out"], 4096)
    anchors = {"run": os.path.basename(R.rstrip("/")), "kind": args.kind,
               "clock_hz": 50_000_000, "cycle_ns": CYCLE_NS, "stages": {}}
    S = anchors["stages"]

    # ---------- stage 03 slice ----------
    cs0 = tb["cs35_start_cycle"]
    row32 = [(c, off) for c, off, _b in in_seq if 2048 <= off < 2112]
    last_row32 = max(c for c, _o in row32)
    win0_cyc = max(0, cs0 - 25)
    win1_cyc = last_row32 + 250
    slice_vcd(os.path.join(R, "stage02_load_overview.vcd"),
              os.path.join(R, "stage03_load_detail.vcd"),
              win0_cyc * CYCLE_NS * 1000, win1_cyc * CYCLE_NS * 1000)

    # strip decode from the slice (row 32 read = the only payload txn)
    _ts, d3 = parse_vcd(os.path.join(R, "stage03_load_detail.vcd"),
                        {"spi_cs_n", "spi_sck", "spi_mosi", "spi_miso"})
    tx3 = decode_spi(d3["spi_cs_n"], d3["spi_sck"], d3["spi_mosi"],
                     d3["spi_miso"])
    strip_bytes = None
    for _t0, _t1, mb, ib in tx3:
        if len(mb) > 4 and mb[0] == 0x03:
            strip_bytes = bytes(ib[4:])
    tables = {"strip_row": 32, "strip_bytes_row32": list(strip_bytes or b"")}

    # ---------- stage 05/06/07 slices ----------
    # Icarus honors only the first $dumpfile of a simulation, so the
    # tb's later windows were all captured into the stage02 file
    # (delimited by $dumpoff/$dumpon). Slice the three remaining
    # stage windows out of it here, re-based like stage03.
    combined = os.path.join(R, "stage02_load_overview.vcd")
    def _need(code):
        if code not in evmap:
            raise SystemExit(f"make_assets: missing trace anchor "
                             f"0x{code:04x} in events.csv")
        return evmap[code]
    slice_vcd(combined, os.path.join(R, "stage05_rtos.vcd"),
              _need(0x1001) * CYCLE_NS * 1000,
              (_need(0x4002) + 200) * CYCLE_NS * 1000)
    slice_vcd(combined, os.path.join(R, "stage06_writeback.vcd"),
              _need(0x4007) * CYCLE_NS * 1000,
              (_need(0x4008) + 300) * CYCLE_NS * 1000)
    # UART window: bytes 2000..2010. A byte is 10 bit periods of 434
    # cycles; anchor from the tb's last-byte cycle and walk back.
    last_byte = tb["last_byte_cycle"]
    b2010_end = last_byte - (4148 - 2010) * 4340
    slice_vcd(combined, os.path.join(R, "stage07_uart.vcd"),
              (b2010_end - 12 * 4340 - 5000) * CYCLE_NS * 1000,
              (b2010_end + 5000) * CYCLE_NS * 1000)

    # ---------- 01 input ----------
    save_img(img_from_bytes(canonical), os.path.join(A, "stage01_input.png"),
             f"input image: 64x64 GRAY8, frame {in_meta['frame_id']}")
    S["01"] = {"image": "assets/stage01_input.png", "vcd": None,
               "events": [{"name": "flash layout", "note":
                           "header 20 B at flash 0x000000; pixel (x,y) at "
                           f"20 + y*64 + x; raw sha256 {in_meta['raw_sha256'][:16]}..."}]}

    # ---------- 02 load overview ----------
    progressive(in_seq, 4096, os.path.join(A, "stage02_load.png"),
                "input SRAM buffer, reconstructed from committed writes")
    first_in = in_seq[0][0]
    last_in = in_seq[-1][0]
    S["02"] = {"image": "assets/stage02_load.png",
               "vcd": "stage02_load_overview.vcd",
               "t0_ns": 0, "t1_ns": (last_in + 300) * CYCLE_NS,
               "events": [
                   {"name": "first committed input write", "cycle": first_in},
                   {"name": "last committed input write", "cycle": last_in},
                   {"name": "load-done trace", "cycle": evmap.get(0x1001)}]}

    # ---------- 03 load detail ----------
    fig, ax = plt.subplots(figsize=(11, 2.6))
    ax.axis("off")
    xs = list(range(16, 48))
    lines = ["row y=32, pixels x=16..47  (flash addr = 20 + 2048 + x = 2068 + x)",
             "x:    " + " ".join(f"{x:4d}" for x in xs),
             "val:  " + " ".join(f"{canonical[2048 + x]:4d}" for x in xs),
             "hex:  " + " ".join(f"{canonical[2048 + x]:02x}  " for x in xs),
             "SPI MISO bytes for the same pixels (decoded from stage03 VCD):",
             "hex:  " + " ".join(
                 f"{(strip_bytes or b'')[x]:02x}  " if strip_bytes else "??"
                 for x in xs),
             "highlight: x=32 is the recurring pixel (value "
             f"{canonical[2080]}); its byte is MISO byte 32 of this read."]
    ax.text(0.01, 0.95, "\n".join(lines), family="monospace", fontsize=8.5,
            va="top")
    fig.tight_layout()
    fig.savefig(os.path.join(A, "stage03_strip.png"), dpi=110)
    plt.close(fig)
    S["03"] = {"image": "assets/stage03_strip.png",
               "vcd": "stage03_load_detail.vcd", "t0_ns": 0,
               "t1_ns": (win1_cyc - win0_cyc) * CYCLE_NS,
               "events": [
                   {"name": "SPI read of row 32 starts (CS fall)",
                    "cycle": cs0},
                   {"name": "row 32 read ends (CS rise)",
                    "cycle": tb["cs35_end_cycle"]},
                   {"name": "last SRAM write of row 32", "cycle": last_row32}]}

    # ---------- 04 algorithm ----------
    idx = 2080
    hood = [[int(canonical[(32 + dy) * 64 + (32 + dx)])
             for dx in (-1, 0, 1)] for dy in (-1, 0, 1)]
    gx_w = [c for c, off, _b in gx_seq if off in (2 * idx, 2 * idx + 1)]
    gy_w = [c for c, off, _b in gy_seq if off in (2 * idx, 2 * idx + 1)]
    out_w = [c for c, off, _b in out_seq if off == idx]
    obs_gx = int(np.frombuffer(gx_final[2 * idx:2 * idx + 2], "<i2")[0])
    obs_gy = int(np.frombuffer(gy_final[2 * idx:2 * idx + 2], "<i2")[0])
    obs_out = out_final[idx]
    fig, ax = plt.subplots(figsize=(7.6, 4.6))
    ax.axis("off")
    txt = [f"pixel (32,32): 3x3 neighborhood from the input image",
           f"        {hood[0]}",
           f"        {hood[1]}     center = {hood[1][1]}",
           f"        {hood[2]}",
           f"Gx = -{hood[0][0]} +{hood[0][2]} -2*{hood[1][0]} +2*{hood[1][2]}"
           f" -{hood[2][0]} +{hood[2][2]} = {int(gx_ref[32, 32])}",
           f"Gy = -{hood[0][0]} -2*{hood[0][1]} -{hood[0][2]}"
           f" +{hood[2][0]} +2*{hood[2][1]} +{hood[2][2]} = {int(gy_ref[32, 32])}",
           f"out = min(255, |Gx| + |Gy|) = {ref_out[idx]}",
           "",
           f"committed SRAM writes observed for this pixel:",
           f"  Gx int16 = {obs_gx}  (write cycle {gx_w[-1] if gx_w else '-'})",
           f"  Gy int16 = {obs_gy}  (write cycle {gy_w[-1] if gy_w else '-'})",
           f"  out byte = {obs_out}  (write cycle {out_w[-1] if out_w else '-'})",
           f"expected (OpenCV reference): Gx {int(gx_ref[32, 32])}, "
           f"Gy {int(gy_ref[32, 32])}, out {ref_out[idx]}"]
    ax.text(0.02, 0.97, "\n".join(txt), family="monospace", fontsize=9,
            va="top")
    fig.tight_layout()
    fig.savefig(os.path.join(A, "stage04_pixel.png"), dpi=110)
    plt.close(fig)
    tables["pixel_32_32"] = {"neighborhood": hood, "gx_ref": int(gx_ref[32, 32]),
                             "gy_ref": int(gy_ref[32, 32]),
                             "gx_obs": obs_gx, "gy_obs": obs_gy,
                             "out_ref": ref_out[idx], "out_obs": obs_out,
                             "gx_write_cycle": gx_w[-1] if gx_w else None,
                             "gy_write_cycle": gy_w[-1] if gy_w else None,
                             "out_write_cycle": out_w[-1] if out_w else None}
    # Stage04 shares the stage06 writeback slice. Window on the Gy
    # write, which is inside that slice; the Gx write precedes the
    # slice start, so anchor on Gy (an earlier formula anchored on
    # Gx and produced a negative window end).
    w06_start = evmap.get(0x4007, 0)
    gy_rel = (gy_w[-1] - w06_start) if gy_w else 0
    S["04"] = {"image": "assets/stage04_pixel.png",
               "vcd": "stage06_writeback.vcd",
               "t0_ns": max(0, gy_rel - 400) * CYCLE_NS,
               "t1_ns": (gy_rel + 800) * CYCLE_NS,
               "events": [{"name": "Gx write for (32,32)",
                           "cycle": gx_w[-1] if gx_w else None,
                           "in_waveform": bool(gx_w)
                           and gx_w[-1] >= w06_start},
                          {"name": "Gy write for (32,32)",
                           "cycle": gy_w[-1] if gy_w else None,
                           "in_waveform": bool(gy_w)
                           and gy_w[-1] >= w06_start}]}

    # ---------- 05 RTOS ----------
    ranges = nm_ranges(args.elf, args.tc_nm)
    _ts, d5 = parse_vcd(os.path.join(R, "stage05_rtos.vcd"),
                        {"dbg_pc", "dbg_trap_taken", "gpio0_scratch_q",
                         "scratch_q"})
    pc_series = d5.get("dbg_pc", [])
    s05_start = evmap.get(0x1001, 0)
    s05_end = evmap.get(0x4002, 0)
    colors = {"ImageIO": "#888888", "Gradient workers": "#1f77b4",
              "Combine": "#2ca02c", "trap handler": "#d62728",
              "kernel/shared": "#cccccc"}
    fig, ax = plt.subplots(figsize=(11, 3.4))
    if pc_series:
        segs = []
        cur_cls, cur_t = None, pc_series[0][0]
        for t, pc in pc_series:
            cls = classify(pc, ranges)
            if cls != cur_cls:
                if cur_cls is not None:
                    segs.append((cur_t, t, cur_cls))
                cur_cls, cur_t = cls, t
        segs.append((cur_t, pc_series[-1][0], cur_cls))
        for t0, t1, cls in segs:
            ax.axvspan((t0 / 1000) / CYCLE_NS + s05_start,
                       (t1 / 1000) / CYCLE_NS + s05_start,
                       color=colors[cls], alpha=0.75)
    names = {0x2000: "GX", 0x3000: "GY", 0x4000: "CB"}
    for c, v in ev:
        if s05_start <= c <= s05_end + 200 and (v & 0xF000) in names:
            ax.axvline(c, color="black", lw=0.5, alpha=0.5)
            ax.text(c, 1.02, f"{names[v & 0xF000]}{v & 0xF}",
                    fontsize=6.5, rotation=0)
    handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in colors.values()]
    ax.legend(handles, list(colors.keys()), fontsize=7, loc="lower left",
              ncol=5)
    ax.set_xlim(s05_start, s05_end + 200)
    ax.set_ylim(0, 1.15)
    ax.set_yticks([])
    ax.set_xlabel("simulation cycle (stage05 window: load done to Combine stripe 2)")
    ax.set_title("retired-PC classification + stripe publication traces "
                 "(GX/GY = gradient published, CB = combine wrote)", fontsize=9)
    fig.tight_layout()
    fig.savefig(os.path.join(A, "stage05_rtos.png"), dpi=110)
    plt.close(fig)
    S["05"] = {"image": "assets/stage05_rtos.png", "vcd": "stage05_rtos.vcd",
               "t0_ns": 0, "t1_ns": (s05_end + 200 - s05_start) * CYCLE_NS,
               "events": [{"name": "load done", "cycle": s05_start},
                          {"name": "combine stripe 2 done", "cycle": s05_end}]}

    # ---------- 06 writeback ----------
    progressive(out_seq, 4096, os.path.join(A, "stage06_writeback.png"),
                "output framebuffer, reconstructed from committed writes")
    # The anchor is the FINAL computed write of the target pixel (the
    # Combine write). out_first would give the crt0 BSS zero-fill at
    # boot, which is not the write this stage is about.
    tgt_cycle = out_w[-1] if out_w else None
    fault = tb.get("fault")
    s06 = {"image": "assets/stage06_writeback.png",
           "vcd": "stage06_writeback.vcd",
           "t0_ns": max(0, (tgt_cycle - evmap.get(0x4007, 0) - 600)) * CYCLE_NS
           if tgt_cycle else 0,
           "t1_ns": ((tgt_cycle - evmap.get(0x4007, 0) + 600)) * CYCLE_NS
           if tgt_cycle else 0,
           "events": [{"name": "output write of pixel (32,32), offset 2080",
                       "cycle": tgt_cycle}]}
    if fault:
        s06["fault"] = fault
        s06["events"].append({"name": "INJECTION (bit 7 flipped)",
                               "cycle": fault["cycle"]})
    S["06"] = s06

    # ---------- 07 UART ----------
    cap = open(os.path.join(R, "uart_capture.bin"), "rb").read()
    fig, ax = plt.subplots(figsize=(9.5, 3.4))
    ax.axis("off")
    lines = ["UART packet: 20 B header + 4096 B payload + 32 B SHA-256",
             f"header: magic {cap[:4]!r} ver {cap[4]} fmt {cap[5]} "
             f"frame {struct.unpack('<I', cap[8:12])[0]} "
             f"{struct.unpack('<H', cap[12:14])[0]}x"
             f"{struct.unpack('<H', cap[14:16])[0]} len "
             f"{struct.unpack('<I', cap[16:20])[0]}",
             "excerpt, packet bytes 2000..2009 (payload offsets 1980..1989):"]
    for i in range(2000, 2010):
        po = i - 20
        lines.append(f"  byte {i}: 0x{cap[i]:02x} ({cap[i]:3d})  "
                     f"pixel (x={po % 64}, y={po // 64})")
    lines.append(f"digest (last 32 B): {cap[-32:].hex()[:32]}...")
    ax.text(0.01, 0.97, "\n".join(lines), family="monospace", fontsize=8.5,
            va="top")
    fig.tight_layout()
    fig.savefig(os.path.join(A, "stage07_uart.png"), dpi=110)
    plt.close(fig)
    S["07"] = {"image": "assets/stage07_uart.png", "vcd": "stage07_uart.vcd",
               "t0_ns": 0, "t1_ns": 10 * 434 * CYCLE_NS,
               "events": [{"name": "window opens at packet byte 2000"}]}
    tables["uart_excerpt"] = {str(i): cap[i] for i in range(2000, 2010)}

    # ---------- 08 reference ----------
    mcu = img_from_bytes(out_final)
    ref = img_from_bytes(ref_out)
    diff = (mcu != ref)
    fig, axes = plt.subplots(1, 3, figsize=(11, 3.8))
    axes[0].imshow(mcu, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    axes[0].set_title("MCU stored image", fontsize=9)
    axes[1].imshow(ref, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    axes[1].set_title("OpenCV reference", fontsize=9)
    dover = np.zeros((64, 64, 4))
    dover[..., 3] = 0.25
    dover[diff] = (1, 0, 0, 1)
    axes[2].imshow(ref, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    axes[2].imshow(dover, interpolation="nearest")
    axes[2].set_title(f"mismatches: {int(diff.sum())} (red)", fontsize=9)
    for ax in axes:
        ax.set_xticks([])
        ax.set_yticks([])
    if diff.any():
        ys, xs = np.nonzero(diff)
        fig2, ax2 = plt.subplots(figsize=(3.4, 3.4))
        y0, x0 = ys[0], xs[0]
        crop = mcu[max(0, y0 - 4):y0 + 5, max(0, x0 - 4):x0 + 5]
        ax2.imshow(crop, cmap="gray", vmin=0, vmax=255,
                   interpolation="nearest")
        ax2.add_patch(plt.Rectangle((4 - min(4, x0) + (x0 - max(0, x0 - 4)) - 0.5,
                                     4 - min(4, y0) + (y0 - max(0, y0 - 4)) - 0.5),
                                    1, 1, fill=False, edgecolor="red", lw=2))
        ax2.set_title(f"crop at mismatch ({x0},{y0}): MCU {mcu[y0, x0]} vs "
                      f"ref {ref[y0, x0]}", fontsize=8)
        fig2.tight_layout()
        fig2.savefig(os.path.join(A, "stage08_crop.png"), dpi=130)
        plt.close(fig2)
    fig.tight_layout()
    fig.savefig(os.path.join(A, "stage08_compare.png"), dpi=110)
    plt.close(fig)
    oc = results["checks"]["output_sram"]
    S["08"] = {"image": "assets/stage08_compare.png", "vcd": None,
               "events": [{"name": "checker: output_sram",
                           "note": f"compared 4096 bytes, mismatches "
                                   f"{oc['mismatch_count']}, pass {oc['pass']}"},
                          {"name": "functional verdict",
                           "note": results["functional"]}]}

    anchors["evidence_hashes"] = {
        "uart_capture.bin": sha256f(os.path.join(R, "uart_capture.bin")),
        "writes.csv": sha256f(os.path.join(R, "writes.csv")),
        "events.csv": sha256f(os.path.join(R, "events.csv")),
        "flash_bin": sha256f(args.flash_bin),
        "results.json": sha256f(os.path.join(R, "results.json")),
    }
    with open(os.path.join(R, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=2)
    with open(os.path.join(A, "decoded_tables.json"), "w") as f:
        json.dump(tables, f, indent=2)
    print(f"assets written for {args.kind}: {A}")


if __name__ == "__main__":
    main()

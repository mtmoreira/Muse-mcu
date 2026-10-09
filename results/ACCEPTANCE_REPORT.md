# Muse MCU — Final Acceptance Report

Contract: `acceptance/manifest.yaml` v1.0.0, APPROVED (31 requirements).
Repo: https://github.com/mtmoreira/Muse-mcu
Branch: `work/mcu-acceptance-v1`
Reproduction: `make acceptance`
Verification base: commit f34617b0500d89216a5322c8c82c3dae075c6b40
Report frozen at commit af3164727692cfdc9e89ef03245a4a13132227f0; HEAD adds only this report's own SHA line.

## Verdict

30 PASS, 0 FAIL, 1 BLOCKED (B7). Every requirement the tracker marks PASS was
independently re-verified against its cited evidence file on 2026-10-09 and
holds up. The single BLOCKED item is a genuine contract-vs-reality conflict,
not a failure of the implementation, and needs the owner's decision (see B7).

## Per-layer counts

| Layer | Requirements | PASS | FAIL | BLOCKED |
|-------|--------------|------|------|---------|
| A (RTL functional) | A1-A9 | 9 | 0 | 0 |
| B (RTOS) | B1-B7 | 6 | 0 | 1 |
| C (Preemption) | C1 | 1 | 0 | 0 |
| D (Application) | D1-D2 | 2 | 0 | 0 |
| E (Frozen revision) | E1 | 1 | 0 | 0 |
| F (Synthesis / gate-level) | F1-F3 | 3 | 0 | 0 |
| G (Negative tests) | G1-G3 | 3 | 0 | 0 |
| R (Reproducibility) | R1-R2 | 2 | 0 | 0 |
| Demo / figures | DEMO1, FIG1, FIG2 | 3 | 0 | 0 |

## Per-requirement verdicts

| ID | Title | Verdict | Evidence (re-verified 2026-10-09) |
|----|-------|---------|-----------------------------------|
| A1 | RV32I arch tests (39) | PASS | `tools/check_arch.py` re-run: ARCH 45/45 (A1 39/39 + A2 6/6), exit 0; 45 DUT/Spike signature pairs byte-identical in `results/raw/arch/` |
| A2 | Zicsr arch tests (6) | PASS | same as A1; csrrc/csrrci/csrrs/csrrsi/csrrw/csrrwi all byte-identical to Spike |
| A3 | Reset/startup (3 variants) | PASS | `tb/build/run_reset_s1/s2/s3.log` all contain `TB_RESET: ALL PASS` |
| A4 | Trap behavior (8 cases) | PASS | `tb/build/run_trap.log`: `TB_TRAP: ALL PASS (8/8)` |
| A5 | Timer/ext interrupts | PASS | `tb/build/run_irq.log`: `TB_IRQ: ALL PASS (20 timer + 4 ext = 24 events)` |
| A6 | Memory map (40) | PASS | `tb/build/run_memmap.log`: `TB_MEMMAP: ALL PASS (40/40)` |
| A7 | UART RX (64 bytes) | PASS | `results/raw/uart_rx.log`: `ALL PASS (64/64 bytes match, in order)` |
| A8 | SPI master (256B) | PASS | `results/raw/spi.log`: `ALL PASS (256/256 data bytes match, 0 protocol violations)` |
| A9 | Timer accuracy + GPIO | PASS | `results/a9_gate.json` verdict PASS; `results/raw/a9_verilator.log`: 1000/1000 ticks at 50000+-1 cycles, 16/16 GPIO (Verilator backend recorded in gate JSON) |
| B1 | Register preservation | PASS | `tb/build/run_rtos_rtos_regtest.log`: `ALL PASS (marks=6)`, 600 switches |
| B2 | Queues | PASS | `tb/build/run_rtos_rtos_queue.log`: `TEST queue PASS ops=4168`, 0 errors |
| B3 | Semaphores/mutexes | PASS | `tb/build/run_rtos_rtos_sema.log`: `TEST sema PASS ops=2376`, 0 errors |
| B4 | Task notifications | PASS | `results/b4_gate.json` verdict PASS; `tb/logs/run_rtos_vlt_rtos_notify.log`: `TEST notify PASS ops=514`, 40 MARKs, 0 errors (Verilator backend recorded) |
| B5 | Software timers | PASS | `results/b5_gate.json` verdict PASS; `results/raw/b5_verilator.log`: `TEST timer PASS expiries=209`, 0 errors |
| B6 | ISR-to-task | PASS | `results/b6_gate.json` verdict PASS; `results/raw/b6_verilator.log`: `TEST isr PASS handoffs=301`, 0 errors |
| B7 | Blocking timeouts | BLOCKED | `results/raw/b7_blocktim_400M_uart.log`, `tb/logs/run_rtos_vlt_rtos_blocktim.log`; measured 48 events / 7950 ticks = 0.006 events per tick; see B7 section |
| C1 | Preemption <= 2000 cycles | PASS | `results/raw/preempt.log`: `ALL PASS (52/52 events within 2000 cycles)`, max latency 427 cycles |
| D1 | App end-to-end (24 msgs) | PASS | `results/raw/demo_uart.log`: `TEST app_demo PASS`; `tools/check_app.py --uart results/raw/demo_uart.log --flash fw/build/flash.hex` re-run by the verifier: `CHECK_APP: ALL PASS (24/24 packets)`, exit 0, digests verified with Python hashlib against the flash image |
| D2 | SHA self-test (8 vecs) | PASS | `results/raw/demo_uart.log`: `SHA SELFTEST PASS` (8 NIST vectors, RFC 6234 extraction) |
| E1 | Frozen RTL revision | PASS | `tools/check_frozen.py` re-run: `PASS (frozen revision consistent)`; RTL tree clean, hexes match freeze record |
| F1 | Synthesis | PASS | `results/f1_synth.json`: Yosys 0.33, 11858 cells, 19495.406 um2 Nangate45, blackboxes={bootrom,sram} |
| F2 | Gate-level app (4 msgs) | PASS | `results/f2_gate.json` verdict PASS (netlist sha256 recorded); `results/raw/gate_uart.log`: 4/4 packets, `TEST app_demo PASS` |
| F3 | Gate-level preempt | PASS | `results/f3_gate.json` verdict PASS: 10/10 events, max 208 cycles (bound 2000), same netlist sha256 as F2 |
| G1 | Fault: no tick | PASS | `results/raw/fault_notick.log`: fault activated at cycle 5240519, `CHECKER REJECTED (watchdog: no MARK for >100000 cycles)`, `TB_FAULT_NOTICK: ALL PASS`. The run was REJECTED, not passed. |
| G2 | Fault: ctx corrupt | PASS | `results/raw/g2_fault_ctx.log`: x5 slot store observed and confirmed in SRAM, injected 0xdddddddd at cycle 239384, `TEST regtest FAIL` at cycle 443667, `ALL PASS (fault active, checker rejected run)` |
| G3 | Fault: UART corrupt | PASS | `results/raw/fault_uart_tampered.log`: duplicated PKT 3 line injected; `results/raw/fault_uart_check.log`: `CHECK_APP: FAIL (25/24 packets)`, packet 4 onward sequence/len/digest mismatches. The tampered stream was REJECTED, not passed. (Note: the status tracker left the G3 evidence cell blank; evidence files are the two logs named here.) |
| R1 | Bootstrap | PASS | `env/bootstrap.sh` provisions pinned toolchains (revision pinned in `third_party/PINS.md`) |
| R2 | make acceptance | PASS | `Makefile` target drives `tools/run_acceptance.py`, the one-command runner |
| DEMO1 | Live demo | PASS | `demo/run_demo.sh` (wraps `tb/run_app.sh`); `results/demo_transcript.txt`: narrated live feed, 157 MARK/PKT lines, `SHA SELFTEST PASS`, `TEST app_demo PASS`, `TB_APP: SIM PASS (24/24 packets live-verified, watermark 4, bg 60/180)` |
| FIG1 | Arch figure | PASS | `doc/fig_arch.png` (1800x1200 PNG, valid), generated by `doc/gen_arch_fig.py` from `rtl/` module metadata; visually verified by the finisher crew 2026-10-09 |
| FIG2 | Trace figure | PASS | `doc/fig_trace.png` (1800x1200 PNG, valid), generated by `doc/gen_trace_fig.py` strictly from `results/raw/demo_trace.vcd` (52 MB, captured by `tb/tb_app.sv` during the D1 run); the generator refuses to run without the VCD, so no edges are invented |

## B7 BLOCKED: measured numbers and owner options

The blocking-timeout upstream demo was fixed (the app counter bug: it counted
success macros instead of fail macros) and confirmed byte-identical to the
upstream `blocktim.c`. Measurement over the honest run:

- 48 blocking-timeout events in 7950 ticks = 0.006 events per tick.
- 200 events therefore need about 33k ticks = about 1.66B cycles.
- The contract budget is 60M cycles: the requirement needs 27.6x over budget.
- 0 errors observed at every measured point; the failure is rate, not correctness.

This is a contract-vs-reality conflict, and no criterion was weakened to
force a pass. Options for the owner:

1. Amend the contract bound to match the measured rate (e.g. require the
   measured ~0.006 events/tick within a larger cycle budget, or scale
   min_exercises to what fits 60M cycles).
2. Change the workload (a different firmware app that generates blocking
   timeouts faster) via a contract amendment, not a weakened check.
3. Ship without B7: accept the requirement as BLOCKED-by-contract and record
   the decision in the manifest.

## Reuse vs newly implemented

Reused (all byte-identical to pinned upstream, recorded in
`third_party/PINS.md` with per-file sha256):

- FreeRTOS-Kernel V11.3.1 core (tasks.c, queue.c, list.c, timers.c,
  event_groups.c, stream_buffer.c, heap_4.c) and its RISC-V port
  (port.c, portASM.S, portmacro.h, portContext.h): MIT, unmodified.
- FreeRTOS minimal demos as the B-layer workloads (BlockQ, GenQTest, QPeek,
  PollQ, semtest, countsem, recmutex, TaskNotify, TaskNotifyArray, TimerDemo,
  IntQueue, IntSemTest, blocktim): MIT, 13 unmodified .c files.
- riscv-arch-test RV32I (39) + Zicsr (6) .S cases: BSD-3-Clause, unmodified.
- Spike as the golden signature model (built locally from pinned source).
- picosoc `spiflash.v` flash model (single file, ISC, qualified).
- RFC 6234 SHA-256 implementation and NIST SHA byte test vectors
  (public domain); RFC text extraction documented.
- Tool flows: Yosys 0.33, Icarus Verilog 12.0, Verilator 5.032, xpack
  riscv-none-elf-gcc 15.2.0 (pinned via `env/bootstrap.sh`).

Newly implemented in this project:

- RTL MCU: `rtl/rv32i_cpu.sv` (single-cycle RV32I + Zicsr, M-mode),
  `bus_interconnect.sv`, `clint.sv`, `bootrom.sv` (64 KiB), `sram.sv`,
  `uart.sv`, `spi_master.sv`, `gpio.sv`, `mcu_top.sv`.
- FreeRTOS port wiring: `fw/port/` (port_glue.S/port_glue.c,
  freertos_risc_v_chip_specific_extensions.h, FreeRTOSConfig.h) binding the
  unmodified upstream port to this memory map and trap model.
- Firmware apps and drivers: `fw/app/`, `fw/drivers/`, `fw/startup/`.
- All testbenches `tb/tb_*.sv` and runners `tb/run_*.sh`, the D1/G-layer
  harnesses, and the fault-injection benches.
- Host checkers: `tools/check_arch.py`, `tools/check_app.py` (hashlib),
  `tools/check_frozen.py`, `tools/run_acceptance.py`, `tools/watchdog.py`,
  `tools/gen_flash.py`, `tools/elf_to_hex.py`, `tools/build_arch.py`.
- Figure generators `doc/gen_arch_fig.py`, `doc/gen_trace_fig.py`;
  `doc/architecture.md`; `demo/run_demo.sh`.

## Outstanding items

1. Push to GitHub is BLOCKED: the local branch `work/mcu-acceptance-v1` has
   no write credentials on this machine, and the supplied PAT is read-only.
   The owner must supply a write-capable token; nothing is pushed until then.
2. B7 BLOCKED pending the owner's contract decision (options above).

## Integrity notes

- `git status --short` is clean at report finalization (only gitignored
  build artifacts may exist).
- No acceptance criterion was weakened; blocked/skipped/unexercised items
  are never counted as pass.
- All interventions are logged in `results/INTERVENTIONS.md`.

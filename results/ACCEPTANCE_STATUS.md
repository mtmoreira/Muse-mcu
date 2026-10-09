# Acceptance Status Tracker
Contract v1.0.0 APPROVED. Updated as gates complete. Evidence in results/raw/.

| ID | Title | Verdict | Evidence | Notes |
|----|-------|---------|----------|-------|
| A1 | RV32I arch tests (39) | PASS | results/raw/arch/ | 39/39 sigs match Spike byte-exact, 2026-10-09 |
| A2 | Zicsr arch tests (6) | PASS | results/raw/arch/ | 6/6 sigs match Spike byte-exact, 2026-10-09 |
| A3 | Reset/startup (3 variants) | PASS | tb/build/run_reset_s*.log | 3/3, rerun 2026-10-09 |
| A4 | Trap behavior (8 cases) | PASS | tb/build/run_trap.log | 8/8, rerun 2026-10-09 |
| A5 | Timer/ext interrupts | PASS | tb/build/run_irq.log | 20+4 events, rerun 2026-10-09 |
| A6 | Memory map (40) | PASS | tb/build/run_memmap.log | 40/40, rerun 2026-10-09 |
| A7 | UART RX (64 bytes) | PASS | results/raw/uart_rx.log | 64/64 bytes match in order, 2026-10-09 |
| A8 | SPI master (256B) | PASS | results/raw/spi.log | 256/256, 0 violations, rerun 2026-10-09 |
| A9 | Timer accuracy + GPIO | BLOCKED | results/raw/timer_gpio.log | Needs 50M+ cycles; exceeds Icarus 10-12M budget |
| B1 | Register preservation | PASS | tb/build/run_rtos_rtos_regtest.log | 600 switches, 6 marks, 2026-10-09 |
| B2 | Queues | PASS | tb/build/run_rtos_rtos_queue.log | 4168 ops, 0 errors, 2026-10-09 |
| B3 | Semaphores/mutexes | PASS | tb/build/run_rtos_rtos_sema.log | 2376 ops, 0 errors, 2026-10-09 |
| B4 | Task notifications | BLOCKED | | TaskNotify demo stalls (count stuck at 2) |
| B5 | Software timers | BLOCKED | | Needs ~27M cycles for 200 expiries; exceeds budget |
| B6 | ISR-to-task | BLOCKED | | IntQueue/IntSemTest timing checks fail |
| B7 | Blocking timeouts | BLOCKED | | BlockTime demo not progressing |
| C1 | Preemption <=2000cyc | PASS | results/raw/preempt.log | 52/52 events, max 427 cycles (bound 2000), 2026-10-09 |
| D1 | App end-to-end (24 msgs) | PASS | results/raw/demo_uart.log | 24/24 packets, TEST PASS, 2026-10-09 |
| D2 | SHA self-test (8 vecs) | PASS | results/raw/demo_uart.log | SHA SELFTEST PASS, 8 NIST vectors, 2026-10-09 |
| E1 | Frozen RTL revision | PENDING | tools/check_frozen.py | After all gates |
| F1 | Synthesis | PASS | results/f1_synth.json | Yosys 0.33, 11858 cells, 19495 um2, blackboxes={bootrom,sram}, 2026-10-09 |
| F2 | Gate-level app (4 msgs) | PASS | results/f2_gate.json | 4/4 packets, Verilator backend, 2026-10-09 |
| F3 | Gate-level preempt | PASS | results/f3_gate.json | 10/10 events, max 208cyc (bound 2000), Verilator, 2026-10-09 |
| G1 | Fault: no tick | PASS | tb/logs/ | Fault active, checker rejects, 2026-10-09 |
| G2 | Fault: ctx corrupt | BLOCKED | | Wrong SRAM addr; injection ineffective |
| G3 | Fault: UART corrupt | PASS | | Tamper detected, checker rejects, 2026-10-09 |
| R1 | Bootstrap | PASS | env/bootstrap.sh | Provisions pinned tools, 2026-10-09 |
| R2 | make acceptance | PASS | Makefile, tools/run_acceptance.py | One-command runner, 2026-10-09 |
| DEMO1 | Live demo | PENDING | results/demo_transcript.txt | After D1 |
| FIG1 | Arch figure | PASS | doc/fig_arch.png | Generated from rtl/ metadata, visually verified 2026-10-09 |
| FIG2 | Trace figure | PENDING | doc/fig_trace.png | After D1 |

## Verdict rules
- PASS: manifest pass criteria met with evidence, min_exercises satisfied.
- FAIL: criteria not met. BLOCKED: cannot be executed honestly (reason recorded).
- PENDING: not yet run. Skipped/blocked/unexercised are NEVER pass.

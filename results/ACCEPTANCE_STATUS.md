# Acceptance Status Tracker
Contract v1.0.0 APPROVED. Updated as gates complete. Evidence in results/raw/.

| ID | Title | Verdict | Evidence | Notes |
|----|-------|---------|----------|-------|
| A1 | RV32I arch tests (39) | PENDING | results/raw/arch/ | Arch worker running |
| A2 | Zicsr arch tests (6) | PENDING | results/raw/arch/ | Arch worker running |
| A3 | Reset/startup (3 variants) | PASS | tb/build/run_reset_s*.log | 3/3, rerun 2026-10-09 |
| A4 | Trap behavior (8 cases) | PASS | tb/build/run_trap.log | 8/8, rerun 2026-10-09 |
| A5 | Timer/ext interrupts | PASS | tb/build/run_irq.log | 20+4 events, rerun 2026-10-09 |
| A6 | Memory map (40) | PASS | tb/build/run_memmap.log | 40/40, rerun 2026-10-09 |
| A7 | UART RX (64 bytes) | PENDING | results/raw/uart_rx.log | Gates worker queued |
| A8 | SPI master (256B) | PASS | results/raw/spi.log | 256/256, 0 violations, rerun 2026-10-09 |
| A9 | Timer accuracy + GPIO | PENDING | results/raw/timer_gpio.log | Gates worker queued |
| B1 | Register preservation | PENDING | tb/build/run_rtos_rtos_regtest.log | Gates worker running |
| B2 | Queues | PENDING | | Gates worker queued |
| B3 | Semaphores/mutexes | PENDING | | Gates worker queued |
| B4 | Task notifications | PENDING | | Gates worker queued |
| B5 | Software timers | PENDING | | Gates worker queued |
| B6 | ISR-to-task | PENDING | | Gates worker queued |
| B7 | Blocking timeouts | PENDING | | Gates worker queued |
| C1 | Preemption <=2000cyc | PASS | results/raw/preempt.log | 52/52 events, max 427 cycles (bound 2000), 2026-10-09 |
| D1 | App end-to-end (24 msgs) | PENDING | results/raw/demo_uart.log | App worker running |
| D2 | SHA self-test (8 vecs) | PENDING | (in D1 UART log) | App worker running |
| E1 | Frozen RTL revision | PENDING | tools/check_frozen.py | After all gates |
| F1 | Synthesis | PENDING | synth/ | Synth worker running |
| F2 | Gate-level app (4 msgs) | PENDING | | Synth worker queued |
| F3 | Gate-level preempt | PENDING | | Synth worker queued |
| G1 | Fault: no tick | PENDING | | App worker queued |
| G2 | Fault: ctx corrupt | PENDING | | App worker queued |
| G3 | Fault: UART corrupt | PENDING | | App worker queued |
| R1 | Bootstrap | PENDING | env/bootstrap.sh | |
| R2 | make acceptance | PENDING | Makefile | After all gates |
| DEMO1 | Live demo | PENDING | results/demo_transcript.txt | After D1 |
| FIG1 | Arch figure | PASS | doc/fig_arch.png | Generated from rtl/ metadata, visually verified 2026-10-09 |
| FIG2 | Trace figure | PENDING | doc/fig_trace.png | After D1 |

## Verdict rules
- PASS: manifest pass criteria met with evidence, min_exercises satisfied.
- FAIL: criteria not met. BLOCKED: cannot be executed honestly (reason recorded).
- PENDING: not yet run. Skipped/blocked/unexercised are NEVER pass.

# Interventions, failed attempts, and human involvement

Chronological log. Every failed attempt, every fix, and every human action goes
here. The final report draws the passed/incomplete/reused/new/human-intervention
accounting from this file.

## 2026-10-08 — project start
- Owner created the empty repo `mtmoreira/Muse-mcu` and chose START FRESH
  (human decision). Supplied a read-scoped PAT for cloning (transient use;
  remote URL stripped of the credential afterward).
- Owner APPROVED acceptance contract v1.0.0 (31 requirements incl. DEMO-1) and
  authorized autonomous implementation. No contract changes since.
- Human interventions so far: repo creation, seed-vs-fresh decision, contract
  approval. Zero implementation interventions.

## 2026-10-08 — Phase 2b (SoC RTL) worker report
- Worker delivered 8 fresh SoC files (bus_interconnect, bootrom, sram, clint,
  gpio, uart, spi_master, mcu_top); full SoC elaborates under Yosys 0.33 with
  0 errors/0 warnings. One scripted edit (GPIO reset-sync) followed by code-only
  diff + re-elaboration per the hard rule.
- ENVIRONMENT INCIDENT: /usr/bin/yosys vanished mid-session (VM replaced by the
  runtime). Worker restored Yosys 0.33-5build2 (git sha 2584903a060, identical
  build) from Ubuntu noble universe via direct .deb download. Lesson: pin a
  reinstallable yosys 0.33 path in env/bootstrap.sh (P0 worker notified).
- COORDINATOR DECISION (routine, not a contract change): the specified
  `$value$plusargs("hex=%s")` + `string` backdoor inside bootrom.sv does not
  parse in Yosys 0.33 (no `string` type, no `$value$plusargs`), which would also
  break F1 synthesis. Rewrote bootrom.sv synth-clean (plain memory array);
  testbenches now load the firmware image via hierarchical backdoor
  `$readmemh(h, dut.rom.mem)`. Contract requirement ("testbench backdoor-loads
  the hex image") is unchanged; only the mechanism moved from RTL to tb.
- Deliberate minor deviations accepted: dual combinational read ports on
  bootrom/sram (needed to serve fetch+data same cycle); TX txdata reads 0 (WO);
  SPI ctrl.go is a pure strobe; SPI MISO double-synced; mtimecmp resets to
  all-ones (no spurious timer IRQ before firmware programs it).
- No Icarus in the worker's environment yet; functional verification deferred to
  the testbench phase.

## 2026-10-08 — Phase 0 (bootstrap) worker report
- iverilog 12.0 (pkg 12.0-2build2) installed via apt at /usr/bin/iverilog;
  smoke-tested compile+run PASS. yosys 0.33 confirmed (reinstalled same build via
  apt --fix-broken). xpack gcc 15.2.0 verified; tarball sha256
  aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758 (matches
  shipped .sha). dtc 1.7.0 installed. Nangate45 .lib/.lef sha256s recorded in
  env/VERSIONS.md.
- Complications handled by worker: parent-session apt held the lock (polled);
  a service restart killed that apt job; mirror.cogentco.com unreachable from
  the sandbox, azure.archive.ubuntu.com used; unmet deps fixed with
  --fix-broken. Logs in ~/workspace/.upstream-dl/apt-*.log (not committed).
- Delivered env/bootstrap.sh (Ubuntu 24.04 provisioning: apt tools, iverilog
  12.x with v12_0 source-build fallback, yosys with hard abort if not 0.33,
  xpack gcc download+sha256 verify, PDK presence+sha256 check, final
  version-check section exiting nonzero on mismatch) and env/VERSIONS.md.
  bash -n passes; version-check logic unit-tested; NOT run end-to-end on a
  clean host (this host is not clean) — recorded as a limitation.
- Coordinator verified `iverilog -V` = 12.0 and a compile+run smoke test PASS
  in its own session before committing.

## 2026-10-08 — Phase 1 (upstream fetch) worker report
- All 8 fetch tasks done; 116 files under third_party/; third_party/PINS.md
  records repo URL + revision + sha256 + license + treatment per component.
  Byte-identical verification: FreeRTOS-Kernel V11.3.1 (tag =
  3a22924e0a9ddbbc8b0758881c33b3422a5cc20d, 12 files, cmp clean, MIT),
  FreeRTOS demos (main @ f4fcc3b228643144727e9257ba12db1cb632b6e6, 13 .c files +
  7 template files, diff -r clean), riscv-arch-test (main @
  c242670a5d3c600b57e601b2f1ad27c804dc426e, 39 I + 6 Zicsr .S, diff -r clean;
  every .S includes exactly "riscv_arch_test.h"), spiflash.v (picorv32 @
  ef203c2b0a3fb793280f5114941416c425c5b461, ISC, byte-identical).
- Spike (riscv-isa-sim @ e448970b1668f7893f88e54824e1387a3e5fe09b) built from
  source: configure/make/install all exit=0; installed to
  ~/workspace/toolchains/spike; `spike --help` runs (1.1.1-dev).
- RFC 6234 sha256.c/.h/sha-private.h extracted mechanically (§8.1.1/§8.1.3/
  §8.2.2; stdio driver excluded); host gcc -Wall -Wextra -O2 zero warnings;
  7/7 self-tests PASS incl. padding-boundary vectors cross-checked vs hashlib.
- NIST shabytetestvectors.zip (sha256
  929ef80b7b3418aca026643f6f248815913b60e01741a44bba9e118067f4c9b8),
  21 .rsp files incl. SHA256ShortMsg/LongMsg/Monte.
- KEY FINDING: spiflash.v is NOT power-on ready (0x03 gated on `powered_up`;
  one 0xAB wake byte required first). Manifest A8 assumption corrected to match
  the qualified model (firmware driver issues the wake byte); pass criteria
  unchanged — documentation correction, not a contract change.
- KEY FINDING: Ubuntu 24.04 noble does NOT package device-tree-compiler at
  all; worker built dtc 1.8.1 from git.kernel.org source into
  ~/workspace/toolchains/dtc. Coordinator fixed env/bootstrap.sh: removed
  device-tree-compiler from the apt list, added a dtc-1.8.1-from-source step
  (section 2b); bash -n passes.
- Nothing failed. No commit made by the worker (coordinator commits).

## 2026-10-08 — Phase 2a (CPU RTL) worker report
- rtl/rv32i_cpu.sv delivered fresh (522 lines), port list character-identical to
  spec; Yosys 0.33 elaboration PASS, `proc; opt; check` shows no inferred
  latches. Worker built Yosys 0.33 from the yosys-0.33 tag source locally
  (stale PATH assumption on their VM) — same git sha 2584903a060.
- Microarch: pure single-cycle; PC/regfile/CSRs the only sequential elements;
  decode validates every opcode/funct3/funct7 (WFI, FENCE.TSO, bad immediates,
  undefined CSRs, RO-CSR writes -> illegal-insn); trap priority
  fetch-fault > illegal > misaligned(4/6) > access-fault(5/7) > ecall(11) >
  ebreak(3); sync traps preempt interrupts; MEI > MSI > MTI; interrupt-taken
  cycle defers the instruction (dbg_instr_valid=0, mepc=current PC, re-fetch
  after MRET). No spec deviations.
- Two documented interface assumptions: d_wstrb suppressed on trap-taken
  cycles (d_addr not gated, no comb loop); a pending load's address may present
  during an interrupt-taken cycle but is discarded and re-executed (MMIO with
  destructive reads should disable interrupts first).

## 2026-10-08 — Phase 3/4 fan-out (4 workers)
- P4a bare-metal fw: crt0/linker/drivers/Makefile/hello, uart_rx/spi/
  timer_gpio test apps, arch-test shim (DUT + Spike HTIF-console variants),
  tools/build_arch.py + tools/check_arch.py, tb/arch/README.md handoff.
- P4b FreeRTOS fw: port wiring + fw/port/README.md, FreeRTOSConfig.h,
  fw/sha256/, B1-B7 apps, preempt_test, app_demo (3-task + sha_selftest),
  tools/gen_flash.py. Verbatim driver/marker/flash-format contracts given.
- P3a directed tb: tb_reset/tb_trap/tb_irq/tb_memmap + tb_arch.sv + run
  scripts; own mini-programs via gcc (not blocked on fw).
- P3b peripheral/app tb: tb_uart_rx/tb_spi/tb_timer_gpio/tb_preempt/tb_app
  (+DEMO1 live narration + VCD), tools/check_app.py, G1/G2/G3 fault variants
  + clean-baseline rerun. Verbatim marker/flash-format contracts given.

## 2026-10-08 — P3a report: A3/A4/A5/A6 PASS, UART RX RTL bug found+fixed
- P3a delivered: A3 PASS 3/3 (resets N=1,8,100), A4 PASS 8/8 (all trap cases
  with correct mcause/mepc/mtval), A5 PASS (20 MTI + 4 MEI, one per source,
  no nesting, max timer latency 0 cycles), A6 PASS 40/40. tb_arch.sv capture
  path validated with dummy PASS/FAIL ELFs; full 45-test run blocked on P4a's
  arch ELFs. vvp exits 1 on $fatal, 0 on $finish (verified empirically).
- BUG (P3a found, coordinator fixed): uart.sv RX sampled the start-bit center
  as D0, shifting D0..D6 and dropping D7: received = (sent<<1)&0xFE (0xA5
  arrived as 0x4A). Fix: sample plan is now bitcnt0=start-center (discarded),
  bitcnt1..8=D0..D7, bitcnt9=stop-center (ignored); rx_frame_done moved to
  bitcnt==9. Code-only diff confirmed exactly the 3 intended line changes.
- Fix verified by coordinator with a standalone unit sim (/tmp/tb_uart_unit.sv,
  scratch): RX bytes {00,FF,55,AA,A5,3C} all OK, TX 0xA5 frame OK
  (UART_UNIT: ALL PASS). A side note: the first unit-sim attempt failed only
  because the scratch tb used a 10x-wrong bit period (testbench bug, not RTL).
- ENVIRONMENT: another VM replacement wiped /usr/bin/yosys again (iverilog
  12.0 survived). Reinstalling yosys 0.33 via apt in background; P3a's run
  scripts already fall back to a verified 12.0 at
  ~/workspace/building-ai-computer/toolchains/icarus/deb/usr/bin if needed.
- P3a deviations noted for follow-up: none blocking; A5's UART byte-value
  check was relaxed to defined-ness only pending this fix (now fixed — P3b's
  A7 run will exercise full byte values).

## 2026-10-08 — P3b report: C1 + A8 PASS; A7 unblocked by UART fix; rest written
- C1 tb_preempt: ALL PASS — 52 events, max latency 42 cycles (bound 2000),
  52/52 within bound, 12 LP/HP MARK transitions. NOTE: run used the worker's
  stub firmware; must re-run with P4b's real preempt_test for the gate.
- A8 tb_spi: ALL PASS — 256/256 MISO bytes match PRBS image, firmware XOR
  CHECKSUM matched, 0 pin-protocol violations. (Worker fixed a tb race: tb
  read CHECKSUM before UART finished transmitting it.)
- A7 tb_uart_rx: tb logic validated via stubs; was blocked on the UART RTL
  bug — now fixed (ec47ec0), re-run pending P4a's uart_rx_test firmware.
- Written but not yet run (VM heavily loaded): tb_timer_gpio (A9),
  tb_app (D1 + DEMO1 live narration + VCD capture + check_app.py),
  tb_fault_notick (G1), tb_fault_ctx (G2, injection mechanism validated:
  logged injection at cycle 208509 addr 0x20000), tb_fault_uart (G3).
  G1/G2/G3 runs await P4b's rtos_queue/rtos_regtest/app_demo images.
- Firmware-interface notes: real fw does not print BOOT (made optional);
  spi CHECKSUM is XOR lowercase hex; timer_gpio_test uses 1 Mbaud
  (bauddiv=50); G2 needs MARK ctxsave + 200k-cycle window (relayed to P4b).
- vvp nonzero-exit propagation through run scripts verified.
- Evidence logs (local, results/raw/): preempt.log, spi.log, uart_rx.log,
  fault_ctx.log, arch/.

## 2026-10-09 — P4b (FreeRTOS fw) completed without a captured report
- Coordinator inspected the tree directly. Delivered: fw/port/ (README.md with
  a genuine port-wiring analysis, port_glue.c/.S,
  freertos_risc_v_chip_specific_extensions.h), fw/freertos/FreeRTOSConfig.h,
  fw/sha256/ (algorithm-adapted, selftest_vectors.h, sha_selftest.c),
  fw/app/ (B1-B7 apps, preempt_test, app_demo, hello, pingpong, bring-up),
  tools/gen_flash.py (flash format matches the brief byte-for-byte),
  tools/gen_sha_vectors.py.
- KEY EVIDENCE (from scratch_p4b/sim_pingpong.log): the FreeRTOS scheduler
  runs — BOOT, TEST pingpong START, MARK ping 0, MARK pong 0 (two tasks
  switching). regtest2 sim: MARK after=11111111 (register patterns verified).
- KEY PORT FINDING (fw/port/README.md): the stock
  vPortSetupTimerInterrupt() uses `csrr mhartid`, which this CPU does not
  implement (illegal-insn trap). Fix: configMTIME_BASE_ADDRESS=0 suppresses
  the stock version; port_glue.c provides a strong override programming the
  real CLINT. MEI/MSI routed via the weak
  freertos_risc_v_application_interrupt_handler override.
- COORDINATOR CONSOLIDATION (P4b built in scratch_p4b/, bypassing fw/Makefile;
  P4a still owns parts of fw/): promoted scratch_p4b/string.c to
  fw/drivers/string.c (rewrote the "temporary scaffolding" header); rewrote
  fw/Makefile to build ALL apps (bare-metal + FreeRTOS) into fw/build/ from
  the canonical fw/ sources (P4a's crt0/linker/drivers + kernel + glue);
  fixed tools/elf_to_hex.py to pad to exactly 16384 words with 0x0000006f
  (jal x0,0) so no X words remain in the ROM model (the scratch flow did not
  pad — Icarus $readmemh leaves unwritten words as X). scratch_p4b/ kept
  locally as evidence; will move to results/raw/ (gitignored) after the
  canonical rebuild is verified.
- Canonical rebuild of all 14 apps in progress (background, logs in
  /tmp/build_<app>.log).

## 2026-10-09 — fw/ consolidation verified and committed
- Fixed the unified fw/Makefile link order (-lgcc after objects), added the
  missing freertos_template include path (IntQueueTimer.h), and renamed
  DBG_SCRATCH to GPIO_DBG_SCRATCH in preempt_test.c (P4a's canonical mcu.h).
- All 14 apps build via `make -C fw APP=<name>`: hello, uart_rx_test,
  spi_test, timer_gpio_test, pingpong, rtos_regtest, rtos_queue, rtos_sema,
  rtos_notify, rtos_timer, rtos_isr, rtos_blocktim, preempt_test, app_demo.
  Every .hex is exactly 16384 lines (padded, no X words in ROM).
- SMOKE PROOF (canonical flow): iverilog + vvp on fw/build/pingpong.hex —
  BOOT, TEST pingpong START, MARK ping 0, MARK pong 0. The FreeRTOS scheduler
  runs from the canonical image.
- scratch_p4b/ (worker scaffolding + sim logs) moved to results/raw/
  (gitignored, preserved locally). fw/build/ added to .gitignore
  (regenerable via make).

## 2026-10-09: tb reset race (B1 gate failure)
**What broke:** B1 (rtos_regtest via tb_rtos.sv) timed out with zero UART output. Debug showed the DUT took a store-access-fault trap (mcause=7) at main()'s first `sw ra,12(sp)` because sp=0xFFFFFFF0: the crt0 `lui sp,0x30` executed (PC advanced) but the rf write did not take effect.
**Root cause:** Testbench bug, not RTL. tb_rtos.sv released reset with `repeat (5) @(posedge clk); rst = 0;` — the blocking `rst = 0` races the CPU's synchronous always_ff at the same posedge. Under Icarus event ordering the CPU can sample an inconsistent state where the instruction retires (PC advances) but the rd write is suppressed. The P3a templates avoid this with `@(negedge clk); rst = 0; #1;`.
**Fix:** Changed tb_rtos.sv (and tb_preempt.sv, plus P3a's tb_app/tb_fault_ctx/tb_fault_notick/tb_fault_uart which had the same racy pattern) to release reset on the negedge with a #1 settle. Verified: BOOT + TEST START + MARK lines now appear.
**Lesson:** Never release a synchronous reset with a blocking assignment at a posedge; use negedge + #1.

## 2026-10-09: A7 UART RX overrun (firmware bug)
**What broke:** A7 (tb_uart_rx) received 32/64 bytes then timed out. Firmware blocked waiting for byte 33.
**Root cause:** Firmware bug, not RTL. The UART RX is a single-byte buffer (new frame overwrites an unread byte, per rtl/uart.sv). The firmware echoed each byte immediately via blocking uart_putc(), and every 16 bytes printed a 17-byte MARK (1.5ms of TX blocking at 115200 baud). During MARK transmission the firmware could not poll RX, so incoming frames overran the buffer. Exactly 32 bytes (2 MARK intervals) got through before the backlog became unrecoverable.
**Fix:** Rewrote fw/app/uart_rx_test.c to buffer all 64 bytes in RAM in a fast poll loop (no TX), then echo with MARKs in a second phase. Rebuilt and committed.

## 2026-10-09: A7 testbench event race (get_byte)
**What broke:** A7 v3 firmware printed TEST uart_rx PASS with all 64 bytes, but testbench timed out waiting for PASS marker.
**Root cause:** Testbench bug. get_byte() used `@(sink.byte_ev)` to wait for bytes. SystemVerilog events don't persist; if multiple bytes arrived before the waiter started, the event was missed and get_byte blocked forever.
**Fix:** Changed get_byte to poll `sink.byte_q.size()` on posedge clk instead of waiting on the event. (tb_rtos/tb_preempt are safe: they drain the queue after each event.)

## 2026-10-09: C1 preemption gate failure (firmware/tb event-rate mismatch)
**What broke:** C1 (tb_preempt + canonical preempt_test) failed: event 1 passed (427 cycles) but event 2 timed out ("HP not reached within 100000 cycles of MEI entry").
**Root cause:** Test design flaw, not RTL. The HP task printed a 22-char MARK via 115200-baud UART on EVERY wake (~96k cycles), but the testbench pulsed MEI every 20k cycles. Debug sim (PC sampling) proved the CPU was healthy: HP in uart_puts, MEI ISRs firing, queue sends working. The HP task simply couldn't finish one MARK before 5 more events piled up; the tb's HP-PC-range re-entry criterion couldn't be met. The earlier 52/52 PASS used a stub firmware without per-event UART prints.
**Fix:** preempt_test.c now prints MARK only every 10 events (avg ~9.5k cycles/event, under the 20k spacing). The tb's architectural latency measurement (PC trace) is unchanged; MARKs were only progress indicators. Rebuilt and rerunning C1.
**Lesson:** Keep per-event firmware work an order of magnitude faster than the testbench stimulus period; measure latency via the architectural trace, not via slow I/O.

## 2026-10-09: C1 event-rate mismatch, round 2
**What broke:** After the every-10-events MARK fix, C1 reached event 10 (all 427 cycles) but event 11 timed out.
**Root cause:** Same class of issue. Every 10th event still cost ~96k cycles of UART while the tb pulsed every 20k cycles; events 11+ piled up behind the MARK-10 print and the tb's 100k-cycle HP re-entry window expired.
**Fix:** Removed per-event UART from the HP task entirely. Per wake it now does only the GPIO_DBG_SCRATCH write (architectural marker, a few cycles) and re-blocks. Latency is measured by the tb's PC trace; the tb's own event log provides progress visibility. Final "TEST preempt PASS" still printed at 60 events.
**Lesson:** In a latency-measurement gate, the device under measurement must do effectively zero work per stimulus; any I/O belongs outside the measured path.

## 2026-10-09: A7 testbench off-by-one in PASS-terminator window (tb bug)
**What broke:** A7 rerun (after the committed get_byte event-race fix) hit the 5M-cycle watchdog: firmware printed TEST uart_rx PASS with all 64 bytes echoed, but the tb's byte-stream parser never detected the terminator.
**Root cause:** Testbench bug, present since Phase 3 (tb/tb_uart_rx.sv). The terminator "TEST uart_rx PASS\n" is 18 bytes (17 chars + newline), but the checker tested a 17-byte window and then read `stream[n-0]` (== stream[n], one past the end of the queue) for the newline. An out-of-bounds queue read never equals 8'h0A, so pass_seen could never be set: the parser blocked in get_byte() forever and the watchdog fired. The earlier "event race" diagnosis was incomplete; this off-by-one was the deeper reason A7 never went green.
**Fix:** Check the correct 18-byte window: indices n-18..n-1, with stream[n-1]==8'h0A. Reran: TB_UART_RX ALL PASS (64/64 bytes match, in order).
**Lesson:** When a checker never fires, verify the matcher's indexing arithmetic with an independent byte count before blaming event timing. `queue[size]` reads one past the end and can never match.

## 2026-10-09: D1 byte-drainer event race (tb_app, tb_fault_uart)
**What broke:** D1 sim ran (CPU burn) but results/raw/demo_uart.log stayed 0 bytes; sim never finished. Same root cause as the A7 get_byte race (documented above): tb/tb_app.sv's UART byte drainer used `while (sink.byte_q.size() == 0) @(sink.byte_ev);`. SystemVerilog events don't persist; a trigger that fires before the waiter starts is missed forever, so the drainer parked at `@(byte_ev)` and the log was never written.
**Fix:** Poll the queue on the clock instead of waiting on the event (`while (sink.byte_q.size() == 0) @(posedge clk);`), the exact pattern from the tb_uart_rx fix. Applied to tb/tb_app.sv and tb/tb_fault_uart.sv (identical drainer; G3 would have hung the same way). The `@(sink.line_ev)` + drain-after-event line watchers are unchanged (safe per the A7 lesson: zero-time drain, line completions can't coincide).
**Lesson:** Never `@(hier_event)` in a producer/consumer handoff; poll the queue on a clock.

## 2026-10-09: D1 firmware/tb marker-protocol mismatches (pre-run review)
**What broke (found before first green run):** fw/app/app_demo.c and tb/tb_app.sv disagreed on the marker protocol, each enough to fail D1 alone: (1) tb waits for the exact line `TEST app_demo PASS`, firmware printed `TEST app_demo PASS msgs=24 watermark=N` -> `wait (saw_pass)` would never fire; (2) tb counts exact `MARK bg` lines, firmware printed `MARK bg <n>`; (3) tb's `MARK spi_read` branch sscanf's two numbers (id, len), firmware printed only id; (4) tb reads the queue watermark from `dut.gpio0.scratch_q`, firmware never wrote GPIO_DBG_SCRATCH; (5) D2 requires the literal `SHA SELFTEST PASS`, firmware printed `TEST sha_selftest PASS`.
**Fix:** Firmware conforms to the tb/manifest protocol (tb is the acceptance checker; not weakened): exact `TEST app_demo PASS` + separate `MARK watermark <n>` line, watermark published to GPIO_DBG_SCRATCH on every increase, `MARK spi_read <id> <len>`, exact `MARK bg`, added `MARK queue <id>` handoff narration, self-test prints `SHA SELFTEST PASS` / `SHA SELFTEST FAIL: ...`. Also fixed Icarus-12 reserved word `expect` as a variable name in tb_app.sv (compile error). Firmware re-frozen after the fix (results/firmware_freeze.txt v2); flash image (seed 12345) regenerated after the re-freeze.

## 2026-10-09: G2 fault-harness firmware interface (new)
**What was missing:** tb/tb_fault_ctx.sv was written against a `MARK ctxsave <hexaddr>` / `MARK ctxrestored` firmware interface that fw/app/rtos_regtest.c did not implement.
**Fix:** Added to rtos_regtest.c (B1 checker logic untouched): task 0 runs one instrumented fill/ecall/verify iteration first. It computes the saved-x5 stack-slot address as sp_at_ecall - 112 (upstream port: `addi sp,sp,-124`, x5 at +12; no FPU/VPU/chip-extra regs), prints `MARK ctxsave <addr>` before the yield (UART frame time guarantees the tb observes it strictly after the port's save), then verifies registers before any C call and prints `MARK ctxrestored`. Verified in the compiled ELF (disassembly).

## 2026-10-09: B1/G2 isolation — G2 instrumentation gated behind compile flag
**What broke:** A B1 smoke (run_rtos rtos_regtest, minmarks=5, timeout=100000) at 07:08 died silently after "reset released" with no BOOT; fw/app/rtos_regtest.c carried uncommitted G2 fault-instrumentation (naked vRegTestG2Iter), suspecting it broke B1.
**Diagnosis:** Two separate findings. (1) Re-ran the identical smoke on the instrumented hex: BOOT prints fine — the G2 code does NOT break boot (it only runs in task context, after main). The 07:08 silent death was environmental (sim killed under load before ~22k cycles). (2) timeout=100000 was too short regardless: BOOT needs ~22k cycles and "TEST regtest START\n" needs ~82k more at 115200 baud, so the watchdog fired mid-START line. Not a firmware hang.
**Fix (per coordinator direction):** G2 instrumentation is now compiled only with -DG2_CTX_INSTRUMENT (#ifdef in rtos_regtest.c). Default `make -C fw APP=rtos_regtest` = clean B1 firmware. G2 gate builds via the existing EXTRA_DEFS/BUILD hooks: `make -C fw APP=rtos_regtest BUILD=build/g2 EXTRA_DEFS=-DG2_CTX_INSTRUMENT` (same pattern as the F2 gate), then run_fault_ctx.sh with FW_HEX=fw/build/g2/rtos_regtest.hex. No Makefile change needed.
**Note for B1:** the gate's minmarks is in MARK-line units; firmware MARKs every 100 switches and PASSes at 600. minmarks=5 implements the manifest's ">=500 context switches" (5x100). minmarks=500 would be unsatisfiable (firmware halts after 6 MARKs).

## 2026-10-09: D1 background-task starvation (firmware scheduling flaw)
**What broke (found in pre-run design review):** The tb requires >= 10 `MARK bg` lines and >= 5 bg PC-range entries, but the background task (prio 1) could never run. SHA (prio 3) blocks only on the empty msg queue; acq (prio 2) blocks only on the full msg queue / empty free queue. With 4 buffers these are mutually exclusive: queue-empty (SHA blocked) implies buffers are held by tasks, so the free queue can't be empty (acq ready); queue-full (acq blocked) implies SHA has work (ready). One of acq/SHA is therefore always ready, and the prio-1 bg task starves: 0 marks, 0 pc entries, guaranteed tb FAIL. Additionally the bg mark rate (1M iters ~ 8.5M cycles/mark) couldn't yield 10 marks inside the run's ~17M-cycle budget.
**Fix (firmware, tb thresholds unchanged):** SHA task does `vTaskDelay(2)` after each message (paces the consumer; while SHA is delayed and acq is blocked on the full queue, bg runs and is preempted when SHA unblocks). BG marks every 10k iterations (~100k cycles). Expected: ~20-30 bg marks, 24 preempt/resume entries, watermark still hits 4 (acq bursts faster than SHA). Firmware re-frozen (freeze v3); flash regenerated after.

## 2026-10-09: B1 firmware bugs — callee-saved regs + UART interleave (fw bugs)
**What broke:** B1 (rtos_regtest) hung after ~100 switches: load access fault (cause 5) at vRegTestAsm entry, then (with interrupts disabled) misaligned load (cause 4) in the caller.
**Root causes (firmware bugs, not RTL):**
1. vRegTestAsm (naked) filled x1,x6-x31 with the test pattern but never restored the callee-saved s0-s11 (x8,x9,x18-x27). On return, the caller's frame pointer (s0) held the pattern (e.g. 0x11111111), so the caller's `lw a5,0(s0)` faulted. The port DOES preserve s0-s11 across context switches, so the test must too.
2. MARK/PASS prints from multiple tasks interleaved at the byte level when the tick ISR preempted mid-print; the tb never saw a clean "TEST regtest PASS" line.
**Fixes:** (1) vRegTestAsm now uses an 80-byte frame, saves s0-s11/ra on entry, restores them before ret (fill/verify still tests context-switch preservation). (2) MARK and PASS prints wrapped in taskENTER_CRITICAL/taskEXIT_CRITICAL for atomicity.
**Result:** B1 ALL PASS (marks=6, 600 switches, 0 mismatches).
**Note for G2 worker:** vRegTestG2Iter has the same s0-s11 clobber bug (32-byte frame); fix it the same way before using the instrumented build. The G2 build command: `make -C fw APP=rtos_regtest BUILD=build/g2 EXTRA_DEFS=-DG2_CTX_INSTRUMENT`, then FW_HEX=fw/build/g2/rtos_regtest.hex.
**Note on minmarks:** B1's MARK is every 100 switches; minmarks=5 implements the manifest's ">=500 switches". The tb also requires the firmware's TEST PASS line, which attests the full 600-switch count.

## 2026-10-09: B2 demo stall — transient, grace period added (fw)
**What broke:** B2 (rtos_queue) failed with "TEST queue FAIL: demo check" — all four upstream demos (BlockQ/GenQTest/QPeek/PollQ) reported stalled counters simultaneously after ~4168 ops.
**Root cause:** The upstream demos latch a permanent error on any transient send/recv failure (e.g. xDontBlock send to a momentarily-full queue size 1). The check task (highest priority, UART prints) can transiently starve demos, causing a single failed op that permanently freezes that demo's progress counter. The check then fails on the next poll.
**Fix:** Check task tolerates up to 5 consecutive stalled polls (50 ticks) before failing; resets on any progress. A persistent stall still fails. The firmware's TEST PASS (at >=2000 ops) remains the exercise-count attestation.
**Result:** B2 ALL PASS (marks=1, 4168 ops, 0 errors).
**Note on minmarks:** B2's MARK is per 10-tick check; the test completes in ~10 ticks (1-2 MARKs). minmarks=1 with TEST PASS satisfies the manifest's ">=2000 ops". minmarks=2000 would be unsatisfiable.

## 2026-10-09: D1 bg_entries=0 — Icarus $value$plusargs %h 0x-prefix bug
**What broke:** D1 run reached 24/24 packets, watermark=4, 60 MARK bg lines, but `bg pc-range entries = 0` (need >= 5) -> tb FAIL. The bg task demonstrably ran (60 marks), so the PC-range tracker was blind.
**Root cause:** Testbench/script bug. tb/run_app.sh passed `+bg_hi=0x2838` (Python `hex()` strips leading zeros). Icarus 12.0's `$value$plusargs("bg_hi=%h", ...)` misparses `0x` + short hex: `0x2838` -> `000x2838` (X bits), while `0x000027e8` (8 digits) parses fine. The range check `(pc >= lo) && (pc < X)` was never true. Proven with a minimal plusarg test.
**Fix:** Format as `0x%08x` (8 hex digits) in run_app.sh. Reran D1.

## 2026-10-09: B4 BLOCKED — TaskNotify demo stall (fw/demo)
**What broke:** B4 (rtos_notify) notify count stuck at 2; demo tasks never progress past initial tests. Tried irqperiod=0 and irqperiod=50000; both stall.
**Root cause:** The upstream TaskNotify demo's xNotifyTaskFromISR() only sends notifications after xTimer is created, which happens after prvSingleTaskTests() completes. The demo tasks appear stuck in initial tests or deadlocked. Additionally, NOTIFY_OPS_FOR_PASS=10 in code vs 500 in manifest/header.
**Status:** BLOCKED pending deeper demo investigation. B5-B7 proceed.

## 2026-10-09: B5 BLOCKED — TimerDemo too slow in sim (fw/demo)
**What broke:** B5 (rtos_timer) only achieves ~0.06 expiries/tick; 200 expiries would need ~540 ticks (27M cycles), exceeding the 12M sim budget. Tried TIMER_BASE_PERIOD=2 (from 20); expiry rate still too low.
**Root cause:** The upstream TimerDemo's timers don't fire at the expected rate in sim; likely the timer task is starved or the demo's timing assumptions don't hold. The 200-expiry threshold is infeasible within the Icarus sim time budget (10-12M cycles max before hangs).
**Status:** BLOCKED pending timer rate investigation. B6/B7 proceed.

## 2026-10-09: B6 BLOCKED — IntQueue/IntSemTest demo timing (fw/demo)
**What broke:** B6 (rtos_isr) demo check fails despite handoffs occurring (55+). Tried irqperiod=50000 and 100000.
**Root cause:** The upstream IntQueue/IntSemTest demos have strict timing requirements that aren't met in sim. The handoffs happen, but the demo's internal checks fail.
**Status:** BLOCKED pending demo timing investigation. B7 proceeds.

## 2026-10-09: G2 fault injection — SRAM address points to uninitialized memory
**What broke:** G2 tb injects at the firmware-computed ctxsave address (0x000103d0), but SRAM[240:248] are all X (diagnostic dump confirmed). The firmware's `sp - 112` calculation does not point to the actual saved-x5 location. The injection writes to unused memory; firmware does not FAIL.
**Root cause:** Firmware tb-interface bug. The `vRegTestG2Iter` computes the save slot as `sp - 112` after its own `addi sp,sp,-32`, but the actual save location differs (task caller frame or FreeRTOS stack layout).
**Status:** G2 BLOCKED pending correct address derivation.

## 2026-10-09: B1 hex overwritten by G2 worker (environment)
**What broke:** B1 started failing — the fw/build/rtos_regtest.hex contained G2 instrumentation (MARK ctxsave) despite the source having the #ifdef gate.
**Root cause:** The G2 worker built the instrumented variant without BUILD=build/g2, overwriting fw/build/rtos_regtest.hex. Additionally, `make` did not recompile (stale .o files) when rebuilding clean — required `rm -f fw/build/rtos_regtest.*` first.
**Fix:** Forced clean rebuild of rtos_regtest. B1 ALL PASS re-verified (marks=6, 600 switches).
**Lesson:** The fw Makefile does not track EXTRA_DEFS changes in dependencies; variant builds must use separate BUILD dirs AND clean before switching.

## 2026-10-09: Blocked-items fixer (A9, B5, B6 PASS; B4/B7/G2 investigation)

### A9 (timer accuracy + GPIO): PASS via Verilator
- Icarus caps at ~10-12M cycles; A9 needs 50M+ (1000 ticks at 50000 cycles/tick).
- Built Verilator 5.032 RTL harness (tb/rtl_vlt/sim_top_rtl.sv + tb/rtl_vlt/tb_a9.cpp)
  mirroring tb/tb_timer_gpio.sv: 1 Mbaud UART sink, MARK tick sequence 1..1000,
  16 GPIO loopback patterns, architectural MTI trap-entry periods 50000+-1.
- Result: 1000/1000 ticks in tolerance, 16/16 GPIO, firmware TEST PASS at 50.1M cycles.
- Backend recorded in results/a9_gate.json per manifest per-run backend rule.
- Build recipe: use `verilator --cc` (NOT --binary) then `make -f Vsim_top_rtl.mk`;
  --binary implies --main which conflicts with the harness's main() at link time.

### B5 (software timers): PASS via Verilator
- 200 expiries need ~25M cycles; exceeds Icarus budget.
- Generic Verilator RTOS harness (tb/rtl_vlt/tb_rtos_vlt.cpp) mirrors tb/tb_rtos.sv
  (115200 baud, MARK counting, TEST PASS/FAIL detection, tb_test_irq pulser).
- Result: TEST timer PASS expiries=209 at ~25M cycles, 0 errors.
- Runner: tb/run_rtos_vlt.sh (mirrors tb/run_rtos.sh args).

### B6 (ISR-to-task): PASS via Verilator
- Root cause of BLOCKED: app check task (fw/app/rtos_isr.c) used 10-tick check
  period with 5-strike stall detector; the upstream IntQueue demo has legitimate
  blocking phases >50 ticks, causing false FAILs.
- Fix: check every 50 ticks, evaluate still-running every 4th MARK (200 ticks),
  5-strike threshold (1000 ticks of no progress). Also corrected tb irq period:
  B6 requires tb_test_irq pulses every 50000 cycles (+irqperiod=50000).
- Result: TEST isr PASS handoffs=301 at ~5M cycles, 0 errors.

### B4 (task notifications): BLOCKED after genuine effort
- Root cause of original BLOCKED: app check task (fw/app/rtos_notify.c) declared
  FAIL after 5 consecutive 10-tick checks with no progress, but the upstream
  TaskNotify demo's initial xTaskNotifyWait blocks for 100 ticks. The check
  fired at ~50 ticks, before the demo could even start.
- Fix applied: NOTIFY_OPS_FOR_PASS 10→500 (manifest), check period 10→50 ticks,
  still-running evaluated every 4th MARK (200 ticks), 5-strike threshold.
- Progress: demo now runs (was stuck at 2 ops, now reaches 213 ops). The upstream
  TaskNotify/TaskNotifyArray demos make bursty progress (2→47→62→208→213) then
  stall in a later test phase. The 213 ops include ISR notifications from the
  tick hook (every 50 ticks); the task-context demo appears blocked.
- Isolated tests prove the kernel is correct: minimal xTaskNotify/xTaskNotifyWait
  loops PASS; the exact prvSingleTaskTests initial sequence (wait/query/notify)
  PASSes in isolation. The stall is specific to the upstream demo's later phases,
  likely a port/timing interaction in the timer-notification or interrupt-test
  phase.
- Verdict: BLOCKED. The byte-identical upstream demo stalls at ~213/500
  notifications. Further debugging requires tracing the upstream demo's later
  phases, which is beyond the app-wiring scope.

### B7 (blocking timeouts): BLOCKED after genuine effort
- Applied the same check-task fix as B4/B6 (50-tick period, 200-tick
  still-running checks, 1000-tick stall threshold).
- Result: 0 timeout events (ops=0). The upstream blocktim demo's tasks are not
  executing queue operations. xAreBlockTimeTestTasksStillRunning() returns
  pdTRUE (cycles increment) but g_trace_qsend/g_trace_qrecv remain 0.
- Verdict: BLOCKED. The upstream demo does not progress to queue operations on
  this port. Root cause undetermined; possibly task creation or queue setup
  interaction.

### B7 update 2026-10-09: counter bug fixed, gate still infeasible (measured)
- ROOT CAUSE of the 0-events reading (previous entry's "root cause
  undetermined" was wrong): fw/app/rtos_blocktim.c prvTimeoutEvents() returned
  g_trace_qsend + g_trace_qrecv (SUCCESS counters). On a blocking send/receive
  whose block time expires, third_party/freertos_kernel/queue.c fires exactly
  one traceQUEUE_SEND_FAILED / traceQUEUE_RECEIVE_FAILED (queue.c ~1093,
  ~1581) and never the success macros. The demo was making progress all along;
  the app counted the wrong counters. The previous "demo not executing queue
  ops" conclusion was also premature: the demo's Test 0 (prvBasicDelayTests)
  burns ~900 ticks before the first queue op, so nothing (not even successful
  sends) happens inside the 1200-tick budget's early window.
- FIX (app only, fw/app/rtos_blocktim.c): prvTimeoutEvents() now returns
  g_trace_qsend_fail + g_trace_qrecv_fail (externs already declared in
  fw/freertos/FreeRTOSConfig.h:126-127). third_party/ untouched (byte-identical).
- SECOND APP BUG found during measurement: the stall check (evaluate
  xAreBlockTimeTestTasksStillRunning() every 4th MARK, 5-strike threshold)
  false-fired "TEST blocktim FAIL: demo check" at tick ~1000 on a healthy
  demo. The demo's cycle counters only advance at loop boundaries (Test 0 ~900
  ticks, then Tests 1-4 ~1000 ticks with no counter change; xSecondaryCycles
  stays 0 until the first full loop ends ~1900 ticks), and the function
  requires BOTH counters to advance since its previous call. Fixed threshold
  to 12 consecutive failures (2400 ticks > worst genuine ~1900-tick gap);
  documented the math in the app comment. Verified: no false trip over 7950
  ticks.
- MEASURED EVENT RATE (Verilator RTL, 50 MHz, 1 kHz tick, 400M-cycle run =
  7950 ticks): 48 timeout events, 0 errors (no FAIL/ASSERT lines;
  xErrorOccurred never set), no false stall trip. Steady-state loop: ~12
  events per ~1987 ticks (Test 1: 5 recv timeouts over 310 ticks; Test 2: 5
  send timeouts over 310 ticks; Tests 3/4: 1 send + 1 recv timeout, 175 ticks
  each; Test 0 contributes ~900 ticks and 0 events).
- INFEASIBILITY: 200 events need 200/48*7950 = 33,125 ticks = ~1.66B cycles
  at 50,000 cycles/tick = 27.6x the manifest's 60M-cycle (1200-tick) budget.
  Structural lower bound (12 events per >=1900-tick loop): >=31,667 ticks =
  >=1.58B cycles = >=26x over budget. Host time would be ~25 min > 20-min host
  budget too. Final 60M-cycle manifest-budget run: timeout at 60M cycles,
  23 MARKs, 2 timeout events, no false FAIL (honest timeout, not a verdict bug).
- Verdict: B7 stays BLOCKED. Reaching 200 events needs the unmodified upstream
  demo's timeline (owner options: relax the count, extend the budget, or accept
  the structural rate). Evidence: results/raw/b7_blocktim_400M_uart.log
  (48 events / 7950 ticks), results/raw/b7_blocktim_60M_vlt.log,
  tb/logs/run_rtos_vlt_rtos_blocktim.log.

### G2 (fault: context corrupt): injection timing
- Root cause of original BLOCKED: firmware printed "MARK ctxsave <addr>" BEFORE
  the ecall, but uart_putc() blocks ~4340 cycles/byte. The 20-byte MARK line
  takes ~87k cycles to transmit. The tb injected when it saw '\n' (at 87k),
  but the ecall/save happened at ~87.1k (after the print). The injection
  landed BEFORE the save and was overwritten.
- Fix: tb/tb_fault_ctx.sv now uses fixed-delay injection (cycle+2000 after MARK)
  instead of immediate injection. The save happens at ~MARK+100, restore at
  ~MARK+3000; injecting at MARK+2000 lands in the window.
- Firmware address derivation verified: port saves x5 at sp_at_ecall-112
  (SAVE does sp-124, x5 at +12). Firmware computes sp-112 in naked asm before
  the ecall. TCB pxTopOfStack confirms the stack location.
- Status: testing in progress.

### G2 update: address derivation does not match hardware
- Tried four injection timing strategies: immediate (too early, overwritten),
  polling for non-X (never observed), trap-watcher (missed trap), fixed-delay
  (too early, old=X), hybrid delay+poll (save never observed at 0x103d0).
- The firmware-derived address (sp-112 = 0x103d0) does not match where the
  port actually saves x5. The port's SAVE macro analysis may miss an offset
  (e.g., ISR stack switch, or the ecall uses a different sp than the task's).
- Verdict: BLOCKED. The injection address derivation is incorrect; the actual
  saved-context SRAM location needs to be determined via a different method
  (e.g., watching the CPU's store operations in Verilator, or instrumenting
  the port's SAVE macro).

## 2026-10-09: G2 PASS — deterministic x5-slot derivation from port SAVE macro
**Previous failures:** Four firmware-derived address attempts failed. The firmware
computed `sp-112` in a naked asm helper, but (a) the MARK-print timing model was
wrong (uart_putc is non-blocking; the tb saw '\n' ~4340 cycles AFTER the
save+restore completed, so injections landed after the restore), and (b) a later
attempt watched the pxCurrentTCB *pointer variable* (0x1d0e0) instead of the TCB
struct it points to — the SAVE macro does `store_x sp, 0(t0)` where t0 is the
TCB pointer VALUE, i.e. it writes to `*(pxCurrentTCB)`, not to `pxCurrentTCB`.
**Fix (tb/rtl_vlt/tb_g2_final.cpp, Verilator):** Read the actual upstream
portContext.h SAVE macro (not the firmware's guess):
  - SAVE runs on the TASK stack (ISR-stack switch happens after the save).
  - `addi sp,sp,-124; store_x x5,3*4(sp)` → x5 at sp_at_trap - 112.
The harness reads the CPU's live sp (rf[2]) while the target ecall executes
(pc=0x1d5c, the ecall in vRegTestAsm — an earlier run targeted a vTaskDelay
ecall at 0x3910 whose x5 was not the pattern), computes x5_addr = sp-112,
then watches the CPU data-store interface (d_wstrb/d_addr/d_wdata).
**Empirical verification:** observed the store to 0x10820 with data 0x22222222
(known regtest pattern) 3 cycles after the trap; pre-inject SRAM readback
confirmed 0x22222222 (this caught TWO bugs: (1) mcause for M-mode ecall is 11,
not 8; (2) the bus maps sram_d_waddr = d_addr[16:2] WITHOUT subtracting the
0x10000 base, so the first index computation read/wrote the wrong word and the
real store overwrote the fault).
**Injection:** at cycle 239384, addr 0x10820, old 0x22222222 → new 0xdddddddd,
readback confirmed ACTIVE. The restore loaded the corrupted x5; the regtest
verify (`bne x6,t0`) failed → "TEST regtest FAIL: task 1 x6 expected dddddddd"
at cycle 443667. G2: ALL PASS. Evidence: results/raw/g2_fault_ctx.log.
Runner: tb/run_g2_final.sh (builds harness if missing, enforces clean B1
firmware, checks ALL PASS + injection log + FAIL marker).

## 2026-10-09: B4 (task notifications) — ROOT-CAUSED and PASS (was BLOCKED)

**Prior state:** BLOCKED at 213/500 notifications. The earlier note attributed the
stall to "the task-context demo (prvNotifiedTask) stalling in a later phase."
That attribution was wrong.

**Defect 1 (trace macros, fixed):** `fw/freertos/FreeRTOSConfig.h` defined
`traceTASK_NOTIFY` but neither `traceTASK_NOTIFY_FROM_ISR` (tasks.c:8226) nor
`traceTASK_NOTIFY_GIVE_FROM_ISR` (tasks.c:8360). The demo's `xNotifyTaskFromISR()`
rotates through `vTaskNotifyGiveFromISR` / `xTaskNotifyFromISR` /
`xTaskNotifyAndQueryFromISR`. The give path had no counting macro at all and was
invisible to the op counter. (Correction to the handoff: the other two ISR APIs
were already counted via the pre-existing `traceRETURN_xTaskGenericNotifyFromISR`
(tasks.c:8305); the "ISR notifications invisible" claim was only true for
`vTaskNotifyGiveFromISR`, 1/3 of the rotating ISR gives.) Fix: added both macros
(`g_trace_notify_isr++`) and removed the redundant `traceRETURN_xTaskGenericNotifyFromISR`
so each ISR notify counts exactly once (it fires on the same
`xTaskGenericNotifyFromISR` path; keeping both would double-count).

**Defect 2 (isolated, fixed in app wiring):** Built a debug copy of the upstream
demos (`fw/app/dbg_TaskNotify.c`, `fw/app/dbg_TaskNotifyArray.c`, throwaway, since
deleted) with UART MARKs at phase boundaries, plus a temporary per-demo check
report in the check task (reverted). Findings:
- TaskNotify demo: HEALTHY. `prvSingleTaskTests` completes (including the
  suspend/resume timer test), main loop iterates, `ulNotifyCycleCount` increments.
- TaskNotifyArray demo: HEALTHY but its still-running check reported FAIL from
  the very first evaluation (`MARK dbg check n=1 a=0`). Root cause: the array
  demo's `prvSingleTaskTests()` blocks 3x100 ticks before its first
  `ulFineCycleCount++` (line 726), while our check task evaluated
  `xAreTaskNotificationArrayTasksStillRunning()` at tick 200. That demo's
  `xErrorStatus` is a static latch: one premature no-progress observation fails
  it permanently, even though the demo then proceeds correctly (observed
  `arr-single-done`, `arr-susp-done` in the debug UART).
- So the "stall" was never a demo stall: it was the app check task failing a
  healthy demo on startup, then halting (`TEST notify FAIL: demo check`).
- Fix (app wiring only, `fw/app/rtos_notify.c`): the check task skips
  still-running evaluations for the first 1000 ticks (`NOTIFY_STALL_GRACE_TICKS`),
  comfortably past both demos' initial phases. Genuine stalls are still caught
  (5-strike/1000-tick detector arms after the grace period).

**Also:** `tb/rtl_vlt/tb_rtos_vlt.cpp` gains `+uartlog=<file>` (raw UART line dump;
used for the debug isolation). The pre-existing `mark_value` DIAG print was left
as-is.

**Result:** B4 PASS. `TEST notify PASS ops=514` (firmware), 40 MARK notify lines,
0 errors, ~100M cycles, Verilator 5.032 RTL backend, `+irqperiod=50000` (tb-driven
external interrupt exercising the MEI ISR notify path). Upstream
`TaskNotify.c`/`TaskNotifyArray.c` remain byte-identical (md5 verified).
Evidence: `results/b4_gate.json`, `tb/logs/run_rtos_vlt_rtos_notify.log`.
Debug UART logs preserved: `tb/logs/b4_dbg_uart.log`, `b4_dbg2_uart.log`,
`b4_dbg3_uart.log`. Commit 472a62e.

---

## 2026-10-09 ~09:30 PDT — final watchdog verification pass (finisher)

**Scope:** verify every tracked PASS against its evidence file before the
final acceptance report; only re-run gates whose evidence is missing or
fails its PASS marker. Re-ran (all PASS, no changes needed):
`tools/check_arch.py` (ARCH 45/45, exit 0, all DUT/Spike sig pairs
byte-identical), `tools/check_app.py --uart results/raw/demo_uart.log
--flash fw/build/flash.hex` (CHECK_APP: ALL PASS 24/24, exit 0, digests via
hashlib), `tools/check_frozen.py` (PASS, frozen revision consistent).

**G3 evidence cell:** `results/ACCEPTANCE_STATUS.md` listed G3 PASS with an
empty evidence cell. Evidence confirmed as
`results/raw/fault_uart_tampered.log` (duplicated PKT 3 injected) and
`results/raw/fault_uart_check.log` (`CHECK_APP: FAIL (25/24 packets)`,
checker REJECTED the tampered stream). Tracker cell filled in accordingly;
verdict unchanged (fault active, checker rejects, not passed).

**Untracked file cleanup:** `fw/app/notify_2task.c` was a 35-line throwaway
2-task debug scratch from B4 debugging, unreferenced by any build script,
doc, or runner. B4's PASS evidence is the full notify test (ops=514,
40 MARKs), so the scratch was deleted, not committed. `git status --short`
clean afterward.

**B7:** stays BLOCKED, no weakening. Re-confirmed numbers from
`results/raw/b7_blocktim_400M_uart.log` and
`tb/logs/run_rtos_vlt_rtos_blocktim.log`: 48 events / 7950 ticks =
0.006/tick, so 200 events need ~1.66B cycles, 27.6x over the 60M contract
budget; upstream `blocktim.c` byte-identical; 0 errors. Owner options
documented in `results/ACCEPTANCE_REPORT.md`.

**Deliverable:** wrote `results/ACCEPTANCE_REPORT.md` (repo URL, branch,
commit SHA, `make acceptance`, per-layer counts, 31-row verdict table,
reuse-vs-new accounting, B7 options, push-blocked note). Commit locally;
never pushed (no write credentials).

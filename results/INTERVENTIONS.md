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

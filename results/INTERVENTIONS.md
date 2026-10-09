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

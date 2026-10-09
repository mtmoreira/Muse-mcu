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

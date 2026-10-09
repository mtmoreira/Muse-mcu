# Muse MCU — architecture and interface specification
**Status: APPROVED by owner 2026-10-08. Contract v1.0.0. Implementation authorized.**

## 1. What is being built (fresh)

A small single-core RISC-V microcontroller plus a FreeRTOS software stack, all RTL
newly authored for this project. Nothing is copied from the earlier
rv32i-open-source-flow experiment; design knowledge from it is reused, code is not.
Reused third-party components are listed in section 7 with exact revisions and
license notes. Nothing here is a pre-existing board demo.

## 2. ISA and execution model (declared, frozen for the contract)

- RV32I v2.1 base + Zicsr. Machine mode only. No S/U modes, no PMP, no debug.
- No M/A/F/D/C extensions. `misa` reads `0x40000100` (RV32I, M-mode only).
- Single-cycle, single-issue, in-order core. CPI = 1 for all instructions.
- Trap model: direct `mtvec` only (no vectored mode). Synchronous traps:
  illegal instruction, `ecall`, `ebreak`, misaligned load/store/fetch address.
  Interrupts: machine software (MSIP), machine timer (MTI), machine external (MEI).
  Interrupts are disabled on trap entry (`mstatus.MIE` cleared); no nesting.
- `wfi` is not implemented and raises illegal-instruction. Misaligned accesses
  trap; there is no hardware fixup.
- Reset: synchronous, active-high, minimum 1 cycle. Reset vector `0x00000000`.
  All architectural state has defined reset values; acceptance never relies on
  simulator X-resolving-to-0 (testbench X-handling limits are disclosed in 9).

## 3. Memory map (32-bit, byte-addressed)

| Region  | Base         | Size    | Attr | Notes |
|---------|--------------|---------|------|-------|
| BOOTROM | 0x00000000   | 64 KiB  | R-X  | Firmware executes here; testbench backdoor-loads the hex image |
| SRAM    | 0x00010000   | 128 KiB | RWX  | Data, stacks, FreeRTOS heap |
| CLINT   | 0x10000000   | 64 KiB  | RW   | msip @0x0, mtimecmp @0x4000, mtime @0xBFF8 |
| GPIO    | 0x10010000   | 4 KiB   | RW   | data_in @0x0, data_out @0x4, dir @0x8 |
| UART0   | 0x10020000   | 4 KiB   | RW   | txdata @0x0, rxdata @0x4, status @0x8, bauddiv @0xC |
| SPI0    | 0x10030000   | 4 KiB   | RW   | ctrl @0x0, status @0x4, txdata @0x8, rxdata @0xC, cs @0x10, clkdiv @0x14 |

Unmapped addresses trap (load/store/ fetch access fault). Writes to BOOTROM are
silently dropped by the bus (documented, tested in A6).

Clock: single 50 MHz domain. UART default 115200 baud (bauddiv = 434).
SPI master: mode 0 (CPOL=0, CPHA=0), MSB-first, software-controlled CS.

Interrupt aggregation into MEI: `uart_rx_ready | spi_done | gpio_edge | tb_test_irq`.
MTI from CLINT `mtime >= mtimecmp`. MSI from CLINT `msip`.

## 4. Software stack

- `fw/startup/crt0.S` (new): reset entry, stack setup, `.data`/`.bss` init, `main`.
- Linker: ROM origin 0x0, RAM origin 0x10000 (new).
- Drivers (new, polling + interrupt variants): `uart.c`, `spi.c`, `gpio.c`, `timer.c` (CLINT), `irq.c`.
- FreeRTOS-Kernel V11.3.1, reused byte-identical (trimmed file set, section 7),
  preemptive, 1 kHz tick from MTI, `heap_4.c`, upstream `portable/GCC/RISC-V`
  port used as-is. New: `FreeRTOSConfig.h`, trap entry wiring, tick setup.
- SHA-256: RFC 6234 `sha256.c`, algorithm verbatim; only the stdio-based test
  driver is replaced by an embedded self-test (adaptation boundary documented).
- Application images (new): per-test-group firmware + the three-task demo app.

## 5. Three-task demonstration workload

- Acquisition task (prio 2): reads framed messages from external SPI flash
  through SPI0, posts each to a FreeRTOS queue (depth 4).
- SHA task (prio 3): blocks on the queue, computes SHA-256 in firmware,
  transmits `(magic, msg_id, msg_len, digest_hex)` packets over UART0 TX.
- Background task (prio 1): continuous xorshift compute loop, live register
  state, never blocks or yields during the observation window.
- FreeRTOS idle + timer tasks at prio 0 (accounted separately, not app tasks).
- Flash holds input messages + framing metadata + seed. Never executable code,
  never expected digests. Expected digests live only in the host checker.
- User-supplied seed without recompilation: the flash image generator takes
  `--seed`; the seed is stored in the flash header and read at runtime.
- Firmware binary is frozen before host-side messages are generated.

## 6. Test strategy summary (details in manifest.yaml)

- A: 45 riscv-arch-test cases (39 RV32I + 6 Zicsr) with Spike-generated golden
  signatures, byte-exact match; plus custom reset/trap/interrupt/memmap/UART-RX/
  SPI/timer-GPIO directed tests.
- B: adapted FreeRTOS minimal demos (queues, semaphores/mutexes, notifications,
  software timers, blocking timeouts, ISR-to-task, register preservation);
  separate firmware images allowed; every group must show progress markers.
- C: preemption latency measured in core cycles from ISR entry to the first
  retired instruction of the unblocked higher-priority task. Bound: 2000 cycles.
- D: end-to-end app through real pins; host checker verifies count, sequence,
  payload digests against Python hashlib.
- E: one frozen RTL revision for all gates; any RTL fix bumps the revision and
  reruns affected tests plus the full app.
- F: Yosys 0.33 + Nangate45 synthesis; app subset + RTOS preemption test on the
  zero-delay gate-level netlist (labeled as such; SRAM/ROM behavioral models
  declared, CPU and peripherals never blackboxed).
- G: three fault-injection negatives; each must provably activate and be
  rejected by the unchanged checkers.

## 7. Reuse / new / credit table

| Component | Origin | Rev | License | Treatment |
|-----------|--------|-----|---------|-----------|
| CPU RTL, SoC RTL, bus, CLINT/GPIO/UART/SPI | new | — | — | newly authored |
| crt0, linker, drivers, FreeRTOSConfig, apps, testbenches, checkers, scripts | new | — | — | newly authored |
| FreeRTOS-Kernel core + `portable/GCC/RISC-V` | FreeRTOS/FreeRTOS-Kernel | tag V11.3.1 | MIT | byte-identical, trimmed set |
| riscv-arch-test RV32I/Zicsr cases | riscv/riscv-arch-test | pinned sha (TBD at impl) | BSD | unmodified .S; thin macro shim (new, documented) |
| Spike (golden signatures) | riscv/riscv-isa-sim | pinned sha (TBD) | BSD | reference model only |
| spiflash.v model | YosysHQ/picorv32 picosoc | pinned sha (TBD) | ISC | unmodified; qualified per checklist |
| sha256.c | RFC 6234 | — | RFC boilerplate (verify) | algorithm verbatim; driver replaced |
| SHA-256 vectors | NIST CAVP shabytetestvectors.zip | pinned sha256 (TBD) | public domain | golden data, host + embedded subset |
| UART sink/source models | new (tb/) | — | — | protocol cross-checked vs cocotbext-uart examples |

## 8. Toolchain and environment (pinned in manifest)

- riscv-none-elf-gcc 15.2.0 (xPack, local tarball, sha pinned)
- Icarus Verilog 12.0 (primary sim), Yosys 0.33 (present), Nangate45 typical lib (local, sha pinned)
- Python 3.10+ for checkers/generators
- `env/bootstrap.sh` installs everything on a clean Ubuntu 24.04 host.
- `make acceptance` runs all mandatory gates, nonzero on failure/incompleteness.
  `make smoke` is a labeled fast subset.

## 9. Known limitations disclosed up front

- Icarus X-handling: 4-state but optimistic on some UDP paths; mitigated by
  defined reset values everywhere and reset-variation tests (A3).
- Single-cycle core: no performance claims beyond CPI=1; characterization is
  functional, not PPA signoff.
- Gate-level sim is zero-delay; timing closure is out of scope per the brief.
- riscv-arch-test modern flow needs a shim for the macro layer; the shim is new
  code, reviewable, and the test bodies stay unmodified.

## 11. Demonstration (DEMO1)

`demo/run_demo.sh` runs the frozen D1 application image and narrates it live on
the console: each SPI message read (id, length), each queue handoff, each
computed SHA-256 digest, each UART packet with host-side verification, and each
observed preemption of the background task. The transcript is saved to
`results/demo_transcript.txt` and the run's VCD is the source for FIG2. The demo
is informational; it does not replace D1, and a demo failure counts as an app
failure.

## 12. Rationale for key bounds (fixed before any trace is captured)

- Preemption bound 2000 cycles @50 MHz: single-cycle core; ISR entry ~12,
  full 32-reg save ~50, port yield path (scheduler + queue op) worst-case few
  hundred, restore ~50, mret ~4. 2000 is ~10x the expected ~250.
- App sim budget 100M cycles / host 90 min: ~24 messages x ~100 UART bytes x
  4340 cycles/byte dominates (~10M cycles) + tick ISR overhead; 10x margin.
- Arch-test per-test 2M cycles: longest RV32I case is a few thousand
  instructions; 2M is orders of magnitude above.
- Exercise counts (45 arch cases, 2000 queue ops, 50 preemption events, 24 app
  messages) are chosen so a stuck-at-pass cheat (zero events) cannot satisfy
  the manifest's minimum-event counters.

# Arch-test DUT-shim convention (A1/A2)

Defined by the Phase-3a testbench worker (2026-10-08) for coordination with
the firmware worker building `fw/build/arch/*.hex`. If the firmware worker
has a conflicting convention, the two must be reconciled before the 45-test
run; until then this document is authoritative for `tb/tb_arch.sv`.

## Test-end protocol

Each arch-test ELF, run from reset on `mcu_top`:

1. Executes the riscv-arch-test case body (unmodified `.S` + thin macro shim).
2. Writes the signature words to SRAM at **SIGBASE `0x00018000`**:
   - word 0: signature word count N (1 <= N <= 4096)
   - words 1..N: the signature words, in riscv-arch-test order
3. Writes **PASS_MAGIC `0xDEADBEEF`** (or **FAIL_MAGIC `0xDEADDEAD`**) to
   **DONE_ADDR `0x0001FFF0`**.
4. Executes `ecall` to end the test (the tb also polls DONE_ADDR).

## Testbench behavior (`tb/tb_arch.sv`)

- Loads the per-test hex into `dut.rom.mem` via `$readmemh`.
- Waits for DONE_MAGIC or the `ecall` trap (`mcause == 11`), 2M-cycle watchdog.
- On PASS_MAGIC: dumps N signature words (one `%08h` per line) to the file
  given by `+sigfile=` (the runner uses
  `results/raw/arch/<name>.dut.sig`), prints `TB_ARCH <name>: PASS`.
- On FAIL_MAGIC, missing PASS_MAGIC at `ecall`, bad count, or timeout:
  prints `TB_ARCH <name>: FAIL: ...` and `$fatal`s (nonzero exit).
- SRAM word index for byte address A is `A[16:2]` (the bus does not subtract
  the region base): DONE word `dut.ram.mem[0x7FFC]`, signature
  `dut.ram.mem[0x6000 + i]`.

## Runner (`tb/run_arch.sh`)

Loops over all `*.hex` in `fw/build/arch/` (override: `run_arch.sh <hexdir>`),
runs `tb_arch` per test, then invokes `tools/check_arch.py` (firmware worker)
for the Spike-golden byte-exact comparison and requires `ARCH 45/45 PASS`.

## Firmware worker notes (Phase 4a, reconciliation 2026-10-08)

The shim/test-end convention above is implemented as specified; the only
reconciliation needed was the `.sig` file format, which now matches this
document on both sides:

- `.spike.sig` (written by `tools/build_arch.py`): N signature words, one
  `%08x` lowercase hex per line, no count header — same as `.dut.sig`.
- `tools/check_arch.py` compares the two word lists byte-exact.

Shim files (all new, test `.S` bodies unmodified):

- `tb/arch/riscv_arch_test.h` — DUT shim. `RVTEST_CODE_END` stores the
  word count to `SIGBASE[0]`, writes `PASS_MAGIC` to `DONE_ADDR`, then
  `ecall` (a0=0); the trap handler records `mcause` to GPIO `dbg_scratch`
  (`0x1001000C`) and spins.
- `tb/arch/riscv_arch_test_spike.h` — Spike shim. `RVTEST_CODE_END`
  prints each signature word as 8 hex chars over the HTIF console, then
  HTIF shutdown (`tohost = 1`).
- `tb/arch/rvtest_common.inc` — shared macros. `RVTEST_BEGIN` is
  textually identical in both builds; both are built with `-mno-relax`
  so test code lands at identical addresses in both ELFs (jal/jalr/auipc
  capture PCs — this is what makes byte-exact comparison valid).
- `tb/arch/arch.ld` — ROM 0x0 / RAM 0x10000, `_start` at 0x0, signature
  at `0x00018000`, writable `.arch_data` (scratch + test data) at
  `0x00010000`, HTIF `.tohost` in RAM.

`tools/build_arch.py [names...]` produces per test: `<name>.dut.elf`,
`<name>.hex` (for `tb/run_arch.sh`), `<name>.spike.elf`, and the golden
`results/raw/arch/<name>.spike.sig`, plus `fw/build/arch/sigbase.json`
(per-test SIGBASE, see below).

### Loading the .hex (testbench workers)

`<name>.hex` is a flat 32-bit word image from byte `0x0`.
`$readmemh(h, dut.rom.mem)` loads the ROM part (words `[0:16384)`).
The words from index 16384 on are the SRAM-resident part
(`.arch_data` at `0x10000`, `.signature`, `.tohost`) and MUST also be
loaded, or the test reads zeroed test-data/scratch:

```
for (i = 0; hex_word[16384 + i] exists; i++)
    dut.ram.mem[0x4000 + i] = hex_word[16384 + i];
```

(SRAM word index is `byte_addr[16:2]`; hex word 16384 = byte `0x10000`.)
Skip the `$readmemh` "too many words" warning; the ROM load is correct
and the loop above loads the rest. `sigbase.json` gives the per-test
signature base (`0x00018000` except `I-jal-00`: `0x00024000`).

### I-jal-00 exception (large .text)

I-jal-00's `.text` is ~112 KiB (it uses `.p2align` up to 14 to exercise
jal with large offsets) and does not fit in the 64 KiB boot ROM. For this
test only:

- Linker script `tb/arch/arch_jal.ld`: `.text` spans ROM+SRAM
  contiguously from `0x0` (`[0x0, 0x1C000)`); the DUT fetches from both.
  `.arch_data` follows `.text`; `.signature` moves to `0x00024000`
  (the default `0x00018000` is inside `.text`); `-DSIGBASE_ADDR`
  carries the move into the shim.
- `fw/build/arch/I-jal-00.hex` is a flat image from `0x0` (28672 words).
  The testbench must load words `[16384:]` into SRAM:
  `dut.ram.mem[0x4000 + i] = hex_word[16384 + i]`
  (SRAM word index is `byte_addr[16:2]`, no base subtraction).
- `sigbase.json` records `"I-jal-00": "0x00024000"` (all others
  `"0x00018000"`); the signature is read from that base instead.

The DUT and Spike ELFs still share identical test-code addresses, so the
byte-exact comparison remains valid.

Spike: stock Spike cannot map target memory at `0x0` (its debug module
sits at `[0x0,0x1000)`, boot ROM at `0x1000`). Use the `spike-mcu` build:
riscv-isa-sim @ `e448970b1668f7893f88e54824e1387a3e5fe09b` with the
two-line platform patch (`DEBUG_START` 0x0 -> 0x40000000,
`DEFAULT_RSTVEC` 0x1000 -> 0x40001000) installed at
`~/workspace/toolchains/spike-mcu/bin/spike` (`SPIKE_BIN` overrides).
The patch moves only platform placement constants; ISA semantics are
untouched. Run as `spike --isa=rv32i_zicsr -m0x0:0x40000 <elf>`.

HTIF transport was verified empirically before batching (minimal
`putc("HI\n")` + shutdown ELF printed `HI` and exited 0 under the
patched Spike).

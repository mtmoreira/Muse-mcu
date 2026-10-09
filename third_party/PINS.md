# Third-party pins — Muse MCU Phase 1 upstream fetch (2026-10-08)

Fetch worker: Phase 1 upstream-fetch. Upstream checkouts live in
`~/workspace/.upstream-dl/<name>/` (shallow clones, kept out of the repo).
Only the trimmed file sets below were copied into `third_party/`.
Every copy was verified byte-identical against the pinned checkout
(`cmp` per file / `diff -r -q` per directory) unless "treatment" says otherwise.

`artifact_sha256` = sha256 over `find <dir> -type f | sort | xargs sha256sum`
of the vendored directory (deterministic snapshot of the vendored set).

| Component | Upstream repo URL | Revision (tag or sha) | sha256 of vendored artifact | License | Treatment |
|---|---|---|---|---|---|
| FreeRTOS-Kernel core + RISC-V port | https://github.com/FreeRTOS/FreeRTOS-Kernel | tag V11.3.1 = `3a22924e0a9ddbbc8b0758881c33b3422a5cc20d` (2026-08-21) | `b210881eb881168576d702c26818c96587ac073d93ff96d5eacfcfa085ce1e4f` | MIT (LICENSE.md vendored) | byte-identical, trimmed set |
| FreeRTOS minimal demos | https://github.com/FreeRTOS/FreeRTOS | main @ `f4fcc3b228643144727e9257ba12db1cb632b6e6` (2026-08-26) | `ac4d25a65a24ca37496e01ae9bdb415d61fac61ec78ab6f1c21541af685b380d` | MIT | unmodified .c files (13) |
| FreeRTOS ThirdParty template | https://github.com/FreeRTOS/FreeRTOS | main @ `f4fcc3b228643144727e9257ba12db1cb632b6e6` (2026-08-26) | `351d285c8c1f229efa3f45f9c03750aa960e6b79b4cb76d1a1d7b009022857ab` | MIT | unmodified reference copy (7 files) |
| riscv-arch-test RV32I cases | https://github.com/riscv/riscv-arch-test | main @ `c242670a5d3c600b57e601b2f1ad27c804dc426e` (2026-10-08) | `b66a6213e2f0d234f64b89fc8d9fbb1ebc3e79e1ae3dbfb11e4923330e57d0` | BSD-3-Clause (COPYING.BSD upstream) | unmodified .S (39 + 6) |
| Spike (golden signatures) | https://github.com/riscv/riscv-isa-sim | main @ `e448970b1668f7893f88e54824e1387a3e5fe09b` (2026-10-08) | n/a (tool, not vendored; built from the pinned checkout) | BSD (UC Regents, LICENSE upstream) | reference model only; built locally |
| picosoc spiflash.v | https://github.com/YosysHQ/picorv32 | main @ `ef203c2b0a3fb793280f5114941416c425c5b461` (2026-09-07) | `5e30ee6eaadd532e2547ee0a3cb41e5bd4a1ee3c72fd484275ce680dff49ba57` (single file) | ISC (header comment in file) | unmodified; qualified per checklist |
| RFC 6234 SHA-256 | https://www.rfc-editor.org/rfc/rfc6234.txt | RFC text, downloaded 2026-10-08 (`8f39f02a57bfd1da15634706724a585766e6223f77ecdaf243cad16cd3a1aa1b`) | `306f6925ee13720a91fa37b78978dcb449f87cdad990f3bc57e2cc1769b61bad` (sha256.c) / `14f2099920904c1c47057e0ee85f3463e0b9f404c3f2e6f1a5c242c54cd7136d` (sha256.h) / `f9cef450263949c5701ee2839f46607136ab0a3e7803af2b74a5326750c63c25` (sha-private.h) | IETF Trust BSD-style (banner in files) | extracted (see sha256/EXTRACTION.md) |
| NIST SHA byte vectors | https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/shs/shabytetestvectors.zip | zip sha256 `929ef80b7b3418aca026643f6f248815913b60e01741a44bba9e118067f4c9b8` | same as zip (golden data) | public domain (US gov) | unmodified; unzipped in place |

## Notes

- FreeRTOS-Kernel trimmed set (`third_party/freertos_kernel/`): tasks.c,
  queue.c, list.c, timers.c, event_groups.c, stream_buffer.c,
  portable/MemMang/heap_4.c, portable/GCC/RISC-V/{port.c, portASM.S,
  portmacro.h, portContext.h}, LICENSE.md. All 12 verified byte-identical.
- FreeRTOS demos (`third_party/freertos_demos/`): BlockQ.c, GenQTest.c,
  QPeek.c, PollQ.c, semtest.c, countsem.c, recmutex.c, TaskNotify.c,
  TaskNotifyArray.c, TimerDemo.c, IntQueue.c, IntSemTest.c, blocktim.c.
  Extra headers they include: FreeRTOS kernel headers (FreeRTOS.h, task.h,
  queue.h, semphr.h, timers.h, from the vendored kernel set); their paired
  `*.h` files live upstream at `FreeRTOS/Demo/Common/include/` (all present
  there except `IntQueueTimer.h`, which is instead provided by the vendored
  `third_party/freertos_template/` reference copy); plus libc
  `<limits.h> <stdlib.h> <string.h>`.
- riscv-arch-test (`third_party/riscv_arch_test/I/` 39 files,
  `.../Zicsr/` 6 files: csrrc, csrrci, csrrs, csrrsi, csrrw, csrrwi).
  Every .S file `#include`s exactly one header: `"riscv_arch_test.h"`
  (to be provided by the later macro-shim step; NOT vendored here).
- spiflash.v: qualified in `third_party/picosoc_spiflash/QUALIFICATION.md`.
  Important: the model powers up with `powered_up = 0`; the 0x03 read path
  is gated on it, so firmware must issue 0xAB (wake) before 0x03 reads.
  The acceptance manifest's "power-on ready" assumption must be corrected.
- Spike build: prefix `~/workspace/toolchains/spike`. Note: Ubuntu 24.04
  (noble) does not package `device-tree-compiler` (absent from noble/main,
  universe, updates, backports, security); Spike's configure hard-requires
  it, so dtc 1.8.1 was built from source (git.kernel.org, `f3451d12532b…`)
  into `~/workspace/toolchains/dtc/bin/dtc` (flex/bison/m4 .debs fetched
  from archive.ubuntu.com since the local apt mirror is incomplete).
  dtc is used by Spike only at runtime for `--device-tree` conversion.
- Toolchain note for env/bootstrap.sh: on noble, plan a from-source dtc
  build (or a dtc binary vendoring step); `apt-get install
  device-tree-compiler` will not work.

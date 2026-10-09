// riscv_arch_test_spike.h — Spike shim for the vendored riscv-arch-test cases.
//
// Same macro interface as riscv_arch_test.h (via the shared
// rvtest_common.inc), but the end-of-test path targets Spike instead of
// the DUT: RVTEST_CODE_END issues the HTIF shutdown (write 1 to `tohost`)
// and Spike's +signature= dump (keyed off the begin_signature /
// end_signature symbols aliased in rvtest_common.inc) captures the
// signature region at exit. tools/build_arch.py parses that dump into the
// golden .spike.sig files.
//
// NOTE: an earlier revision dumped the signature over the HTIF console and
// polled fromhost for an ack per character. That hung forever: this Spike
// build prints the character but never sets fromhost for console writes
// (verified empirically 2026-10-09). The +signature= path is race-free.
//
// HTIF transport (RV32): `tohost`/`fromhost` are 64-bit symbols in the
// .tohost section. Shutdown is tohost = 1 (device 0, command 0, payload 1);
// Spike exits 0. Run with:
//   spike --isa=rv32i_zicsr -m0x0:0x40000 \
//     +signature=<file> +signature-granularity=4 <elf>
// (-m maps 256 KiB at 0x0 covering the ROM/RAM image layout from arch.ld;
// +signature-granularity=4 makes each dump line one 32-bit word.)

#ifndef RISCV_ARCH_TEST_SPIKE_H
#define RISCV_ARCH_TEST_SPIKE_H

#include "rvtest_common.inc"

// HTIF mailbox symbols. Spike intercepts stores to the `tohost` address.
.pushsection .tohost, "aw", @progbits
.align 3
.globl tohost
tohost:   .dword 0
.globl fromhost
fromhost: .dword 0
.popsection

// End of test on Spike: HTIF shutdown; the signature region is captured
// by Spike's +signature= dump at exit. Uses no registers but t0/t1.
#define RVTEST_CODE_END \
    .text; \
    .align 2; \
    la t0, tohost; \
    li t1, 1; \
    sw t1, 0(t0); \
    sw zero, 4(t0); \
28: j 28b; \
    .align 2; \
trap_handler: \
    j trap_handler

// Pass/fail primitives, Spike flavor. (Neither is invoked by the 45 tests;
// RVTEST_CODE_END is the real end-of-test path. Provided per contract.)
#define RVTEST_PASS \
    /* no-op: the RVTEST_CODE_END shutdown is the pass path */

#define RVTEST_FAIL \
    la t0, tohost; \
    li t1, 3; \
    sw t1, 0(t0); \
    sw zero, 4(t0); \
39: j 39b

#endif // RISCV_ARCH_TEST_SPIKE_H

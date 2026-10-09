// riscv_arch_test_spike.h — Spike shim for the vendored riscv-arch-test cases.
//
// Same macro interface as riscv_arch_test.h (via the shared
// rvtest_common.inc), but the end-of-test path targets Spike instead of
// the DUT: RVTEST_CODE_END prints each signature word as 8 lowercase hex
// chars over the HTIF console (device 1), then issues the HTIF shutdown
// (write 1 to `tohost`). The build_arch.py harness captures stdout and
// parses the hex words into the golden .spike.sig files.
//
// HTIF transport (RV32): `tohost`/`fromhost` are 64-bit symbols in the
// .tohost section. A console char c is sent as two 32-bit stores:
//   tohost[31:0]  = c            (payload)
//   tohost[63:32] = 0x01010000   (device=1, command=1)
// then the shim polls fromhost for nonzero and clears it. Shutdown is
// tohost = 1 (device 0, command 1, exit code 0); Spike exits 0.
// Run with: spike --isa=rv32i_zicsr -m0x0:0x40000 <elf>
// (-m maps 256 KiB at 0x0 covering the ROM/RAM image layout from arch.ld.)

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

// End of test on Spike: dump the signature over the HTIF console, shut down.
// Uses only s-registers (no calls, no stack) so no setup is needed.
#define RVTEST_CODE_END \
    .text; \
    .align 2; \
    li s0, SIGBASE_ADDR; \
    lw s1, 0(s0); \
    addi s0, s0, 4; \
    beqz s1, 29f; \
30: lw s2, 0(s0); \
    li s3, 28; \
31: srl t0, s2, s3; \
    andi t0, t0, 0xF; \
    addi t0, t0, 48; \
    li t1, 58; \
    blt t0, t1, 32f; \
    addi t0, t0, 39; \
32: la t2, tohost; \
    sw t0, 0(t2); \
    lui t0, 0x1010; \
    sw t0, 4(t2); \
    la t2, fromhost; \
33: lw t0, 0(t2); \
    beqz t0, 33b; \
    sw zero, 0(t2); \
    sw zero, 4(t2); \
    addi s3, s3, -4; \
    bgez s3, 31b; \
    li t0, 10; \
    la t2, tohost; \
    sw t0, 0(t2); \
    lui t0, 0x1010; \
    sw t0, 4(t2); \
    la t2, fromhost; \
34: lw t0, 0(t2); \
    beqz t0, 34b; \
    sw zero, 0(t2); \
    sw zero, 4(t2); \
    addi s0, s0, 4; \
    addi s1, s1, -1; \
    bnez s1, 30b; \
29: la t0, tohost; \
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
    /* no-op: the RVTEST_CODE_END dump + shutdown is the pass path */

#define RVTEST_FAIL \
    la s0, 38f; \
35: lbu t0, 0(s0); \
    beqz t0, 36f; \
    la t2, tohost; \
    sw t0, 0(t2); \
    lui t0, 0x1010; \
    sw t0, 4(t2); \
    la t2, fromhost; \
37: lw t0, 0(t2); \
    beqz t0, 37b; \
    sw zero, 0(t2); \
    sw zero, 4(t2); \
    addi s0, s0, 1; \
    j 35b; \
36: la t0, tohost; \
    li t1, 3; \
    sw t1, 0(t0); \
    sw zero, 4(t0); \
39: j 39b; \
    .section .rodata; \
38: .string "ARCHFAIL\n"; \
    .text

#endif // RISCV_ARCH_TEST_SPIKE_H

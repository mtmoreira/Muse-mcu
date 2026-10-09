// riscv_arch_test.h — DUT shim for the vendored riscv-arch-test cases.
//
// The 45 test files do `#include "riscv_arch_test.h"`; this header provides
// the RVTEST_* macro layer for the Muse MCU DUT. New file, written for this
// project; the test bodies (*.S) are unmodified upstream sources.
//
// End-of-test protocol (observed by tb/tb_arch.sv):
//   - RVTEST_CODE_END stores SIGUPD_COUNT to SIGBASE[0], writes PASS_MAGIC
//     (0xDEADBEEF) to DONE_ADDR (0x0001FFF0), then `ecall` with a0=0.
//   - The trap handler records mcause to GPIO dbg_scratch (0x1001000C) and
//     spins. Any unexpected trap therefore hangs the test -> the
//     testbench's cycle timeout reports FAIL.
//   - RVTEST_FAIL (not used by the 45 tests; provided for completeness)
//     writes FAIL_MAGIC (0xDEADDEAD) then `ecall` with a0=1.
// Shared macros (RVTEST_BEGIN, RVTEST_SIGUPD, ...) live in
// rvtest_common.inc so the DUT and Spike builds stay consistent.

#ifndef RISCV_ARCH_TEST_H
#define RISCV_ARCH_TEST_H

#include "rvtest_common.inc"

// End of test: publish the signature count, signal done, halt via ecall.
#define RVTEST_CODE_END \
    .text; \
    .align 2; \
    li t0, SIGBASE_ADDR; \
    li t1, SIGUPD_COUNT; \
    sw t1, 0(t0); \
    li t0, DONE_ADDR; \
    li t1, PASS_MAGIC; \
    sw t1, 0(t0); \
    li a0, 0; \
    ecall; \
11: j 11b; \
    .align 2; \
trap_handler: \
    csrr t0, mcause; \
    li t1, 0x1001000C; \
    sw t0, 0(t1); \
12: j 12b

// Pass/fail primitives (per the Phase 4a interface contract).
#define RVTEST_PASS \
    li t0, DONE_ADDR; \
    li t1, PASS_MAGIC; \
    sw t1, 0(t0); \
    li a0, 0; \
    ecall

#define RVTEST_FAIL \
    li t0, DONE_ADDR; \
    li t1, FAIL_MAGIC; \
    sw t1, 0(t0); \
    li a0, 1; \
    ecall

#endif // RISCV_ARCH_TEST_H

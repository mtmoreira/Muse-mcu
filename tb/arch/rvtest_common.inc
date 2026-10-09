// rvtest_common.inc — macro layer shared by the DUT and Spike shims.
//
// The 45 vendored riscv-arch-test cases (third_party/riscv_arch_test/I,
// third_party/riscv_arch_test/Zicsr) all do `#include "riscv_arch_test.h"`
// and use only the macros defined here plus the shim-specific
// RVTEST_CODE_END / trap_handler / RVTEST_PASS / RVTEST_FAIL.
//
// NOTE: the parameterized macros MUST be C-preprocessor #defines (not GAS
// .macro), because the test files invoke them with parentheses, e.g.
// RVTEST_SIGUPD(x2, x5, x4, x28, tag, tag_str).
//
// Conventions (must hold for DUT-vs-Spike signature equality):
// - RVTEST_BEGIN is TEXTUALLY IDENTICAL in both shims and both are built
//   with -mno-relax, so the test code that follows it lands at identical
//   addresses in both ELFs. Tests that capture PC values (jal/jalr/auipc)
//   therefore produce identical signature words.
// - Signature region: SRAM at SIGBASE_ADDR. Word 0 is the word count,
//   words 1..N are the signature words (SIG_STRIDE = 4).
// - x2 = signature pointer (init: SIGBASE+4), x3 = test-data pointer
//   (init: test_data_begin). RVTEST_SIGUPD stores the value and advances
//   x2; the link-reg/tmp/tag operands are accepted and unused (scalar
//   tests are self-checking; there is no compare-and-branch here).
// - RVTEST_TESTDATA_LOAD_INT loads one word and advances the data pointer.
// - The Zicsr tests use RVTEST_TEST_CSR (a writable M-mode CSR present on
//   both the DUT and Spike): mscratch.

#ifndef RVTEST_COMMON_INC
#define RVTEST_COMMON_INC

// Signature region base (SRAM). Overridable via -DSIGBASE_ADDR for tests
// whose .text overflows into the default region (I-jal-00 -> 0x00024000;
// see tb/arch/arch_jal.ld and README).
#ifndef SIGBASE_ADDR
#define SIGBASE_ADDR 0x00018000
#endif
#define DONE_ADDR    0x0001FFF0  // testbench polls this for nonzero
#define PASS_MAGIC   0xDEADBEEF
#define FAIL_MAGIC   0xDEADDEAD

#define SIG_STRIDE   4
#define REGWIDTH     4

// Load-immediate / load-address / XLEN store/load aliases used by tests.
#define LI(rd_, imm_)   li rd_, imm_
#define LA(rd_, sym_)   la rd_, sym_
#define SREG            sw
#define LREG            lw

// Zicsr tests do csrrw/csrrs against RVTEST_TEST_CSR. mscratch (0x340)
// is writable on both the DUT CPU and Spike and resets to 0 on both.
#ifdef RVTEST_USES_TEST_CSR
#define RVTEST_TEST_CSR mscratch
#endif

// Entry point. Installs the trap vector, inits the signature and data
// pointers. Byte-identical in both shims (see above).
#define RVTEST_BEGIN \
    .text; \
    .align 2; \
    .globl _start; \
_start: \
    la t0, trap_handler; \
    csrw mtvec, t0; \
    la x2, signature_begin; \
    addi x2, x2, 4; \
    la x3, test_data_begin

// Store one signature word, advance the signature pointer.
#define RVTEST_SIGUPD(sigptr, linkreg, tmpreg, val, tag, tagstr) \
    sw val, 0(sigptr); \
    addi sigptr, sigptr, SIG_STRIDE

// Load one test-data word, advance the data pointer.
#define RVTEST_TESTDATA_LOAD_INT(dataptr, reg_) \
    lw reg_, 0(dataptr); \
    addi dataptr, dataptr, 4

// Writable scratch + test-data words. `scratch` is referenced by the
// lb/lbu/lh/lhu/lw tests with offsets in [-1571, +7]; the 2048-byte pad
// before it and 256-byte guard after it keep those accesses inside this
// writable region and off the test-data words. `test_data_begin` is x3's
// initial value; the .word lines that follow are consumed in order.
#define RVTEST_DATA_BEGIN \
    .section .arch_data, "aw", @progbits; \
    .align 2; \
    .space 2048; \
scratch: \
    .space 256; \
test_data_begin:

#define RVTEST_DATA_END \
    .text

// Signature region, pinned at SIGBASE_ADDR by arch.ld. Word 0 holds the
// word count (also rewritten at RVTEST_CODE_END as a liveness proof).
#define RVTEST_SIG_SETUP \
    .section .signature, "aw", @progbits; \
    .align 2; \
    .globl signature_begin; \
signature_begin: \
    .word SIGUPD_COUNT; \
    .space SIGUPD_COUNT * 4; \
    .globl signature_end; \
signature_end: \
    .text

#endif // RVTEST_COMMON_INC

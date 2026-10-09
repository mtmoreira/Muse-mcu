/* prog_reset.S -- A3 reset/startup check.
 * Verifies the integer register file is all zero, then dumps CSRs to SRAM
 * 0x10000 for the testbench to check. DONE marker at 0x10024.
 *   0xDEADBEEF = pass, 0xDEADDEAD = a register was nonzero.
 */
    .text
    .globl _start
_start:
    /* x1..x31 must read 0 (bne writes nothing, needs no temp reg) */
    bne x1,  x0, fail
    bne x2,  x0, fail
    bne x3,  x0, fail
    bne x4,  x0, fail
    bne x5,  x0, fail
    bne x6,  x0, fail
    bne x7,  x0, fail
    bne x8,  x0, fail
    bne x9,  x0, fail
    bne x10, x0, fail
    bne x11, x0, fail
    bne x12, x0, fail
    bne x13, x0, fail
    bne x14, x0, fail
    bne x15, x0, fail
    bne x16, x0, fail
    bne x17, x0, fail
    bne x18, x0, fail
    bne x19, x0, fail
    bne x20, x0, fail
    bne x21, x0, fail
    bne x22, x0, fail
    bne x23, x0, fail
    bne x24, x0, fail
    bne x25, x0, fail
    bne x26, x0, fail
    bne x27, x0, fail
    bne x28, x0, fail
    bne x29, x0, fail
    bne x30, x0, fail
    bne x31, x0, fail

    /* dump CSRs to SRAM 0x10000 */
    li   t0, 0x10000
    csrr t1, mstatus
    sw   t1, 0(t0)
    csrr t1, mie
    sw   t1, 4(t0)
    csrr t1, mtvec
    sw   t1, 8(t0)
    csrr t1, mscratch
    sw   t1, 12(t0)
    csrr t1, mepc
    sw   t1, 16(t0)
    csrr t1, mcause
    sw   t1, 20(t0)
    csrr t1, mtval
    sw   t1, 24(t0)
    csrr t1, misa
    sw   t1, 28(t0)
    csrr t1, mip
    sw   t1, 32(t0)
    li   t1, 0xDEADBEEF
    sw   t1, 36(t0)
done:
    j done

fail:
    li   t0, 0x10024
    li   t1, 0xDEADDEAD
    sw   t1, 0(t0)
fail_loop:
    j fail_loop

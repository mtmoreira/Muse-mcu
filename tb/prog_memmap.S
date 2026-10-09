/* prog_memmap.S -- A6 memory map and access widths.
 * 40 directed tests; each logs 3 words [status, actual, expected] to SRAM
 * 0x12000 (status = id, or 0x80000000|id on fail). DONE 0xDEADBEEF at 0x121E0.
 * Tests 39/40 (unmapped load/store) trap to a handler that checks
 * mcause/mtval and logs [id|fail, mcause, mtval].
 *
 * Trap slots at 0x12200: +0 RESUME_PC, +4 EXP_CAUSE, +8 EXP_ID,
 *                        +12 SAVE_T1, +16 SAVE_T2, +20 SAVE_T3
 */
    .text
    .globl _start

/* t1=actual, t2=expected, t3 temp, s0=log ptr (byte addr) */
.macro CHECK_EQ id
    bne  t1, t2, .Lfail\@
    li   t3, \id
    j    .Lstore\@
.Lfail\@:
    lui  t3, 0x80000
    ori  t3, t3, \id
.Lstore\@:
    sw   t3, 0(s0)
    sw   t1, 4(s0)
    sw   t2, 8(s0)
    addi s0, s0, 12
.endm

_start:
    li   sp, 0x30000
    la   t0, trap_handler
    csrw mtvec, t0
    li   s0, 0x12000             # log pointer
    lui  t0, 0x12
    addi t0, t0, 0x200          # t0 = 0x12200 trap slots

    /* ---------- ROM reads: reference = last word @0xFFFC ---------- */
    li   t4, 0xFFFC
    # 1: LW last word
    lw   t1, 0(t4)
    mv   t5, t1                 # t5 = reference
    mv   t2, t1
    CHECK_EQ 1
    # 2: LH @0xFFFE == ref>>16 (sign-extended)
    lh   t1, 2(t4)
    srai t2, t5, 16
    CHECK_EQ 2
    # 3: LHU @0xFFFC == ref & 0xFFFF
    lhu  t1, 0(t4)
    slli t2, t5, 16
    srli t2, t2, 16
    CHECK_EQ 3
    # 4: LH @0xFFFC == sign-extend(ref[15:0])
    lh   t1, 0(t4)
    slli t2, t5, 16
    srai t2, t2, 16
    CHECK_EQ 4
    # 5: LB @0xFFFF == ref>>24 (sign-extended)
    lb   t1, 3(t4)
    srai t2, t5, 24
    CHECK_EQ 5
    # 6: LBU @0xFFFD == (ref>>16)&0xFF
    lbu  t1, 1(t4)
    srli t2, t5, 16
    andi t2, t2, 0xFF
    CHECK_EQ 6
    # 7: LB @0xFFFC == sign-extend(ref[7:0])
    lb   t1, 0(t4)
    slli t2, t5, 24
    srai t2, t2, 24
    CHECK_EQ 7
    # 8: LBU @0xFFFF == (ref>>24)&0xFF
    lbu  t1, 3(t4)
    srli t2, t5, 24
    CHECK_EQ 8

    /* ---------- ROM writes are dropped ---------- */
    # 9: SB @0x200 dropped
    li   t4, 0x200
    lbu  t5, 0(t4)
    li   t1, 0xFF
    sb   t1, 0(t4)
    lbu  t1, 0(t4)
    mv   t2, t5
    CHECK_EQ 9
    # 10: SW @0x204 dropped
    li   t4, 0x204
    lw   t5, 0(t4)
    li   t1, 0x12345678
    sw   t1, 0(t4)
    lw   t1, 0(t4)
    mv   t2, t5
    CHECK_EQ 10

    /* ---------- SRAM ---------- */
    # 11: SW/LW @0x10000
    li   t4, 0x10000
    li   t5, 0xDEADBEEF
    sw   t5, 0(t4)
    lw   t1, 0(t4)
    mv   t2, t5
    CHECK_EQ 11
    # 12: SH 0x1234 @0x10010, LH back
    li   t4, 0x10010
    li   t5, 0x1234
    sh   t5, 0(t4)
    lh   t1, 0(t4)
    li   t2, 0x1234
    CHECK_EQ 12
    # 13: SH 0x8001 @0x10014, LH back (sign-extended)
    li   t4, 0x10014
    li   t5, 0x8001
    sh   t5, 0(t4)
    lh   t1, 0(t4)
    li   t2, 0xFFFF8001
    CHECK_EQ 13
    # 14: LHU @0x10014
    lhu  t1, 0(t4)
    li   t2, 0x8001
    CHECK_EQ 14
    # 15: SB 0x7F @0x10020, LB back
    li   t4, 0x10020
    li   t5, 0x7F
    sb   t5, 0(t4)
    lb   t1, 0(t4)
    li   t2, 0x7F
    CHECK_EQ 15
    # 16: SB 0x80 @0x10021, LB back (sign-extended)
    li   t4, 0x10021
    li   t5, 0x80
    sb   t5, 0(t4)
    lb   t1, 0(t4)
    li   t2, 0xFFFFFF80
    CHECK_EQ 16
    # 17: LBU @0x10021
    lbu  t1, 0(t4)
    li   t2, 0x80
    CHECK_EQ 17
    # 18: SW 0xA5A5A5A5 @0x2FFFC (last word), LW back
    li   t4, 0x2FFFC
    li   t5, 0xA5A5A5A5
    sw   t5, 0(t4)
    lw   t1, 0(t4)
    mv   t2, t5
    CHECK_EQ 18
    # 19: SB 0x42 @0x2FFFD, LB back
    li   t4, 0x2FFFD
    li   t5, 0x42
    sb   t5, 0(t4)
    lb   t1, 0(t4)
    li   t2, 0x42
    CHECK_EQ 19
    # 20: SH 0xBEEF @0x2FFF0, LH back
    li   t4, 0x2FFF0
    li   t5, 0xBEEF
    sh   t5, 0(t4)
    lh   t1, 0(t4)
    li   t2, 0xFFFFBEEF
    CHECK_EQ 20
    # 21: LHU @0x2FFF0
    lhu  t1, 0(t4)
    li   t2, 0xBEEF
    CHECK_EQ 21
    # 22: LW @0x10000 still 0xDEADBEEF
    li   t4, 0x10000
    lw   t1, 0(t4)
    li   t2, 0xDEADBEEF
    CHECK_EQ 22

    /* ---------- MMIO ---------- */
    # 23: GPIO data_out
    lui  t4, 0x10010
    li   t5, 0xA5
    sw   t5, 0x4(t4)
    lw   t1, 0x4(t4)
    li   t2, 0xA5
    CHECK_EQ 23
    # 24: GPIO dir
    li   t5, 0x3C
    sw   t5, 0x8(t4)
    lw   t1, 0x8(t4)
    li   t2, 0x3C
    CHECK_EQ 24
    # 25: GPIO scratch
    li   t5, 0xDEADBEEF
    sw   t5, 0xC(t4)
    lw   t1, 0xC(t4)
    mv   t2, t5
    CHECK_EQ 25
    # 26: GPIO data_in (tb drives 0x5A)
    lw   t1, 0(t4)
    li   t2, 0x5A
    CHECK_EQ 26
    # 27: UART bauddiv
    lui  t4, 0x10020
    li   t5, 434
    sw   t5, 0xC(t4)
    lw   t1, 0xC(t4)
    li   t2, 434
    CHECK_EQ 27
    # 28: UART status == 2 (rx_empty)
    lw   t1, 0x8(t4)
    li   t2, 2
    CHECK_EQ 28
    # 29: CLINT msip = 1
    lui  t4, 0x10000
    li   t5, 1
    sw   t5, 0(t4)
    lw   t1, 0(t4)
    li   t2, 1
    CHECK_EQ 29
    # 30: CLINT msip = 0
    sw   x0, 0(t4)
    lw   t1, 0(t4)
    mv   t2, x0
    CHECK_EQ 30
    # 31: CLINT mtimecmp lo
    lui  t4, 0x10004
    li   t5, 0x12345678
    sw   t5, 0(t4)
    lw   t1, 0(t4)
    mv   t2, t5
    CHECK_EQ 31
    # 32: CLINT mtimecmp hi
    li   t5, 0x9ABCDEF0
    sw   t5, 4(t4)
    lw   t1, 4(t4)
    mv   t2, t5
    CHECK_EQ 32
    # 33: CLINT mtime != 0
    lui  t4, 0x1000C
    lw   t4, -8(t4)
    sltu t1, x0, t4
    li   t2, 1
    CHECK_EQ 33
    # 34: SPI clkdiv
    lui  t4, 0x10030
    li   t5, 4
    sw   t5, 0x14(t4)
    lw   t1, 0x14(t4)
    li   t2, 4
    CHECK_EQ 34
    # 35: SPI txdata
    li   t5, 0xA5
    sw   t5, 0x8(t4)
    lw   t1, 0x8(t4)
    li   t2, 0xA5
    CHECK_EQ 35
    # 36: SPI cs = 0
    sw   x0, 0x10(t4)
    lw   t1, 0x10(t4)
    mv   t2, x0
    CHECK_EQ 36
    # 37: SPI cs = 1
    li   t5, 1
    sw   t5, 0x10(t4)
    lw   t1, 0x10(t4)
    li   t2, 1
    CHECK_EQ 37
    # 38: SPI status == 0
    lw   t1, 0x4(t4)
    mv   t2, x0
    CHECK_EQ 38

    /* ---------- unmapped accesses trap ---------- */
    # 39: LW @0x20000000 -> cause 5
    la   t1, after39
    sw   t1, 0(t0)
    li   t1, 5
    sw   t1, 4(t0)
    li   t1, 39
    sw   t1, 8(t0)
    lui  t1, 0x20000
    lw   t2, 0(t1)
after39:
    # 40: SW @0x20000000 -> cause 7
    la   t1, after40
    sw   t1, 0(t0)
    li   t1, 7
    sw   t1, 4(t0)
    li   t1, 40
    sw   t1, 8(t0)
    lui  t1, 0x20000
    li   t2, 0xA5A5A5A5
    sw   t2, 0(t1)
after40:
    li   t1, 0xDEADBEEF
    sw   t1, 0(s0)              # DONE at 0x121E0
done_loop:
    j done_loop

    .align 2
trap_handler:
    csrrw t0, mscratch, t0
    lui   t0, 0x12
    addi  t0, t0, 0x200
    sw    t1, 12(t0)
    sw    t2, 16(t0)
    sw    t3, 20(t0)
    csrr  t1, mcause
    lw    t2, 4(t0)             # EXP_CAUSE
    bne   t1, t2, th_fail
    csrr  t1, mtval
    lui   t2, 0x20000
    bne   t1, t2, th_fail       # mtval must be 0x20000000
    lw    t3, 8(t0)             # EXP_ID (pass)
    j     th_log
th_fail:
    lw    t3, 8(t0)
    lui   t1, 0x80000
    or    t3, t3, t1
th_log:
    csrr  t1, mcause
    csrr  t2, mtval
    sw    t3, 0(s0)
    sw    t1, 4(s0)             # mcause
    sw    t2, 8(s0)             # mtval
    addi  s0, s0, 12
    lw    t1, 0(t0)             # RESUME_PC
    csrw  mepc, t1
    lw    t1, 12(t0)
    lw    t2, 16(t0)
    lw    t3, 20(t0)
    csrr  t0, mscratch
    mret

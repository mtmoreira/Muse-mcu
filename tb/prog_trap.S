/* prog_trap.S -- A4 synchronous-trap directed tests.
 * Installs a trap handler (direct mtvec) that logs
 *   [caseid, exp_mepc, mcause, mepc, mtval] (5 words) per trap to SRAM
 *   0x10000, then resumes at a per-case RESUME_PC via mret.
 * 8 cases: illegal, ecall, ebreak, misaligned LW/SW/LH, fetch-unmapped,
 * store-unmapped. DONE marker 0xDEADBEEF at 0x10114.
 *
 * Slot map at 0x10100: +0 RESUME_PC, +4 CASEID, +8 EXP_MEPC,
 *                      +12 SAVE_T1, +16 SAVE_T2, +20 DONE
 */
    .text
    .globl _start
_start:
    li   sp, 0x30000
    la   t0, handler
    csrw mtvec, t0
    li   s0, 0x10000              # log pointer (byte address)
    lui  t0, 0x10
    addi t0, t0, 0x100           # t0 = 0x10100 (slots)

    /* ---- case 1: illegal instruction (0xFFFFFFFF) ---- */
    la   t1, case2
    sw   t1, 0(t0)
    li   t1, 1
    sw   t1, 4(t0)
    la   t1, insn1
    sw   t1, 8(t0)
insn1:
    .word 0xFFFFFFFF
case2:
    /* ---- case 2: ecall ---- */
    la   t1, case3
    sw   t1, 0(t0)
    li   t1, 2
    sw   t1, 4(t0)
    la   t1, insn2
    sw   t1, 8(t0)
insn2:
    ecall
case3:
    /* ---- case 3: ebreak ---- */
    la   t1, case4
    sw   t1, 0(t0)
    li   t1, 3
    sw   t1, 4(t0)
    la   t1, insn3
    sw   t1, 8(t0)
insn3:
    ebreak
case4:
    /* ---- case 4: misaligned LW (0x10001) ---- */
    la   t1, case5
    sw   t1, 0(t0)
    li   t1, 4
    sw   t1, 4(t0)
    la   t1, insn4
    sw   t1, 8(t0)
    li   t1, 0x10000
insn4:
    lw   t2, 1(t1)
case5:
    /* ---- case 5: misaligned SW (0x10003) ---- */
    la   t1, case6
    sw   t1, 0(t0)
    li   t1, 5
    sw   t1, 4(t0)
    la   t1, insn5
    sw   t1, 8(t0)
    li   t1, 0x10000
    li   t2, 0x12345678
insn5:
    sw   t2, 3(t1)
case6:
    /* ---- case 6: misaligned LH (0x10001) ---- */
    la   t1, case7
    sw   t1, 0(t0)
    li   t1, 6
    sw   t1, 4(t0)
    la   t1, insn6
    sw   t1, 8(t0)
    li   t1, 0x10000
insn6:
    lh   t2, 1(t1)
case7:
    /* ---- case 7: fetch from unmapped (jalr to 0x20000000) ---- */
    la   t1, case8
    sw   t1, 0(t0)
    li   t1, 7
    sw   t1, 4(t0)
    lui  t1, 0x20000             # t1 = 0x20000000
    sw   t1, 8(t0)               # EXP_MEPC = 0x20000000
    jalr x0, 0(t1)
case8:
    /* ---- case 8: store to unmapped (0x20000000) ---- */
    la   t1, done
    sw   t1, 0(t0)
    li   t1, 8
    sw   t1, 4(t0)
    la   t1, insn8
    sw   t1, 8(t0)
    lui  t1, 0x20000
    li   t2, 0xA5A5A5A5
insn8:
    sw   t2, 0(t1)
done:
    lui  t0, 0x10
    addi t0, t0, 0x100
    li   t1, 0xDEADBEEF
    sw   t1, 20(t0)              # DONE
done_loop:
    j done_loop

    .align 2
handler:
    csrrw t0, mscratch, t0      # orig t0 -> mscratch
    lui   t0, 0x10
    addi  t0, t0, 0x100         # t0 = 0x10100 (slots)
    sw    t1, 12(t0)            # SAVE_T1
    sw    t2, 16(t0)            # SAVE_T2
    lw    t1, 4(t0)             # CASEID
    sw    t1, 0(s0)             # log[0]
    lw    t1, 8(t0)             # EXP_MEPC
    sw    t1, 4(s0)             # log[1]
    csrr  t1, mcause
    sw    t1, 8(s0)             # log[2]
    csrr  t1, mepc
    sw    t1, 12(s0)            # log[3]
    csrr  t1, mtval
    sw    t1, 16(s0)            # log[4]
    addi  s0, s0, 20
    lw    t1, 0(t0)             # RESUME_PC
    csrw  mepc, t1
    lw    t1, 12(t0)            # restore t1
    lw    t2, 16(t0)            # restore t2
    csrr  t0, mscratch          # restore t0
    mret

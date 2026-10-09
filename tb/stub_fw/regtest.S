// Write x1..x31 (pattern | idx) to [base], read back to restore.
    .section .text, "ax"
    .globl ctxsave_asm
ctxsave_asm:
    // a0 = base, a1 = pattern
    add t0, a1, zero
    sw x1,  0(a0); sw x3,  4(a0); sw x4,  8(a0); sw x5,  12(a0)
    sw x6,  16(a0); sw x7, 20(a0); sw x8, 24(a0); sw x9, 28(a0)
    sw x10, 32(a0); sw x11,36(a0); sw x12,40(a0); sw x13,44(a0)
    sw x14, 48(a0); sw x15,52(a0); sw x16,56(a0); sw x17,60(a0)
    sw x18, 64(a0); sw x19,68(a0); sw x20,72(a0); sw x21,76(a0)
    sw x22, 80(a0); sw x23,84(a0); sw x24,88(a0); sw x25,92(a0)
    sw x26, 96(a0); sw x27,100(a0); sw x28,104(a0); sw x29,108(a0)
    sw x30,112(a0); sw x31,116(a0)
    ret
    .globl ctxrestore_asm
ctxrestore_asm:
    // a0 = base; reload x1..x31 from memory (simulates restore)
    lw x1,  0(a0); lw x3,  4(a0); lw x4,  8(a0); lw x5,  12(a0)
    lw x6,  16(a0); lw x7, 20(a0); lw x8, 24(a0); lw x9, 28(a0)
    lw x10, 32(a0); lw x11,36(a0); lw x12,40(a0); lw x13,44(a0)
    lw x14, 48(a0); lw x15,52(a0); lw x16,56(a0); lw x17,60(a0)
    lw x18, 64(a0); lw x19,68(a0); lw x20,72(a0); lw x21,76(a0)
    lw x22, 80(a0); lw x23,84(a0); lw x24,88(a0); lw x25,92(a0)
    lw x26, 96(a0); lw x27,100(a0); lw x28,104(a0); lw x29,108(a0)
    lw x30,112(a0); lw x31,116(a0)
    ret

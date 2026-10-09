// crt0.S — Muse MCU bare-metal reset entry.
//
// Reset vector is 0x00000000; the linker script places _start there.
// On entry:
//   1. sp is set to 0x00030000 (top of the 128 KiB SRAM at 0x00010000).
//   2. mtvec is pointed at trap_handler (direct mode).
//   3. .bss is zeroed.
//   4. .data is copied from its ROM load address to its RAM run address.
//   5. main() is called; if it returns, the core spins.
//
// trap_handler (minimal, for bare-metal tests):
//   - records mcause to the GPIO dbg_scratch register (0x1001000C)
//   - ecall with a0==0 is the bare-metal "done" convention: print nothing,
//     spin silently. Any other trap (including ecall with a0!=0) also
//     spins after recording mcause; firmware never returns from a trap.
// An application that needs interrupts installs its own mtvec handler
// after startup (see fw/app/timer_gpio_test.c).

    .section .text.init, "ax", @progbits
    .globl _start
    .align 2
_start:
    li sp, 0x00030000            // top of SRAM
    la t0, trap_handler
    csrw mtvec, t0

    // clear .bss
    la t0, __bss_start
    la t1, __bss_end
.Lbss:
    bgeu t0, t1, .Ldata
    sw zero, 0(t0)
    addi t0, t0, 4
    j .Lbss

    // copy .data: ROM (load) -> RAM (run)
.Ldata:
    la t0, __data_start
    la t1, __data_end
    la t2, __data_load_start
.Lcopy:
    bgeu t0, t1, .Lmain
    lw t3, 0(t2)
    sw t3, 0(t0)
    addi t0, t0, 4
    addi t2, t2, 4
    j .Lcopy

.Lmain:
    jal ra, main
    // main returned: spin forever
.Lspin:
    j .Lspin

    .align 2
trap_handler:
    csrr t0, mcause
    li t1, 0x1001000C            // GPIO dbg_scratch
    sw t0, 0(t1)                // record mcause for the testbench
    // ecall (mcause 11) with a0==0: done convention, spin silently.
    // Anything else: spin as well; bare-metal tests never resume.
.Ltrap_spin:
    j .Ltrap_spin

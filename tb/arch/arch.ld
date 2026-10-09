/* arch.ld — linker script for riscv-arch-test cases (DUT and Spike builds).
 *
 * Same memory map as the MCU firmware: ROM at 0x0 (test code), RAM at
 * 0x10000 (test data/scratch, HTIF mailbox). _start is linked at 0x0.
 * The DUT and Spike ELFs use this same script so test code lands at
 * identical addresses in both (required: jal/jalr/auipc capture PCs).
 *
 * Sections:
 *   .text      ROM  — _start, test code, RVTEST_CODE_END epilog
 *   .arch_data RAM  — 2K pad + `scratch` label + test-data words
 *   .signature 0x00018000 (RAM) — count word + SIGUPD_COUNT sig words
 *   .tohost    RAM  — HTIF mailbox (Spike build only; empty in DUT build)
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 128K
}

SECTIONS
{
    .text :
    {
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > ROM

    .arch_data :
    {
        *(.arch_data)
    } > RAM

    .signature 0x00018000 :
    {
        *(.signature)
    } > RAM

    .tohost :
    {
        *(.tohost)
    } > RAM

    /DISCARD/ :
    {
        *(.comment .comment.*)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
    }
}

/* The signature region must not collide with .arch_data (which grows up
 * from 0x10000). Largest .arch_data seen: < 8 KiB; 0x18000 is 32 KiB up. */


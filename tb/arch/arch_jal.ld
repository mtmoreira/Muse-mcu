/* arch_jal.ld — linker script for I-jal-00 ONLY.
 *
 * I-jal-00's .text is ~112 KiB (the test uses .p2align up to 14 to check
 * jal with large offsets). It does not fit in the 64 KiB boot ROM, so
 * .text spans ROM+SRAM contiguously from 0x0. The DUT bus serves
 * instruction fetch from both, so execution is seamless.
 *
 * Layout:
 *   .text      0x0       (~112K, ROM+SRAM)
 *   .arch_data follows .text (SRAM; writable scratch required)
 *   .signature 0x00024000 (moved from 0x18000: .text covers it)
 *   .tohost    follows .signature
 *
 * The .hex image is a flat binary from 0x0. The testbench must load
 * words[16384:] into dut.ram.mem (SRAM word index = byte_addr[16:2],
 * so hex word 16384 -> dut.ram.mem[0x4000]). See tb/arch/README.md.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    XMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 192K  /* ROM+SRAM, fetchable */
    RAM  (rwx) : ORIGIN = 0x00010000, LENGTH = 128K
}

SECTIONS
{
    .text 0x0 :
    {
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > XMEM

    .arch_data :
    {
        *(.arch_data)
    } > XMEM

    .signature 0x00024000 :
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

/* .arch_data must land in SRAM (writable); validated by build_arch.py. */

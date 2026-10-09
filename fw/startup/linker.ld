/* linker.ld — Muse MCU bare-metal firmware.
 *
 * ROM  (rx)  : ORIGIN 0x00000000, 64 KiB  — code executes here.
 * RAM  (rwx) : ORIGIN 0x00010000, 128 KiB — data, bss, stack.
 *
 * _start (from crt0.S .text.init) is linked at 0x00000000, the reset vector.
 * .data is loaded in ROM but runs in RAM (copied by crt0).
 * _stack_top = 0x00030000 (top of SRAM); matches the literal in crt0.S.
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
        KEEP(*(.text.init))
        *(.text .text.*)
        *(.rodata .rodata.*)
        _etext = .;
    } > ROM

    .data :
    {
        __data_load_start = LOADADDR(.data);
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        __data_end = .;
    } > RAM AT > ROM

    .bss (NOLOAD) :
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /* Stack / heap symbols for C code. */
    _stack_top  = ORIGIN(RAM) + LENGTH(RAM);   /* 0x00030000 */
    _heap_start = __bss_end;
    _heap_end   = ORIGIN(RAM) + LENGTH(RAM);

    /DISCARD/ :
    {
        *(.eh_frame .eh_frame.*)
        *(.note .note.*)
        *(.comment .comment.*)
    }
}

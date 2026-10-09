/* Minimal linker script for Phase-3a directed-test mini-programs.
 * ROM  0x00000000, 64 KiB, rx  (_start at 0x0)
 * RAM  0x00010000, 128 KiB, rwx (stack top 0x00030000)
 */
MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
  RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 128K
}

ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text : {
    *(.text.start)
    *(.text*)
  } > ROM

  .rodata : {
    *(.rodata*)
  } > ROM

  /* everything else (data/bss/stack) lives in SRAM */
  .data : {
    *(.data*)
    *(.sdata*)
  } > RAM

  .bss (NOLOAD) : {
    *(.bss*)
    *(.sbss*)
    *(COMMON)
  } > RAM

  _stack_top = 0x00030000;
}

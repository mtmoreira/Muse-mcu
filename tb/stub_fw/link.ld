/* Stub linker script for Muse-mcu tb validation. ROM 0x0 (64K), RAM 0x10000 (128K). */
MEMORY {
  ROM : ORIGIN = 0x00000000, LENGTH = 64K
  RAM : ORIGIN = 0x00010000, LENGTH = 128K
}
ENTRY(_start)
SECTIONS {
  .text : {
    *(.text.init)
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > ROM
  .data : {
    _data_start = .;
    *(.data .data.*)
    _data_end = .;
  } > RAM AT > ROM
  _data_load = LOADADDR(.data);
  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    _bss_end = .;
  } > RAM
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

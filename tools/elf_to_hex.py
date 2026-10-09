#!/usr/bin/env python3
"""elf_to_hex.py — convert a raw firmware binary to Verilog $readmemh hex.

Usage: elf_to_hex.py <input.bin> <output.hex>

The input is the objcopy -O binary image of the firmware ELF (loaded at
0x00000000, the boot ROM base). The output is 32-bit little-endian words,
one lowercase hex word per line, suitable for $readmemh into the bootrom
model (16384 x 32-bit words).

The output is padded to exactly 16384 words with 0x0000006f (jal x0,0, an
infinite loop to self) so that no uninitialized (X) words remain in the ROM
model and a runaway PC spins harmlessly instead of fetching X.
"""
import struct
import sys

ROM_WORDS = 16384
PAD_WORD = 0x0000006F  # jal x0, 0


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: elf_to_hex.py <input.bin> <output.hex>", file=sys.stderr)
        sys.exit(2)
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        data = f.read()
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)
    words = list(struct.iter_unpack("<I", data))
    if len(words) > ROM_WORDS:
        print("error: firmware image %d words exceeds 64 KiB ROM" % len(words),
              file=sys.stderr)
        sys.exit(1)
    words += [(PAD_WORD,)] * (ROM_WORDS - len(words))
    with open(dst, "w") as f:
        for (word,) in words:
            f.write("%08x\n" % word)


if __name__ == "__main__":
    main()

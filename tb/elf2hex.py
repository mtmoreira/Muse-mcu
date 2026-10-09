#!/usr/bin/env python3
"""Convert a mini-program ELF to a 32-bit word hex file for $readmemh.

Usage: elf2hex.py <prog.elf> <prog.hex> [objcopy]

Packs the ELF's binary image little-endian into 32-bit words, one %08x per
line, padded out to the full 64 KiB boot ROM (16384 words) with a
jal-to-self infinite loop (0x0000006f) so stray fetches never hit X.
"""
import struct
import subprocess
import sys

ROM_WORDS = 16384
PAD_WORD = 0x0000006F  # jal x0, 0 : infinite loop to self


def main():
    elf, hexpath = sys.argv[1], sys.argv[2]
    objcopy = sys.argv[3] if len(sys.argv) > 3 else "riscv-none-elf-objcopy"
    binpath = elf + ".bin"
    subprocess.run([objcopy, "-O", "binary", elf, binpath], check=True)
    with open(binpath, "rb") as f:
        data = f.read()
    nwords = (len(data) + 3) // 4
    if nwords > ROM_WORDS:
        sys.exit(f"elf2hex: image {nwords} words exceeds 64 KiB ROM")
    words = struct.unpack("<%dI" % nwords, data.ljust(nwords * 4, b"\x00"))
    words = list(words) + [PAD_WORD] * (ROM_WORDS - nwords)
    with open(hexpath, "w") as f:
        f.write("\n".join("%08x" % w for w in words) + "\n")
    print(f"elf2hex: {elf} -> {hexpath} ({nwords} image words)")


if __name__ == "__main__":
    main()

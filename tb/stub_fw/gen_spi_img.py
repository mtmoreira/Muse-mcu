#!/usr/bin/env python3
"""Generate a 256-byte PRBS flash image for tb_spi validation (STAND-IN).
The real spi image comes from the bare-metal worker; this only validates tb logic."""
import sys
state = 0xACE1
out = bytearray()
for _ in range(256):
    b = 0
    for _ in range(8):
        bit = ((state >> 0) ^ (state >> 2) ^ (state >> 3) ^ (state >> 5)) & 1
        state = (state >> 1) | (bit << 15)
        b = (b << 1) | bit
    out.append(b)
open(sys.argv[1] if len(sys.argv) > 1 else "spi_img.bin", "wb").write(out)
print("wrote 256-byte PRBS image")

#!/usr/bin/env python3
"""Build the SPI flash image for the F2 gate-level application SUBSET.

Same layout and byte-stream convention as tools/gen_flash.py (FSLA magic,
version 1, seed, msg_count; per message: id u32, len u32, then the
xorshift32(seed ^ id) little-endian byte stream), but with exactly the 4
messages the F2 requirement prescribes:

  ids 0..3, lengths {0, 56, 64, 1024}

The firmware image for F2 is built with -DFLASH_MSG_COUNT=4 (see
fw/app/app_demo.c); the host checker tools/check_app.py verifies the UART
stream against THIS image with --expect-nmsg 4.

Usage: tools/gen_flash_f2.py --seed S --out flash_f2.hex
(writes byte-per-line hex: loadable by spiflash.v, tb_app.sv and check_app.py)
"""
import argparse
import json
import struct
import sys

sys.path.insert(0, "tools")
from gen_flash import (  # noqa: E402  (same PRNG/stream convention as D1)
    MAGIC, VERSION, M32, xorshift32, stream_bytes,
)

F2_LENGTHS = [0, 56, 64, 1024]


def build(seed):
    img = bytearray()
    img += struct.pack("<IIII", MAGIC, VERSION, seed & M32, len(F2_LENGTHS))
    table = []
    for msg_id, length in enumerate(F2_LENGTHS):
        data = stream_bytes(seed, msg_id, length)
        img += struct.pack("<II", msg_id, length)
        img += data
        table.append({"id": msg_id, "len": length})
    return bytes(img), table


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=lambda s: int(s, 0), required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    img, table = build(args.seed & M32)
    with open(args.out, "w") as f:
        for b in img:
            f.write(f"{b:02x}\n")
    print(json.dumps({"seed": args.seed & M32, "messages": table}))
    print(f"wrote {args.out}: {len(img)} bytes, {len(table)} messages",
          file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())

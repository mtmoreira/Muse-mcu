#!/usr/bin/env python3
"""Build the SPI flash image for the app_demo (D1) workload.

Flash layout (all multi-byte fields little-endian):
  header (16 bytes): magic u32 = 0x46534C41 ("FSLA"), version u32 = 1,
                     seed u32, msg_count u32 = 24
  then 24 messages, each:
      id u32, len u32, then len content bytes

Message set (frozen, byte-for-byte contract with fw/app/app_demo.c and the
host checker tools/check_app.py):
  ids 0..15:  fixed lengths {0,1,55,56,57,63,64,65,119,120,127,128,129,255,512,1024}
  ids 16..23: lengths = 1 + (prng(seed) % 300), where prng is xorshift32
              seeded with (seed | 1), one output per message in id order.
  content bytes for EVERY message: the xorshift32(seed ^ id) byte stream
  (each 32-bit output emitted little-endian, truncated to len bytes).
  A zero (seed ^ id) state is replaced with 0x2545F491 so the stream is
  never degenerate.

xorshift32 (32-bit wraparound):
  x ^= (x << 13) & 0xFFFFFFFF; x ^= x >> 17; x ^= (x << 5) & 0xFFFFFFFF

Usage: tools/gen_flash.py --seed S --out flash.bin
Prints the (id, len) table as JSON on stdout for the host checker.
"""
import argparse
import json
import struct
import sys

MAGIC = 0x46534C41
VERSION = 1
MSG_COUNT = 24
FIXED_LENGTHS = [0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 255, 512, 1024]
M32 = 0xFFFFFFFF


def xorshift32(x):
    x ^= ((x << 13) & M32)
    x ^= (x >> 17)
    x ^= ((x << 5) & M32)
    return x & M32


def stream_bytes(seed, msg_id, n):
    """First n bytes of the xorshift32(seed ^ id) stream, LE word emission."""
    state = (seed ^ msg_id) & M32
    if state == 0:
        state = 0x2545F491
    out = bytearray()
    while len(out) < n:
        state = xorshift32(state)
        out += struct.pack("<I", state)
    return bytes(out[:n])


def seeded_lengths(seed):
    """8 lengths for ids 16..23: 1 + (prng(seed) % 300)."""
    state = (seed | 1) & M32
    lens = []
    for _ in range(8):
        state = xorshift32(state)
        lens.append(1 + (state % 300))
    return lens


def build(seed):
    img = bytearray()
    img += struct.pack("<IIII", MAGIC, VERSION, seed & M32, MSG_COUNT)
    table = []
    for msg_id in range(MSG_COUNT):
        if msg_id < 16:
            length = FIXED_LENGTHS[msg_id]
        else:
            length = seeded_lengths(seed)[msg_id - 16]
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
    with open(args.out, "wb") as f:
        f.write(img)
    print(json.dumps({"seed": args.seed & M32, "messages": table}))
    print(f"wrote {args.out}: {len(img)} bytes, {len(table)} messages",
          file=sys.stderr)


if __name__ == "__main__":
    main()

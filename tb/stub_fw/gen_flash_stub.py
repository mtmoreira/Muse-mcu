#!/usr/bin/env python3
"""STAND-IN flash image generator (tb validation only).
Same layout as tools/gen_flash.py will produce: header + [id,len,data]*.
Usage: gen_flash_stub.py --seed S --nmsg N --out f.bin"""
import argparse, struct, sys

def xorshift32(state):
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= (state >> 17)
    state ^= (state << 5) & 0xFFFFFFFF
    return state & 0xFFFFFFFF

FIXED = {0:0, 1:1, 2:55, 3:56, 4:57, 5:63, 6:64, 7:65, 8:119, 9:120,
         10:127, 11:128, 12:129, 13:255, 14:512, 15:1024}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--nmsg", type=int, default=24)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = bytearray()
    out += struct.pack("<IIII", 0x46534C41, 1, a.seed, a.nmsg)
    st = a.seed & 0xFFFFFFFF
    for mid in range(a.nmsg):
        if mid in FIXED:
            ln = FIXED[mid]
        else:
            st = xorshift32(st if st else 1)
            ln = 1 + (st % 300)
        out += struct.pack("<II", mid, ln)
        st2 = (a.seed ^ (mid * 0x9E3779B9)) & 0xFFFFFFFF
        for _ in range(ln):
            st2 = xorshift32(st2 if st2 else 1)
            out.append((st2 >> 24) & 0xFF)
    open(a.out, "wb").write(out)
    print(f"wrote {a.out}: {a.nmsg} msgs, {len(out)} bytes")

main()

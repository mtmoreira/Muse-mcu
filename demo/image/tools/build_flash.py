#!/usr/bin/env python3
"""Build the SPI flash image for the image demo.

Layout: 20-byte little-endian MIMG header (spec Section 2.1) followed
by the 4096 raw pixels. Outputs <prefix>.bin and <prefix>.hex
(one byte per line, for the spiflash model's $readmemh).
"""
import argparse
import hashlib
import json
import struct


def build(raw, frame_id):
    assert len(raw) == 4096
    hdr = bytearray()
    hdr += b"MIMG"
    hdr += bytes([1, 1])              # version, format GRAY8
    hdr += struct.pack("<H", 0)       # flags
    hdr += struct.pack("<I", frame_id)
    hdr += struct.pack("<H", 64)      # width
    hdr += struct.pack("<H", 64)      # height
    hdr += struct.pack("<I", 4096)    # payload length
    assert len(hdr) == 20
    return bytes(hdr) + raw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--frame", type=int, required=True)
    ap.add_argument("--out-prefix", required=True)
    args = ap.parse_args()

    raw = open(args.raw, "rb").read()
    img = build(raw, args.frame)
    with open(args.out_prefix + ".bin", "wb") as f:
        f.write(img)
    with open(args.out_prefix + ".hex", "w") as f:
        for b in img:
            f.write(f"{b:02x}\n")
    print(json.dumps({
        "flash_bin": args.out_prefix + ".bin",
        "flash_hex": args.out_prefix + ".hex",
        "frame_id": args.frame,
        "bytes": len(img),
        "flash_sha256": hashlib.sha256(img).hexdigest(),
        "raw_sha256": hashlib.sha256(raw).hexdigest(),
    }))


if __name__ == "__main__":
    main()

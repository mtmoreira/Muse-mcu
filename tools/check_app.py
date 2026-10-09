#!/usr/bin/env python3
"""Muse MCU D1 host checker.

Verifies the UART packet stream captured by tb_app.sv against the flash
image: packet count, id/len sequence, and SHA-256 digests (Python hashlib).

Usage:
  check_app.py --uart <uart.log> --flash <flash.hex> [--expect-nmsg N]

The flash image is the raw binary format hex dump (one byte per line):
  header [magic 0x46534C41 LE u32, version=1 LE u32, seed LE u32,
          msg_count LE u32], then per message [id LE u32, len LE u32, data].

Exits 0 only if every packet is present, in order, with matching id, length
and digest. Prints per-packet OK/FAIL lines.
"""
import argparse
import hashlib
import re
import struct
import sys


def parse_flash(path):
    data = bytearray()
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(int(line, 16))
    data = bytes(data)
    if len(data) < 16:
        raise ValueError(f"flash image too short ({len(data)} bytes)")
    magic, ver, seed, nmsg = struct.unpack('<IIII', data[:16])
    if magic != 0x46534C41:
        raise ValueError(f"bad flash magic {magic:#010x}")
    if ver != 1:
        raise ValueError(f"unsupported flash version {ver}")
    msgs = []
    off = 16
    for _ in range(nmsg):
        if off + 8 > len(data):
            raise ValueError("flash image truncated in message header")
        mid, ln = struct.unpack('<II', data[off:off + 8])
        if off + 8 + ln > len(data):
            raise ValueError(f"flash image truncated in message {mid} data")
        msgs.append((mid, ln, data[off + 8:off + 8 + ln]))
        off += 8 + ln
    return msgs


PKT_RE = re.compile(r'^PKT 9E55AA01 (\d+) (\d+) ([0-9a-fA-F]{64})$')


def parse_uart(path):
    pkts = []
    with open(path, 'rb') as f:
        for raw in f:
            try:
                line = raw.decode('ascii').strip()
            except UnicodeDecodeError:
                continue
            m = PKT_RE.match(line)
            if m:
                pkts.append((int(m.group(1)), int(m.group(2)), m.group(3).lower()))
    return pkts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--uart', required=True, help='captured UART byte log')
    ap.add_argument('--flash', required=True, help='flash image hex (byte/line)')
    ap.add_argument('--expect-nmsg', type=int, default=None,
                    help='require exactly this many messages in the image')
    args = ap.parse_args()

    try:
        msgs = parse_flash(args.flash)
    except (ValueError, OSError) as e:
        print(f"CHECK_APP: FAIL (flash parse: {e})")
        return 1
    nmsg = len(msgs)
    if args.expect_nmsg is not None and nmsg != args.expect_nmsg:
        print(f"CHECK_APP: FAIL (flash has {nmsg} messages, expected {args.expect_nmsg})")
        return 1

    try:
        pkts = parse_uart(args.uart)
    except OSError as e:
        print(f"CHECK_APP: FAIL (uart log: {e})")
        return 1

    ok = True
    if len(pkts) != nmsg:
        print(f"CHECK_APP: FAIL packet count {len(pkts)} != message count {nmsg}")
        ok = False

    for i, (mid, ln, data) in enumerate(msgs):
        expect = hashlib.sha256(data).hexdigest()
        if i < len(pkts):
            pid, plen, pdigest = pkts[i]
            reasons = []
            if pid != mid:
                reasons.append(f"id {pid} != expected {mid} (sequence error)")
            if plen != ln:
                reasons.append(f"len {plen} != expected {ln}")
            if pdigest != expect:
                reasons.append("digest mismatch")
            if reasons:
                print(f"PKT {mid}: FAIL ({'; '.join(reasons)})")
                ok = False
            else:
                print(f"PKT {mid}: OK len={ln} digest={expect[:16]}...")
        else:
            print(f"PKT {mid}: FAIL (missing packet)")
            ok = False

    for j in range(nmsg, len(pkts)):
        pid, plen, pdigest = pkts[j]
        print(f"PKT {pid}: FAIL (extra packet at position {j})")
        ok = False

    print(f"CHECK_APP: {'ALL PASS' if ok else 'FAIL'} ({len(pkts)}/{nmsg} packets)")
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())

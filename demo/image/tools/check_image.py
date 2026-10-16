#!/usr/bin/env python3
"""Independent functional checker for the image demo (spec S3.2).

Fault-blind: this program never reads the fault flag, fault
coordinates or any negative-control expectation. It compares, each
separately:

  spi_payload     SPI read payload decoded from the stage02 VCD vs
                  the canonical input pixels (+ MIMG header bytes)
  input_sram      committed input-buffer writes vs canonical image
  gradients_sram  committed Gx/Gy writes vs the OpenCV reference
  output_sram     committed output-buffer writes vs reference image
  uart_packet     pin-decoded packet: header fields, digest over the
                  received header+payload, payload == stored framebuffer
  uart_vs_ref     UART payload vs the independent reference image
  task_evidence   trace-code ordering (dependencies actually enforced)
  tb_protocol     tb protocol verdict (length, quiet window, watchdog)

Exit 0 only if every check passes. Per-check detail lands in
results.json in the run directory.
"""
import argparse
import hashlib
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_tools import parse_vcd, decode_spi  # noqa: E402

import numpy as np  # noqa: E402

NPIX = 4096


def load_csv_writes(path):
    rows = []
    with open(path) as f:
        next(f)
        for line in f:
            c, a, d, s = line.strip().split(",")
            rows.append((int(c), int(a, 16), int(d, 16), int(s, 16)))
    return rows


def reconstruct(rows, base, size):
    """Final committed byte image of [base, base+size) + coverage set."""
    buf = bytearray(size)
    covered = set()
    for _c, addr, data, strb in rows:
        for lane in range(4):
            if strb & (1 << lane):
                off = addr + lane - base
                if 0 <= off < size:
                    buf[off] = (data >> (8 * lane)) & 0xFF
                    covered.add(off)
    return bytes(buf), covered


def diff_list(a, b, limit=20):
    out = []
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            out.append({"offset": i, "x": i % 64, "y": i // 64,
                        "expected": int(x), "actual": int(y)})
            if len(out) >= limit:
                break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--input-raw", required=True)
    ap.add_argument("--ref-dir", required=True)
    ap.add_argument("--flash-bin", required=True)
    args = ap.parse_args()
    R = args.run_dir
    checks = {}

    syms = json.load(open(os.path.join(R, "symbols.json")))
    base = {k: int(v, 16) for k, v in syms.items() if k.startswith("img_")}
    canonical = open(args.input_raw, "rb").read()
    flash = open(args.flash_bin, "rb").read()
    rows = load_csv_writes(os.path.join(R, "writes.csv"))

    # ---- SPI payload decoded from the stage02 VCD ----
    vcd02 = os.path.join(R, "stage02_load_overview.vcd")
    if os.path.exists(vcd02):
        _ts, d = parse_vcd(vcd02, {"spi_cs_n", "spi_sck", "spi_mosi",
                                   "spi_miso"})
        txns = decode_spi(d["spi_cs_n"], d["spi_sck"], d["spi_mosi"],
                          d["spi_miso"])
        hdr_read, payload = None, bytearray()
        cmds = []
        for _t0, _t1, mb, ib in txns:
            if not mb:
                continue
            cmds.append(mb[0])
            if mb[0] == 0x03 and len(mb) >= 4:
                addr = (mb[1] << 16) | (mb[2] << 8) | mb[3]
                data = bytes(ib[4:])
                if addr == 0:
                    hdr_read = data
                else:
                    payload += data
        spi_ok = (hdr_read == flash[:20]
                  and bytes(payload) == canonical)
        checks["spi_payload"] = {
            "pass": bool(spi_ok),
            "transactions": len(txns),
            "commands": [hex(c) for c in cmds[:5]] + ["..."],
            "header_read_matches_flash": hdr_read == flash[:20],
            "payload_bytes": len(payload),
            "payload_matches_canonical": bytes(payload) == canonical,
        }
    else:
        checks["spi_payload"] = {"pass": False, "error": "stage02 VCD missing"}

    # ---- SRAM reconstructions ----
    img_in, cov_in = reconstruct(rows, base["img_in"], NPIX)
    checks["input_sram"] = {
        "pass": img_in == canonical and len(cov_in) == NPIX,
        "coverage": len(cov_in),
        "mismatches": diff_list(canonical, img_in),
    }
    gx_ref = np.load(os.path.join(args.ref_dir, "gx.npy")).ravel()
    gy_ref = np.load(os.path.join(args.ref_dir, "gy.npy")).ravel()
    ref_out = open(os.path.join(args.ref_dir, "ref_out.raw"), "rb").read()

    gx_bytes, cov_gx = reconstruct(rows, base["img_gx"], 2 * NPIX)
    gy_bytes, cov_gy = reconstruct(rows, base["img_gy"], 2 * NPIX)
    gx = np.frombuffer(gx_bytes, "<i2").astype(np.int32)
    gy = np.frombuffer(gy_bytes, "<i2").astype(np.int32)
    gx_bad = int((gx != gx_ref.astype(np.int32)).sum())
    gy_bad = int((gy != gy_ref.astype(np.int32)).sum())
    checks["gradients_sram"] = {
        "pass": gx_bad == 0 and gy_bad == 0
                and len(cov_gx) == 2 * NPIX and len(cov_gy) == 2 * NPIX,
        "gx_mismatches": gx_bad, "gy_mismatches": gy_bad,
        "gx_coverage": len(cov_gx), "gy_coverage": len(cov_gy),
    }

    img_out, cov_out = reconstruct(rows, base["img_out"], NPIX)
    out_diffs = diff_list(ref_out, img_out, limit=100000)
    checks["output_sram"] = {
        "pass": len(out_diffs) == 0 and len(cov_out) == NPIX,
        "coverage": len(cov_out),
        "mismatch_count": len(out_diffs),
        "mismatches": out_diffs[:20],
    }

    # ---- UART packet ----
    cap = open(os.path.join(R, "uart_capture.bin"), "rb").read()
    pkt = {"length": len(cap)}
    if len(cap) == 4148:
        hdr, payload, digest = cap[:20], cap[20:4116], cap[4116:]
        magic_ok = hdr[:4] == b"MIMG"
        fields_ok = (hdr[4] == 1 and hdr[5] == 1
                     and struct.unpack("<I", hdr[8:12])[0]
                     == struct.unpack("<I", flash[8:12])[0]
                     and struct.unpack("<H", hdr[12:14])[0] == 64
                     and struct.unpack("<H", hdr[14:16])[0] == 64
                     and struct.unpack("<I", hdr[16:20])[0] == 4096)
        digest_ok = hashlib.sha256(hdr + payload).digest() == digest
        stored_ok = payload == img_out
        pkt.update({"magic_ok": magic_ok, "fields_ok": bool(fields_ok),
                    "digest_ok": bool(digest_ok),
                    "payload_equals_stored_framebuffer": bool(stored_ok)})
        checks["uart_packet"] = {
            "pass": bool(magic_ok and fields_ok and digest_ok and stored_ok),
            **pkt,
        }
        ref_diffs = diff_list(ref_out, payload, limit=100000)
        checks["uart_vs_ref"] = {
            "pass": len(ref_diffs) == 0,
            "mismatch_count": len(ref_diffs),
            "mismatches": ref_diffs[:20],
        }
    else:
        checks["uart_packet"] = {"pass": False, **pkt,
                                 "error": "packet length != 4148"}
        checks["uart_vs_ref"] = {"pass": False, "error": "no packet"}

    # ---- task / queue evidence ----
    ev = []
    with open(os.path.join(R, "events.csv")) as f:
        next(f)
        for line in f:
            c, v = line.strip().split(",")
            ev.append((int(c), int(v, 16)))
    codes = {}
    for c, v in ev:
        codes.setdefault(v, []).append(c)
    problems = []

    def at(code):
        return codes.get(code, [None])[0]

    load_done = at(0x1001)
    if load_done is None:
        problems.append("no load-done trace")
    for s in range(16):
        g, h, cb = at(0x2000 | s), at(0x3000 | s), at(0x4000 | s)
        if g is None or h is None or cb is None:
            problems.append(f"stripe {s}: missing task trace")
            continue
        if load_done is not None and (g < load_done or h < load_done):
            problems.append(f"stripe {s}: gradient before load done")
        if not (g < cb and h < cb):
            problems.append(f"stripe {s}: combine before both gradients")
        if s and at(0x4000 | (s - 1)) is not None and cb < at(0x4000 | (s - 1)):
            problems.append(f"stripe {s}: combine out of order")
    frame, exp = at(0x5000), at(0x6000)
    if frame is None or exp is None:
        problems.append("missing frame-done or export trace")
    elif at(0x4000 | 15) is not None and not (at(0x4000 | 15) < frame < exp):
        problems.append("frame/export ordering wrong")
    for code in (0x1001, 0x5000, 0x6000, 0x6001):
        if len(codes.get(code, [])) != 1:
            problems.append(f"trace 0x{code:x} seen {len(codes.get(code, []))}x")
    checks["task_evidence"] = {"pass": not problems, "problems": problems}

    # ---- tb protocol ----
    tb = json.load(open(os.path.join(R, "tb_result.json")))
    checks["tb_protocol"] = {
        "pass": tb["protocol_pass"] == 1 and tb["extra_bytes_in_observation"] == 0,
        **tb,
    }

    functional = all(c["pass"] for c in checks.values())
    results = {"functional": "PASS" if functional else "FAIL",
               "checks": checks}
    with open(os.path.join(R, "results.json"), "w") as f:
        json.dump(results, f, indent=2)
    for name, c in checks.items():
        print(f"CHECK {name}: {'PASS' if c['pass'] else 'FAIL'}")
    print(f"FUNCTIONAL: {results['functional']}")
    return 0 if functional else 1


if __name__ == "__main__":
    raise SystemExit(main())

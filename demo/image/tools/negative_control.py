#!/usr/bin/env python3
"""Negative-control wrapper for the fault run (spec Section 4).

This wrapper MAY know about the fault (it is the experiment harness,
not a functional checker). It succeeds only if ALL hold:
  - the tb recorded exactly one injection, at the target byte,
    honouring the byte lane, committed = intended XOR 0x80
  - the SRAM readback byte matches the committed value
  - input loading and both gradient checks still PASS
  - packet integrity: uart_packet check PASSES (digest matches the
    transmitted, corrupted contents; payload == stored framebuffer)
  - the unchanged functional checker FAILED the run, with exactly
    one output mismatch, at (32,32), actual == expected XOR 0x80
    in both the stored framebuffer and the UART payload
Prints the three separate verdicts required by the spec.
"""
import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    args = ap.parse_args()
    R = args.run_dir
    res = json.load(open(os.path.join(R, "results.json")))
    tb = json.load(open(os.path.join(R, "tb_result.json")))
    syms = json.load(open(os.path.join(R, "symbols.json")))
    out_base = int(syms["img_out"], 16)
    problems = []

    f = tb.get("fault")
    if not tb.get("fault_fired"):
        problems.append("fault never fired")
    elif f is None:
        problems.append("no fault record")
    else:
        if int(f["addr"], 16) != out_base + 2080:
            problems.append(f"fault addr {f['addr']} != target")
        if int(f["be"], 16) & 1 == 0:
            problems.append("byte lane 0 not enabled")
        if int(f["committed"], 16) != int(f["intended"], 16) ^ 0x80:
            problems.append("committed != intended XOR 0x80")
        if int(f["readback_byte"], 16) != int(f["committed"], 16):
            problems.append("SRAM readback != committed value")

    c = res["checks"]
    for name in ("spi_payload", "input_sram", "gradients_sram",
                 "task_evidence", "tb_protocol"):
        if not c[name]["pass"]:
            problems.append(f"{name} should PASS in the fault run")
    packet_integrity = c["uart_packet"]["pass"]
    if not packet_integrity:
        problems.append("uart_packet should PASS (digest over corrupted data)")

    image_reject = (res["functional"] == "FAIL"
                    and c["output_sram"]["mismatch_count"] == 1
                    and c["uart_vs_ref"]["mismatch_count"] == 1)
    if not image_reject:
        problems.append("functional checker did not reject with exactly "
                        "one mismatch")
    else:
        for src in ("output_sram", "uart_vs_ref"):
            m = c[src]["mismatches"][0]
            if (m["x"], m["y"]) != (32, 32):
                problems.append(f"{src}: mismatch at {(m['x'], m['y'])}")
            if m["actual"] != m["expected"] ^ 0x80:
                problems.append(f"{src}: actual != expected XOR 0x80")

    print(f"packet integrity: {'MATCH' if packet_integrity else 'MISMATCH'}")
    print(f"image reference:  {'MISMATCH' if image_reject else 'MATCH'}")
    detected = not problems
    print(f"negative-control detection: {'CONFIRMED' if detected else 'NOT CONFIRMED'}")
    for p in problems:
        print(f"  problem: {p}")
    return 0 if detected else 1


if __name__ == "__main__":
    raise SystemExit(main())

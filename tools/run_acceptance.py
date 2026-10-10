#!/usr/bin/env python3
"""run_acceptance.py — R2: one-command acceptance runner.

Parses acceptance/manifest.yaml and executes every mandatory gate.
Exits 0 only if every requirement is PASS. Skipped/blocked/unexercised
requirements are reported, never passed.

Usage: python3 tools/run_acceptance.py [--smoke]
  --smoke: run only the labeled fast subset (A3, A4, A6, C1-quick).
"""
import argparse
import os
import subprocess
import sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Enforce toolchain PATH before running gates: the setup.sh-built Icarus
# 12.x must come before any Homebrew v13. Uses TOOLCHAIN_ROOT env var
# (set by activate.sh or caller), defaults to ~/work/toolchains.
# Also ensures GNU coreutils (timeout) is available on macOS.
_tcr = os.environ.get("TOOLCHAIN_ROOT", os.path.expanduser("~/work/toolchains"))
_brew = "/opt/homebrew"
for _d in (f"{_tcr}/icarus-12.0/bin", f"{_tcr}/spike-mcu/bin",
           f"{_brew}/opt/coreutils/libexec/gnubin", f"{_brew}/bin"):
    if os.path.isdir(_d) and _d not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = _d + os.pathsep + os.environ.get("PATH", "")
del _tcr, _d, _brew

# Map requirement ID -> gate command (run from ROOT). Each must exit 0 on PASS.
GATES = {
    "A1": ["bash", "tb/run_arch.sh"],
    "A2": ["bash", "tb/run_arch.sh"],  # same script covers both
    "A3": ["bash", "tb/run_reset.sh"],
    "A4": ["bash", "tb/run_trap.sh"],
    "A5": ["bash", "tb/run_irq.sh"],
    "A6": ["bash", "tb/run_memmap.sh"],
    "A7": ["bash", "tb/run_uart_rx.sh"],
    "A8": ["bash", "tb/run_spi.sh"],
    "A9": ["bash", "tb/run_a9_vlt.sh"],
    "B1": ["bash", "tb/run_rtos_vlt.sh", "rtos_regtest", "regtest", "regtest", "500"],
    "B2": ["bash", "tb/run_rtos_vlt.sh", "rtos_queue", "queue", "queue", "2000"],
    "B3": ["bash", "tb/run_rtos_vlt.sh", "rtos_sema", "sema", "sema", "1000"],
    "B4": ["bash", "tb/run_rtos_vlt.sh", "rtos_notify", "notify", "notify", "500"],
    "B5": ["bash", "tb/run_rtos_vlt.sh", "rtos_timer", "timer", "timer", "200"],
    "B6": ["bash", "tb/run_rtos_vlt.sh", "rtos_isr", "isr", "isr", "200", "50000"],
    "B7": ["bash", "tb/run_rtos_vlt.sh", "rtos_blocktim", "blocktim", "blocktim", "2"],
    "C1": ["bash", "tb/run_preempt.sh"],
    "D1": ["bash", "demo/run_demo.sh"],
    "D2": ["bash", "demo/run_demo.sh"],  # self-test verified in D1 UART log
    "F1": ["bash", "synth/run_synth.sh"],
    "F2": ["bash", "synth/run_gate_app.sh"],
    "F3": ["bash", "synth/run_gate_preempt.sh"],
    "G1": ["bash", "tb/run_fault_notick.sh"],
    "G2": ["bash", "tb/run_fault_ctx.sh"],
    "G3": ["bash", "tb/run_fault_uart.sh"],
}

SMOKE = ["A3", "A4", "A6", "A8"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--skip", default="",
                    help="comma-separated requirement IDs to skip (e.g. --skip F1)")
    args = ap.parse_args()

    manifest = yaml.safe_load(open(f"{ROOT}/acceptance/manifest.yaml"))
    reqs = manifest["requirements"]
    print(f"Contract {manifest['contract_version']} status={manifest['status']}: "
          f"{len(reqs)} requirements")

    ids = [r["id"] for r in reqs if r["id"] in GATES]
    if args.smoke:
        ids = [i for i in SMOKE if i in ids]
        print("SMOKE subset:", ids)
    skip = {s.strip() for s in args.skip.split(",") if s.strip()}
    if skip:
        ids = [i for i in ids if i not in skip]
        print("Skipping:", sorted(skip))

    results = {}
    for rid in ids:
        cmd = GATES[rid]
        print(f"\n===== {rid}: {' '.join(cmd)} =====", flush=True)
        try:
            r = subprocess.run(cmd, cwd=ROOT, timeout=8 * 3600,
                               capture_output=True, text=True)
            ok = (r.returncode == 0)
            print(f"{rid}: {'PASS' if ok else 'FAIL'} (exit={r.returncode})")
            if not ok:
                print(r.stdout[-2000:])
                print(r.stderr[-2000:])
            results[rid] = "PASS" if ok else "FAIL"
        except subprocess.TimeoutExpired:
            print(f"{rid}: FAIL (timeout)")
            results[rid] = "FAIL"

    # Requirements without a gate command are reported, never passed.
    for r in reqs:
        if r["id"] not in results:
            results[r["id"]] = "NOT_RUN"
            print(f"{r['id']}: NOT_RUN (no gate command)")

    print("\n===== SUMMARY =====")
    for rid, v in results.items():
        print(f"  {rid}: {v}")
    failed = [k for k, v in results.items() if v != "PASS"]
    if failed:
        print(f"\nRESULT: FAIL ({len(failed)} not passing: {failed})")
        return 1
    print("\nRESULT: ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

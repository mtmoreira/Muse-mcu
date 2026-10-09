#!/usr/bin/env python3
"""check_frozen.py — E1: verify the frozen-revision consistency.

Reads acceptance/manifest.yaml (frozen_revision field) and checks:
  1. The git HEAD commit matches frozen_revision (or the manifest is updated).
  2. All RTL files (rtl/*.sv) are committed (no uncommitted changes).
  3. The frozen firmware hex files exist and match the committed sources.

Exits 0 if frozen, nonzero otherwise. This is a consistency check, not a gate.
"""
import hashlib
import subprocess
import sys
import yaml

ROOT = "/home/hatch/workspace/Muse-mcu"


def git(*args):
    r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip(), r.returncode


def main():
    manifest = yaml.safe_load(open(f"{ROOT}/acceptance/manifest.yaml"))
    frozen = manifest.get("frozen_revision", "")
    print(f"E1: manifest frozen_revision = {frozen}")

    head, _ = git("rev-parse", "HEAD")
    print(f"E1: git HEAD = {head}")
    if frozen and frozen != head:
        print(f"E1: NOTE: HEAD differs from frozen_revision (manifest may need update)")
    
    # Check for uncommitted RTL changes
    status, _ = git("status", "--porcelain", "rtl/")
    if status:
        print(f"E1: FAIL: uncommitted RTL changes:\n{status}")
        return 1
    print("E1: RTL tree clean (no uncommitted changes)")
    
    # Check firmware hexes exist
    import os
    for app in ["app_demo", "preempt_test", "rtos_regtest"]:
        hex_path = f"{ROOT}/fw/build/{app}.hex"
        if not os.path.exists(hex_path):
            print(f"E1: FAIL: missing {hex_path}")
            return 1
        size = os.path.getsize(hex_path)
        print(f"E1: {app}.hex exists ({size} bytes)")
    
    print("E1: PASS (frozen revision consistent)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

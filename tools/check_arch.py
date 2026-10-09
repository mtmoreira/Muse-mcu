#!/usr/bin/env python3
"""check_arch.py — byte-exact compare of DUT vs Spike arch-test signatures.

Reads results/raw/arch/<name>.dut.sig (written by tb/tb_arch.sv) and
results/raw/arch/<name>.spike.sig (written by tools/build_arch.py).

.sig format (both sides, agreed in tb/arch/README.md):
  one signature word per line, `%08x` lowercase hex, no count header.
  (.dut.sig is written by tb/tb_arch.sv; .spike.sig by tools/build_arch.py.)

Prints `ARCH <pass>/<total> PASS`, exits 0 iff all 45 match, nonzero otherwise.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(ROOT, "results", "raw", "arch")
ARCH_TEST = os.path.join(ROOT, "third_party", "riscv_arch_test")


def read_sig(path):
    with open(path) as f:
        words = [ln.strip() for ln in f if ln.strip()]
    if not words:
        raise ValueError("empty file")
    for w in words:
        if len(w) != 8 or any(c not in "0123456789abcdef" for c in w):
            raise ValueError("bad word %r" % w)
    return words


def main():
    names = []
    for sub in ("I", "Zicsr"):
        d = os.path.join(ARCH_TEST, sub)
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".S"):
                names.append(fn[:-2])

    passed = 0
    failures = []
    for name in names:
        dut = os.path.join(RESULTS, name + ".dut.sig")
        spk = os.path.join(RESULTS, name + ".spike.sig")
        try:
            if not os.path.exists(dut):
                raise ValueError("missing .dut.sig (DUT side not run?)")
            if not os.path.exists(spk):
                raise ValueError("missing .spike.sig (golden not run?)")
            dw, sw = read_sig(dut), read_sig(spk)
            if dw == sw:
                passed += 1
            else:
                n = next((i for i, (a, b) in enumerate(zip(dw, sw)) if a != b),
                         min(len(dw), len(sw)))
                failures.append("%s: mismatch at word %d (dut=%s spike=%s, %d/%d words)" %
                                (name, n,
                                 dw[n] if n < len(dw) else "-",
                                 sw[n] if n < len(sw) else "-",
                                 len(dw), len(sw)))
        except ValueError as e:
            failures.append("%s: %s" % (name, e))

    for f in failures:
        print("FAIL", f)
    print("ARCH %d/%d PASS" % (passed, len(names)))
    return 0 if (passed == len(names)) else 1


if __name__ == "__main__":
    sys.exit(main())

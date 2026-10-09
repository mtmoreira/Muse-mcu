#!/usr/bin/env python3
"""build_arch.py — build + golden-run the 45 riscv-arch-test cases.

For each test in third_party/riscv_arch_test/{I,Zicsr}/*.S:
  1. Build the DUT ELF  (tb/arch/riscv_arch_test.h shim)  -> fw/build/arch/<name>.dut.elf
  2. Convert it to hex for tb/run_arch.sh                  -> fw/build/arch/<name>.hex
  3. Build the Spike ELF (tb/arch/riscv_arch_test_spike.h shim) -> fw/build/arch/<name>.spike.elf
  4. Run the Spike ELF under Spike, capture the HTIF-console hex dump,
     write results/raw/arch/<name>.spike.sig

The DUT ELFs are consumed by tb/tb_arch.sv (testbench worker), which writes
results/raw/arch/<name>.dut.sig; tools/check_arch.py compares the pair.

Both ELFs use tb/arch/arch.ld (ROM 0x0 / RAM 0x10000, _start at 0x0) and
-mno-relax so the test code lands at identical addresses in both builds
(required: jal/jalr/auipc capture PC values into the signature).

Spike invocation:
  spike --isa=rv32i_zicsr -m0x0:0x40000 <elf>
The -m maps 256 KiB at 0x0 (ROM image + RAM). This needs a Spike whose
debug module / boot ROM do NOT sit at [0x0,0x1000)/0x1000; use the
spike-mcu build (see tb/arch/README.md). SPIKE_BIN env var overrides.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TB_ARCH = os.path.join(ROOT, "tb", "arch")
ARCH_TEST = os.path.join(ROOT, "third_party", "riscv_arch_test")
BUILD = os.path.join(ROOT, "fw", "build", "arch")
RESULTS = os.path.join(ROOT, "results", "raw", "arch")

TOOLCHAIN = os.path.expanduser(
    "~/workspace/building-ai-computer/toolchains/riscv/"
    "xpack-riscv-none-elf-gcc-15.2.0-1/bin")
CC = os.path.join(TOOLCHAIN, "riscv-none-elf-gcc")
SPIKE = os.environ.get("SPIKE_BIN",
        os.path.expanduser("~/workspace/toolchains/spike-mcu/bin/spike"))

HEXLINE = re.compile(r"^[0-9a-f]{8}$")

CFLAGS = [
    "-march=rv32i_zicsr", "-mabi=ilp32", "-mcmodel=medany", "-O2",
    "-ffreestanding", "-nostdlib", "-mno-relax",
    "-T", os.path.join(TB_ARCH, "arch.ld"),
]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# Tests whose .text overflows the 64 KiB ROM (I-jal-00: ~112 KiB from
# .p2align). They use tb/arch/arch_jal.ld (.text spans ROM+SRAM) and a
# moved signature base. sigbase.json records the per-test SIGBASE for the
# testbench (default 0x00018000).
BIG_TEXT = {
    "I-jal-00": {"ld": "arch_jal.ld", "sigbase": 0x00024000},
}
DEFAULT_SIGBASE = 0x00018000


def build_one(test_src, name):
    """Build DUT + Spike ELFs. Returns (dut_elf, spike_elf) or raises."""
    dut_elf = os.path.join(BUILD, name + ".dut.elf")
    spike_elf = os.path.join(BUILD, name + ".spike.elf")
    big = BIG_TEXT.get(name, {})
    ld = os.path.join(TB_ARCH, big.get("ld", "arch.ld"))
    extra = []
    if "sigbase" in big:
        extra = ["-DSIGBASE_ADDR=0x%08x" % big["sigbase"]]
    cflags = [a for a in CFLAGS
              if a != "-T" and a != os.path.join(TB_ARCH, "arch.ld")]
    cflags += ["-T", ld]

    # DUT build: "riscv_arch_test.h" resolves to tb/arch/riscv_arch_test.h
    r = run([CC] + cflags + extra + ["-I", TB_ARCH, "-o", dut_elf, test_src])
    if r.returncode != 0:
        raise RuntimeError("DUT build failed for %s:\n%s" % (name, r.stderr))

    # Spike build: shadow "riscv_arch_test.h" with the spike shim
    inc_spike = os.path.join(BUILD, "inc_spike")
    os.makedirs(inc_spike, exist_ok=True)
    with open(os.path.join(inc_spike, "riscv_arch_test.h"), "w") as f:
        f.write('#include "riscv_arch_test_spike.h"\n')
    r = run([CC] + cflags + extra + ["-I", inc_spike, "-I", TB_ARCH,
                                     "-o", spike_elf, test_src])
    if r.returncode != 0:
        raise RuntimeError("Spike build failed for %s:\n%s" % (name, r.stderr))
    return dut_elf, spike_elf


def spike_golden(name, spike_elf, timeout=120):
    """Run the Spike ELF, capture the +signature= dump -> results/raw/arch/<name>.spike.sig.

    The Spike shim (tb/arch/riscv_arch_test_spike.h) ends the test with an
    HTIF shutdown (tohost = 1); Spike's +signature= dump (keyed off the
    begin_signature/end_signature symbols, +signature-granularity=4 so each
    line is one 32-bit word) captures the signature region at exit. The
    first dumped word is the word count N; the next N words are the
    signature. This replaces the earlier HTIF-console approach, which hung:
    this Spike build never acks console writes via fromhost.

    .spike.sig format matches the tb's .dut.sig format (tb/arch/README.md):
    N signature words, one `%08x` per line, no count header.
    """
    sig_path = os.path.join(RESULTS, name + ".spike.sig")
    raw_path = os.path.join(BUILD, name + ".spike.raw")
    try:
        r = subprocess.run(
            [SPIKE, "--isa=rv32i_zicsr", "-m0x0:0x40000",
             "+signature=" + raw_path, "+signature-granularity=4", spike_elf],
            capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, "spike timeout after %ds" % timeout
    if r.returncode != 0:
        return False, "spike exit=%d stderr=%s" % (r.returncode, r.stderr.strip()[:300])
    try:
        with open(raw_path) as f:
            words = [ln.strip() for ln in f if HEXLINE.match(ln.strip())]
    except OSError as e:
        return False, "no signature dump: %s" % e
    finally:
        if os.path.exists(raw_path):
            os.remove(raw_path)
    if not words:
        return False, "empty signature dump"
    n = int(words[0], 16)
    if n < 1 or n > 4096 or 1 + n > len(words):
        return False, "bad count %d (dumped %d words)" % (n, len(words))
    with open(sig_path, "w") as f:
        for w in words[1:1 + n]:
            f.write(w + "\n")
    return True, "%d words" % n


def dut_hex(name, dut_elf):
    """Convert the DUT ELF to a $readmemh hex for tb/run_arch.sh.

    The runner globs `*.hex` in fw/build/arch/, so the DUT hex is named
    `<name>.hex` (the `.dut.elf`/`.spike.elf` names are kept distinct).

    The .hex is a FLAT 32-bit word image from byte 0x0 (tb/arch/README.md):
    words [0:16384) are the ROM image, words [16384:] are the SRAM-resident
    part (.arch_data at 0x10000, .signature, .tohost); the testbench splits
    them into dut.rom.mem / dut.ram.mem. If the binary is shorter than
    16384 words, the ROM part is padded with jal x0,0 so no ROM word stays X.
    (tools/elf_to_hex.py is a firmware-ROM tool capped at 16384 words and
    drops the SRAM part, so it cannot be used here.)
    """
    import struct
    hex_path = os.path.join(BUILD, name + ".hex")
    bin_path = os.path.join(BUILD, name + ".dut.bin")
    r = run([os.path.join(TOOLCHAIN, "riscv-none-elf-objcopy"),
             "-O", "binary", dut_elf, bin_path])
    if r.returncode != 0:
        raise RuntimeError("objcopy failed for %s" % name)
    with open(bin_path, "rb") as f:
        data = f.read()
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)
    words = list(w for (w,) in struct.iter_unpack("<I", data))
    ROM_WORDS = 16384
    if len(words) < ROM_WORDS:
        words += [0x0000006F] * (ROM_WORDS - len(words))  # jal x0,0
    with open(hex_path, "w") as f:
        for w in words:
            f.write("%08x\n" % w)
    os.remove(bin_path)


def list_tests(names=None):
    """Enumerate (src, name) for third_party/riscv_arch_test/{I,Zicsr}/*.S."""
    tests = []
    for sub in ("I", "Zicsr"):
        d = os.path.join(ARCH_TEST, sub)
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".S"):
                name = fn[:-2]
                if not names or name in names:
                    tests.append((os.path.join(d, fn), name))
    return tests


def main():
    tests = list_tests(sys.argv[1:] or None)
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(RESULTS, exist_ok=True)

    # Per-test SIGBASE manifest for the testbench (tb/tb_arch.sv).
    import json
    sigbase = {name: "0x%08x" % BIG_TEXT.get(name, {}).get("sigbase", DEFAULT_SIGBASE)
               for _, name in tests}
    with open(os.path.join(BUILD, "sigbase.json"), "w") as f:
        json.dump(sigbase, f, indent=1, sort_keys=True)

    built = failed = 0
    for src, name in tests:
        # Guard: fw/build/arch was observed to vanish mid-run once (another
        # worker's clean step?); recreate per test so it can't kill the batch.
        os.makedirs(BUILD, exist_ok=True)
        os.makedirs(RESULTS, exist_ok=True)
        try:
            dut_elf, spike_elf = build_one(src, name)
            dut_hex(name, dut_elf)
            ok, msg = spike_golden(name, spike_elf)
        except RuntimeError as e:
            print("FAIL %-28s %s" % (name, e))
            failed += 1
            continue
        if ok:
            built += 1
            print("ok   %-28s spike golden: %s" % (name, msg))
        else:
            failed += 1
            print("FAIL %-28s %s" % (name, msg))
    print("built+golden: %d/%d, failed: %d" % (built, len(tests), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

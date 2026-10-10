#!/bin/bash
# run_arch.sh -- A1/A2 arch-test runner.
# Loops over all *.hex in <hexdir> (default fw/build/arch), captures each
# test's signature with tb_arch, then runs tools/check_arch.py (firmware
# Icarus location (robust to VM replacement): prefer /usr/bin, fall back to local toolchain copy.
IVL_BIN=""
if command -v iverilog >/dev/null 2>&1; then
  IVL_BIN="$(dirname "$(command -v iverilog)")"
else
  for _d in /usr/bin "$HOME/workspace/building-ai-computer/toolchains/icarus/deb/usr/bin"; do
    if [ -x "$_d/iverilog" ]; then IVL_BIN="$_d"; break; fi
  done
fi
[ -n "$IVL_BIN" ] || { echo "no iverilog found (install icarus-verilog or set PATH)"; exit 1; }
MMCU="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$MMCU/tb/build"
HEXDIR="${1:-$MMCU/fw/build/arch}"
SIGDIR="$MMCU/results/raw/arch"
LOGDIR="$MMCU/tb/logs"
mkdir -p "$SIGDIR" "$LOGDIR"

$IVL_BIN/iverilog -g2012 -o "$MMCU/tb/build/sim_arch.vvp" \
  "$MMCU/tb/tb_arch.sv" "$MMCU"/rtl/*.sv

mapfile -t HEXES < <(ls "$HEXDIR"/*.hex 2>/dev/null || true)
if [ ${#HEXES[@]} -eq 0 ]; then
  echo "ARCH: no .hex files in $HEXDIR"
  exit 2
fi

# Per-test signature word index from fw/build/arch/sigbase.json
# (default 0x6000 = byte 0x00018000; I-jal-00 is 0x9000 = 0x00024000).
sigwidx() {
  python3 -c "import json,sys; print('%x' % (int(json.load(open('$MMCU/fw/build/arch/sigbase.json')).get(sys.argv[1],'0x00018000'),16)>>2))" "$1"
}

pass=0; fail=0
for hx in "${HEXES[@]}"; do
  name="$(basename "$hx" .hex)"
  sig="$SIGDIR/$name.dut.sig"
  log="$LOGDIR/run_arch_$name.log"
  timeout 600 $IVL_BIN/vvp "$MMCU/tb/build/sim_arch.vvp" "+hex=$hx" "+name=$name" \
    "+sigfile=$sig" "+sigbase=$(sigwidx "$name")" > "$log" 2>&1
  ec=$?
  echo "exit=$ec" >> "$log"
  if [ $ec -eq 0 ] && grep -q "TB_ARCH $name: PASS" "$log"; then
    echo "ARCH $name: TB PASS"; pass=$((pass+1))
  else
    echo "ARCH $name: TB FAIL (exit=$ec) -- see $log"; fail=$((fail+1))
  fi
done
echo "ARCH tb-level: $pass pass / $fail fail / $((pass+fail)) total"

if [ $fail -ne 0 ]; then exit 1; fi
if [ ! -x "$MMCU/tools/check_arch.py" ] && [ ! -f "$MMCU/tools/check_arch.py" ]; then
  echo "ARCH: tools/check_arch.py not present (firmware worker pending); golden compare BLOCKED"
  exit 2
fi
python3 "$MMCU/tools/check_arch.py" --sigdir "$SIGDIR" 2>&1 | tee "$LOGDIR/check_arch.log"
if grep -q "ARCH 45/45 PASS" "$LOGDIR/check_arch.log"; then
  echo "ARCH: ALL 45/45 PASS"
  exit 0
else
  echo "ARCH: golden comparison did not report 45/45 PASS"
  exit 1
fi

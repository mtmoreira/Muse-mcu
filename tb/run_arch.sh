#!/bin/bash
# run_arch.sh -- A1/A2 arch-test runner.
# Loops over all *.hex in <hexdir> (default fw/build/arch), captures each
# test's signature with tb_arch, then runs tools/check_arch.py (firmware
# Icarus location (robust to VM replacement): prefer /usr/bin, fall back to local toolchain copy.
IVL_BIN=""
for _d in /usr/bin "$HOME/workspace/building-ai-computer/toolchains/icarus/deb/usr/bin"; do
  if [ -x "$_d/iverilog" ]; then IVL_BIN="$_d"; break; fi
done
[ -n "$IVL_BIN" ] || { echo "no iverilog found"; exit 1; }
MMCU="$HOME/workspace/Muse-mcu"
HEXDIR="${1:-$MMCU/fw/build/arch}"
SIGDIR="$MMCU/results/raw/arch"
mkdir -p "$SIGDIR"

$IVL_BIN/iverilog -g2012 -o "$MMCU/tb/build/sim_arch.vvp" \
  "$MMCU/tb/tb_arch.sv" "$MMCU"/rtl/*.sv

mapfile -t HEXES < <(ls "$HEXDIR"/*.hex 2>/dev/null || true)
if [ ${#HEXES[@]} -eq 0 ]; then
  echo "ARCH: no .hex files in $HEXDIR"
  exit 2
fi

pass=0; fail=0
for hx in "${HEXES[@]}"; do
  name="$(basename "$hx" .hex)"
  sig="$SIGDIR/$name.dut.sig"
  log="$MMCU/tb/build/run_arch_$name.log"
  timeout 600 $IVL_BIN/vvp "$MMCU/tb/build/sim_arch.vvp" "+hex=$hx" "+name=$name" \
    "+sigfile=$sig" > "$log" 2>&1
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
python3 "$MMCU/tools/check_arch.py" --sigdir "$SIGDIR" 2>&1 | tee "$MMCU/tb/build/check_arch.log"
if grep -q "ARCH 45/45 PASS" "$MMCU/tb/build/check_arch.log"; then
  echo "ARCH: ALL 45/45 PASS"
  exit 0
else
  echo "ARCH: golden comparison did not report 45/45 PASS"
  exit 1
fi

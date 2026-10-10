#!/bin/bash
# tb_reset runner (A3): 3 seeded runs, N in {1,8,100}. Exits nonzero on failure.
set -uo pipefail
MMCU="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$MMCU/tb/build"
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
$IVL_BIN/iverilog -g2012 -o "$MMCU/tb/build/sim_reset.vvp" \
  "$MMCU/tb/tb_reset.sv" "$MMCU"/rtl/*.sv
overall=0
for seed in 1 2 3; do
  log="$MMCU/tb/build/run_reset_s$seed.log"
  timeout 600 $IVL_BIN/vvp "$MMCU/tb/build/sim_reset.vvp" \
    "+hex=$MMCU/tb/build/reset.hex" "+seed=$seed" > "$log" 2>&1
  ec=$?
  echo "exit=$ec" >> "$log"
  if [ $ec -ne 0 ] || ! grep -q "TB_RESET: ALL PASS" "$log"; then
    echo "TB_RESET seed=$seed FAILED (exit=$ec) -- see $log"; overall=1
  else
    echo "TB_RESET seed=$seed PASS"
  fi
done
exit $overall

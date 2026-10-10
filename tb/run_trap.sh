#!/bin/bash
# tb_trap runner (A4): 8 directed trap cases. Exits nonzero on failure.
set -uo pipefail
MMCU="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$MMCU/tb/build"
# Icarus location (robust to VM replacement): prefer /usr/bin, fall back to local toolchain copy.
IVL_BIN=""
if command -v iverilog >/dev/null 2>&1; then
  IVL_BIN="$(dirname "$(command -v iverilog)")"
else
  for _d in /usr/bin "${TOOLCHAIN_ROOT:-$HOME/work/toolchains}/icarus-12.0/bin"; do
    if [ -x "$_d/iverilog" ]; then IVL_BIN="$_d"; break; fi
  done
fi
[ -n "$IVL_BIN" ] || { echo "no iverilog found (install icarus-verilog or set PATH)"; exit 1; }
$IVL_BIN/iverilog -g2012 -o "$MMCU/tb/build/sim_trap.vvp" \
  "$MMCU/tb/tb_trap.sv" "$MMCU"/rtl/*.sv
log="$MMCU/tb/build/run_trap.log"
timeout 600 $IVL_BIN/vvp "$MMCU/tb/build/sim_trap.vvp" \
  "+hex=$MMCU/tb/build/trap.hex" > "$log" 2>&1
ec=$?
echo "exit=$ec" >> "$log"
if [ $ec -ne 0 ] || ! grep -q "TB_TRAP: ALL PASS" "$log"; then
  echo "TB_TRAP FAILED (exit=$ec) -- see $log"; exit 1
fi
echo "TB_TRAP PASS"

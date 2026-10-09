#!/bin/bash
# tb_memmap runner (A6): 40 directed accesses. Exits nonzero on failure.
set -uo pipefail
MMCU="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Icarus location (robust to VM replacement): prefer /usr/bin, fall back to local toolchain copy.
IVL_BIN=""
for _d in /usr/bin "$HOME/workspace/building-ai-computer/toolchains/icarus/deb/usr/bin"; do
  if [ -x "$_d/iverilog" ]; then IVL_BIN="$_d"; break; fi
done
[ -n "$IVL_BIN" ] || { echo "no iverilog found"; exit 1; }
$IVL_BIN/iverilog -g2012 -o "$MMCU/tb/build/sim_memmap.vvp" \
  "$MMCU/tb/tb_memmap.sv" "$MMCU"/rtl/*.sv
log="$MMCU/tb/build/run_memmap.log"
timeout 600 $IVL_BIN/vvp "$MMCU/tb/build/sim_memmap.vvp" \
  "+hex=$MMCU/tb/build/memmap.hex" > "$log" 2>&1
ec=$?
echo "exit=$ec" >> "$log"
if [ $ec -ne 0 ] || ! grep -q "TB_MEMMAP: ALL PASS" "$log"; then
  echo "TB_MEMMAP FAILED (exit=$ec) -- see $log"; exit 1
fi
echo "TB_MEMMAP PASS"

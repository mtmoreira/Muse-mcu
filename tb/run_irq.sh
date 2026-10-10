#!/bin/bash
# tb_irq runner (A5): timer + 4 external interrupt sources. Exits nonzero on failure.
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
$IVL_BIN/iverilog -g2012 -o "$MMCU/tb/build/sim_irq.vvp" \
  "$MMCU/tb/tb_irq.sv" "$MMCU"/rtl/*.sv
log="$MMCU/tb/build/run_irq.log"
timeout 900 $IVL_BIN/vvp "$MMCU/tb/build/sim_irq.vvp" \
  "+hex=$MMCU/tb/build/irq.hex" > "$log" 2>&1
ec=$?
echo "exit=$ec" >> "$log"
if [ $ec -ne 0 ] || ! grep -q "TB_IRQ: ALL PASS" "$log"; then
  echo "TB_IRQ FAILED (exit=$ec) -- see $log"; exit 1
fi
echo "TB_IRQ PASS"

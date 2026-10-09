#!/bin/bash
# tb/run_a9_vlt.sh — A9 via Verilator RTL harness (not Icarus).
#
# Backend: Verilator 5.032 (recorded per manifest "per-run backend recorded").
# Icarus caps at ~10-12M cycles; A9 needs 50M+ (1000 ticks at 50000 cycles).
# Same RTL (tb/rtl_vlt/sim_top_rtl.sv wraps rtl/mcu_top), same firmware
# (fw/build/timer_gpio_test.hex), same pass criteria as tb/tb_timer_gpio.sv:
# 1000/1000 tick periods at 50000+-1 cycles (architectural MTI entries),
# 1000 MARK tick lines (sequence 1..1000), 16 MARK gpio lines, firmware
# prints "TEST timer_gpio PASS".
#
# Verdict recorded in results/a9_gate.json; UART/trace log in results/raw/.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VLT="${VLT_BIN:-$(command -v verilator)}"
[ -n "$VLT" ] || VLT=/home/hatch/workspace/tools/verilator-src/bin/verilator
[ -x "$VLT" ] || { echo "verilator not found (set VLT_BIN)"; exit 1; }
BIN=build/rtl_vlt/vobj_a9v/Vsim_top_rtl
HEX=fw/build/timer_gpio_test.hex
LOG=tb/logs/a9_verilator.log
TIMEOUT_S="${TIMEOUT_S:-1800}"

[ -f "$HEX" ] || { echo "A9_VLT: FAIL: missing $HEX (build firmware first)"; exit 2; }

if [ ! -x "$BIN" ]; then
  echo "A9_VLT: building Verilator RTL harness"
  mkdir -p build/rtl_vlt/vobj_a9v
  "$VLT" --cc --top-module sim_top_rtl --Mdir build/rtl_vlt/vobj_a9v \
    --exe tb/rtl_vlt/tb_a9.cpp tb/rtl_vlt/sim_top_rtl.sv rtl/*.sv || exit 1
  make -C build/rtl_vlt/vobj_a9v -f Vsim_top_rtl.mk -j4 || exit 1
fi

echo "A9_VLT: running (verilator backend, RTL)"
timeout "$TIMEOUT_S" "$BIN" "+hex=$HEX" > "$LOG" 2>&1
rc=$?
echo "A9_VLT: harness exit code = $rc"
[ $rc -eq 0 ] || { echo "A9_VLT: FAIL: nonzero exit; see $LOG"; exit 1; }
grep -q "A9: ALL PASS" "$LOG" || { echo "A9_VLT: FAIL: verdict missing; see $LOG"; exit 1; }
echo "A9_VLT: PASS"

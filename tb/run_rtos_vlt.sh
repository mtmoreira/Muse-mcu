#!/bin/bash
# tb/run_rtos_vlt.sh — FreeRTOS gate via Verilator RTL harness (not Icarus).
# Usage: run_rtos_vlt.sh <app> <testname> <markname> <minmarks> [irqperiod] [timeout_cycles]
#
# Backend: Verilator 5.032 (recorded per manifest "per-run backend recorded").
# Used for gates whose cycle budget exceeds Icarus throughput (B5: ~27M cycles).
# Same RTL, same firmware, same marker protocol as tb/tb_rtos.sv:
# no "TEST FAIL" line, a "TEST <name> PASS" line, >= minmarks "MARK <mark> " lines.
# Exits 0 only if the harness prints "RTOS_VLT <testname>: ALL PASS".
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$1"; TEST="$2"; MARK="$3"; MINMARKS="$4"
IRQPERIOD="${5:-0}"; TIMEOUT="${6:-60000000}"
VLT=/home/hatch/workspace/tools/verilator-src/bin/verilator
BIN=build/rtl_vlt/vobj_rtos/Vsim_top_rtl
HEX="fw/build/$APP.hex"
LOG="tb/logs/run_rtos_vlt_$APP.log"
TIMEOUT_S="${TIMEOUT_S:-1800}"

[ -f "$HEX" ] || { echo "RTOS_VLT: FAIL: missing $HEX (build firmware first)"; exit 2; }

if [ ! -x "$BIN" ]; then
  echo "RTOS_VLT: building Verilator RTL harness"
  mkdir -p build/rtl_vlt/vobj_rtos
  "$VLT" --cc --top-module sim_top_rtl --Mdir build/rtl_vlt/vobj_rtos \
    --exe tb/rtl_vlt/tb_rtos_vlt.cpp tb/rtl_vlt/sim_top_rtl.sv rtl/*.sv || exit 1
  make -C build/rtl_vlt/vobj_rtos -f Vsim_top_rtl.mk -j4 || exit 1
fi

echo "RTOS_VLT: running $APP (verilator backend, RTL)"
timeout "$TIMEOUT_S" "$BIN" "+hex=$HEX" "+test=$TEST" "+mark=$MARK" \
  "+minmarks=$MINMARKS" "+irqperiod=$IRQPERIOD" "+timeout=$TIMEOUT" > "$LOG" 2>&1
rc=$?
echo "RTOS_VLT: harness exit code = $rc"
[ $rc -eq 0 ] || { echo "RTOS_VLT: FAIL: nonzero exit for $APP; see $LOG"; exit 1; }
grep -q "RTOS_VLT $TEST: ALL PASS" "$LOG" || { echo "RTOS_VLT: FAIL: no ALL PASS for $APP; see $LOG"; exit 1; }
echo "RTOS_VLT: PASS: $APP ($TEST)"

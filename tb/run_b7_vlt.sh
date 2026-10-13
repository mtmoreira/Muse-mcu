#!/bin/bash
# tb/run_b7_vlt.sh — B7 gate via Verilator RTL harness.
#
# Manifest B7 verdict (contract v1.0.1): ">=2 timeout events within 60M
# cycles, 0 errors (no FAIL lines); event count from firmware MARK lines
# observed by testbench". The firmware's own "TEST blocktim PASS" prints
# only at 200 events (the unmodified upstream demo yields ~48 events per
# 7950 ticks, so 200 events need ~1.66B cycles) and can never appear in
# the 60M budget; the gate verdict therefore comes from the MARK blocktim
# <count> values in the UART stream, exactly as the 2026-10-09 evidence
# run did (results/b7_gate.json: counts reached 4, verdict PASS).
#
# Exits 0 only if: no FAIL text in the UART log AND max MARK blocktim
# count >= 2 within 60M cycles.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VLT="${VLT_BIN:-$(command -v verilator)}"
[ -n "$VLT" ] || VLT=/home/hatch/workspace/tools/verilator-src/bin/verilator
[ -x "$VLT" ] || { echo "verilator not found (set VLT_BIN)"; exit 1; }
BIN=build/rtl_vlt/vobj_rtos/Vsim_top_rtl
HEX="fw/build/rtos_blocktim.hex"
UARTLOG="results/raw/b7_uart.log"
mkdir -p results/raw tb/logs

[ -f "$HEX" ] || { echo "B7: FAIL: missing $HEX (build firmware first)"; exit 2; }

if [ ! -x "$BIN" ]; then
  echo "B7: building Verilator RTL harness"
  mkdir -p build/rtl_vlt/vobj_rtos
  "$VLT" --cc --top-module sim_top_rtl --Mdir build/rtl_vlt/vobj_rtos \
    --exe tb/rtl_vlt/tb_rtos_vlt.cpp tb/rtl_vlt/sim_top_rtl.sv rtl/*.sv || exit 1
  make -C build/rtl_vlt/vobj_rtos -f Vsim_top_rtl.mk -j4 || exit 1
fi

echo "B7: running rtos_blocktim (verilator backend, RTL, 60M cycles)"
timeout "${TIMEOUT_S:-1800}" "$BIN" "+hex=$HEX" "+test=blocktim" "+mark=blocktim" \
  "+minmarks=1" "+timeout=60000000" "+uartlog=$UARTLOG" > tb/logs/run_b7_vlt.log 2>&1
# Harness exit code is expected nonzero (watchdog timeout; the firmware
# PASS line is unreachable by design). The verdict is evaluated below.

if grep -q "FAIL" "$UARTLOG"; then
  echo "B7: FAIL: FAIL line in UART log; see $UARTLOG"
  exit 1
fi
MAXCOUNT="$(grep -o 'MARK blocktim [0-9]*' "$UARTLOG" | awk '{print $3}' | sort -n | tail -1)"
MAXCOUNT="${MAXCOUNT:-0}"
echo "B7: max MARK blocktim count = $MAXCOUNT (need >= 2)"
if [ "$MAXCOUNT" -ge 2 ]; then
  echo "B7: PASS: $MAXCOUNT timeout events within 60M cycles, 0 errors"
  exit 0
fi
echo "B7: FAIL: only $MAXCOUNT timeout events within 60M cycles"
exit 1

#!/bin/bash
# run_rtos.sh — build + run one FreeRTOS gate.
# Usage: run_rtos.sh <app> <testname> <markname> <minmarks> [irqperiod] [timeout_cycles]
# Exits 0 only if the tb prints "TB_RTOS <testname>: ALL PASS".
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"; TEST="$2"; MARK="$3"; MINMARKS="$4"
IRQPERIOD="${5:-0}"; TIMEOUT="${6:-60000000}"
HEX="$REPO/fw/build/$APP.hex"
LOG="$REPO/tb/build/run_rtos_$APP.log"
mkdir -p "$REPO/tb/build"

if [ ! -f "$HEX" ]; then echo "RUNNER: FAIL: missing $HEX (build the firmware first)"; exit 2; fi

{
echo "=== run_rtos $APP test=$TEST mark=$MARK minmarks=$MINMARKS irqperiod=$IRQPERIOD ==="
iverilog -g2012 -o "$REPO/tb/build/tb_rtos.vvp" \
  "$REPO/tb/tb_rtos.sv" "$REPO/tb/uart_sink.sv" "$REPO"/rtl/*.sv || exit 1
vvp "$REPO/tb/build/tb_rtos.vvp" \
  "+hex=$HEX" "+test=$TEST" "+mark=$MARK" "+minmarks=$MINMARKS" \
  "+irqperiod=$IRQPERIOD" "+timeout=$TIMEOUT"
} > "$LOG" 2>&1
ec=$?
if [ $ec -ne 0 ]; then echo "RUNNER: FAIL: tb_rtos nonzero exit ($ec) for $APP; see $LOG"; exit 1; fi
if grep -q "TB_RTOS $TEST: ALL PASS" "$LOG"; then
  echo "RUNNER: PASS: $APP ($TEST)"
  exit 0
else
  echo "RUNNER: FAIL: no ALL PASS verdict for $APP ($TEST); see $LOG"; exit 1
fi

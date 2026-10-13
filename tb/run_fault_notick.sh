#!/bin/bash
# run_fault_notick.sh — build & run tb_fault_notick (G1).
# Env overrides: FW_HEX (default fw/build/rtos_queue.hex),
#   FAULT_AT_TICK (default 100), TIMEOUT_S (default 1800).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/rtos_queue.hex}"
FAULT_AT_TICK="${FAULT_AT_TICK:-100}"  # evidence run used 100; 1000 ticks = ~50M cycles exceeds the tb 30M-cycle watchdog
TIMEOUT_S="${TIMEOUT_S:-1800}"
OUT=build/tb_out
mkdir -p "$OUT" results/raw
[ -f "$FW_HEX" ] || { echo "RUNNER: FAIL: firmware hex not found: $FW_HEX"; exit 1; }
echo "RUNNER: iverilog tb_fault_notick"
iverilog -g2012 -o "$OUT/tb_fault_notick.vvp" tb/tb_fault_notick.sv tb/uart_sink.sv rtl/*.sv || exit 1
echo "RUNNER: vvp tb_fault_notick"
timeout "$TIMEOUT_S" vvp "$OUT/tb_fault_notick.vvp" "+hex=$FW_HEX" \
  "+fault_at_tick=$FAULT_AT_TICK" 2>&1 | tee results/raw/fault_notick.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_fault_notick nonzero exit"; exit 1; }
grep -q "TB_FAULT_NOTICK: ALL PASS" results/raw/fault_notick.log || { echo "RUNNER: FAIL: verdict missing"; exit 1; }
grep -q "FAULT G1: ACTIVATED" results/raw/fault_notick.log || { echo "RUNNER: FAIL: activation not logged"; exit 1; }
echo "RUNNER: PASS"

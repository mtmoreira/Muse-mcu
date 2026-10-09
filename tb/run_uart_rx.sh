#!/bin/bash
# run_uart_rx.sh — build & run tb_uart_rx (A7).
# Env overrides: FW_HEX (default fw/build/uart_rx_test.hex), TIMEOUT_S (default 900).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/uart_rx_test.hex}"
TIMEOUT_S="${TIMEOUT_S:-900}"
OUT=build/tb_out
mkdir -p "$OUT" results/raw
if [ ! -f "$FW_HEX" ]; then echo "RUNNER: FAIL: firmware hex not found: $FW_HEX"; exit 1; fi
echo "RUNNER: iverilog tb_uart_rx"
iverilog -g2012 -o "$OUT/tb_uart_rx.vvp" tb/tb_uart_rx.sv tb/uart_sink.sv rtl/*.sv || exit 1
echo "RUNNER: vvp tb_uart_rx (+hex=$FW_HEX)"
timeout "$TIMEOUT_S" vvp "$OUT/tb_uart_rx.vvp" "+hex=$FW_HEX" 2>&1 | tee results/raw/uart_rx.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_uart_rx nonzero exit"; exit 1; }
grep -q "TB_UART_RX: ALL PASS" results/raw/uart_rx.log || { echo "RUNNER: FAIL: verdict missing"; exit 1; }
echo "RUNNER: PASS"

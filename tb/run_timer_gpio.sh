#!/bin/bash
# run_timer_gpio.sh — build & run tb_timer_gpio (A9).
# Env overrides: FW_HEX (default fw/build/timer_gpio_test.hex), TIMEOUT_S (default 1200).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/timer_gpio_test.hex}"
TIMEOUT_S="${TIMEOUT_S:-1200}"
EXPECT_TICKS="${EXPECT_TICKS:-1000}"
OUT=build/tb_out
mkdir -p "$OUT" results/raw
[ -f "$FW_HEX" ] || { echo "RUNNER: FAIL: firmware hex not found: $FW_HEX"; exit 1; }
echo "RUNNER: iverilog tb_timer_gpio"
iverilog -g2012 -o "$OUT/tb_timer_gpio.vvp" tb/tb_timer_gpio.sv tb/uart_sink.sv rtl/*.sv || exit 1
echo "RUNNER: vvp tb_timer_gpio"
timeout "$TIMEOUT_S" vvp "$OUT/tb_timer_gpio.vvp" "+hex=$FW_HEX" "+expect_ticks=$EXPECT_TICKS" 2>&1 | tee results/raw/timer_gpio.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_timer_gpio nonzero exit"; exit 1; }
grep -q "TB_TIMER_GPIO: ALL PASS" results/raw/timer_gpio.log || { echo "RUNNER: FAIL: verdict missing"; exit 1; }
echo "RUNNER: PASS"

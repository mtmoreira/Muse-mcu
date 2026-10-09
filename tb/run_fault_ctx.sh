#!/bin/bash
# run_fault_ctx.sh — build & run tb_fault_ctx (G2).
# Env overrides: FW_HEX (default fw/build/rtos_regtest.hex), TIMEOUT_S (default 1200).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/rtos_regtest.hex}"
TIMEOUT_S="${TIMEOUT_S:-1200}"
OUT=build/tb_out
mkdir -p "$OUT" results/raw
[ -f "$FW_HEX" ] || { echo "RUNNER: FAIL: firmware hex not found: $FW_HEX"; exit 1; }
echo "RUNNER: iverilog tb_fault_ctx"
iverilog -g2012 -o "$OUT/tb_fault_ctx.vvp" tb/tb_fault_ctx.sv tb/uart_sink.sv rtl/*.sv || exit 1
echo "RUNNER: vvp tb_fault_ctx"
timeout "$TIMEOUT_S" vvp "$OUT/tb_fault_ctx.vvp" "+hex=$FW_HEX" 2>&1 | tee results/raw/fault_ctx.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_fault_ctx nonzero exit"; exit 1; }
grep -q "TB_FAULT_CTX: ALL PASS" results/raw/fault_ctx.log || { echo "RUNNER: FAIL: verdict missing"; exit 1; }
grep -q "FAULT G2: injected at cycle" results/raw/fault_ctx.log || { echo "RUNNER: FAIL: injection not logged"; exit 1; }
echo "RUNNER: PASS"

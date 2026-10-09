#!/bin/bash
# run_spi.sh — build & run tb_spi (A8).
# Env overrides: FW_HEX (default fw/build/spi_test.hex),
#   FLASH_IMG (default fw/build/spi_img.hex), TIMEOUT_S (default 900).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/spi_test.hex}"
FLASH_IMG="${FLASH_IMG:-fw/build/spi_img.hex}"
TIMEOUT_S="${TIMEOUT_S:-900}"
OUT=build/tb_out
mkdir -p "$OUT" results/raw
for f in "$FW_HEX" "$FLASH_IMG"; do
  [ -f "$f" ] || { echo "RUNNER: FAIL: file not found: $f"; exit 1; }
done
echo "RUNNER: iverilog tb_spi"
iverilog -g2012 -o "$OUT/tb_spi.vvp" tb/tb_spi.sv tb/uart_sink.sv \
  rtl/*.sv third_party/picosoc_spiflash/spiflash.v || exit 1
echo "RUNNER: vvp tb_spi"
timeout "$TIMEOUT_S" vvp "$OUT/tb_spi.vvp" "+hex=$FW_HEX" "+firmware=$FLASH_IMG" \
  2>&1 | tee results/raw/spi.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_spi nonzero exit"; exit 1; }
grep -q "TB_SPI: ALL PASS" results/raw/spi.log || { echo "RUNNER: FAIL: verdict missing"; exit 1; }
echo "RUNNER: PASS"

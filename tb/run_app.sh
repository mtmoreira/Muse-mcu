#!/bin/bash
# run_app.sh — build & run tb_app (D1 + DEMO1).
# The tb live-verifies packets; this script then runs tools/check_app.py as the
# host gate and prints TB_APP: ALL PASS only if both pass. The console
# transcript is saved to results/demo_transcript.txt (DEMO1 requirement).
#
# Env overrides: FW_HEX (default fw/build/app_demo.hex),
#   FW_ELF (default: FW_HEX .hex->.elf), FLASH_IMG (default fw/build/flash.hex),
#   BG_SYM (default bg_task_fn), SEED (only used to pick a default flash name),
#   TIMEOUT_S (default 5400), VCD_WIN (default 1000000).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/app_demo.hex}"
FW_ELF="${FW_ELF:-${FW_HEX%.hex}.elf}"
FLASH_IMG="${FLASH_IMG:-fw/build/flash.hex}"
BG_SYM="${BG_SYM:-bg_task_fn}"
TIMEOUT_S="${TIMEOUT_S:-5400}"
VCD_WIN="${VCD_WIN:-1000000}"
EXPECT_NMSG="${EXPECT_NMSG:-24}"
TC="${TOOLCHAIN:-$HOME/workspace/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
[ -x "$TC/riscv-none-elf-gcc" ] || TC=~/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
OUT=build/tb_out
UARTLOG=results/raw/demo_uart.log
VCD=results/raw/demo_trace.vcd
mkdir -p "$OUT" results/raw
for f in "$FW_HEX" "$FLASH_IMG"; do
  [ -f "$f" ] || { echo "RUNNER: FAIL: file not found: $f"; exit 1; }
done

# bg task range from ELF symbols (optional but recommended)
BG_ARGS=()
if [ -f "$FW_ELF" ]; then
  SYM_LINE="$("$TC/riscv-none-elf-nm" --print-size "$FW_ELF" 2>/dev/null | awk -v s="$BG_SYM" '$4==s && ($3=="T" || $3=="t") {print}')"
  if [ -n "$SYM_LINE" ]; then
    BG_LO="0x$(echo "$SYM_LINE" | awk '{print $1}')"
    # 8 hex digits after 0x: Icarus $value$plusargs %h misparses 0x + short
    # hex (e.g. 0x2838 -> 000x2838); 0x + 8 digits is safe.
    BG_HI=$(python3 -c "print('0x%08x' % (int('$BG_LO',16)+int('0x$(echo "$SYM_LINE" | awk '{print $2}')',16)))")
    echo "RUNNER: bg symbol $BG_SYM: lo=$BG_LO hi=$BG_HI"
    BG_ARGS=("+bg_lo=$BG_LO" "+bg_hi=$BG_HI")
  else
    echo "RUNNER: WARNING: bg symbol '$BG_SYM' not found; preemption check degraded"
  fi
else
  echo "RUNNER: WARNING: ELF not found ($FW_ELF); preemption check degraded"
fi

echo "RUNNER: iverilog tb_app"
iverilog -g2012 -o "$OUT/tb_app.vvp" tb/tb_app.sv tb/uart_sink.sv \
  rtl/*.sv third_party/picosoc_spiflash/spiflash.v || exit 1

echo "RUNNER: vvp tb_app (live DEMO narration below)"
timeout "$TIMEOUT_S" vvp "$OUT/tb_app.vvp" "+hex=$FW_HEX" "+firmware=$FLASH_IMG" \
  "+uartlog=$UARTLOG" "+vcd=$VCD" "+vcdwin=$VCD_WIN" "+expect_nmsg=$EXPECT_NMSG" \
  "${BG_ARGS[@]}" 2>&1 | tee results/demo_transcript.txt
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_app nonzero exit"; exit 1; }
grep -q "TB_APP: SIM PASS" results/demo_transcript.txt || { echo "RUNNER: FAIL: sim verdict missing"; exit 1; }

echo "RUNNER: host checker tools/check_app.py"
python3 tools/check_app.py --uart "$UARTLOG" --flash "$FLASH_IMG" --expect-nmsg "$EXPECT_NMSG"
crc=$?
[ $crc -eq 0 ] || { echo "RUNNER: FAIL: check_app.py rejected the stream"; exit 1; }

echo "TB_APP: ALL PASS"
echo "RUNNER: PASS"

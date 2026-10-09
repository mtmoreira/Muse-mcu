#!/bin/bash
# run_preempt.sh — build & run tb_preempt (C1).
# Extracts the HP task function address range from the ELF via riscv-none-elf-nm.
# Env overrides: FW_HEX (default fw/build/preempt_test.hex),
#   FW_ELF (default: FW_HEX with .hex->.elf), HP_SYM (default hp_task_fn),
#   TIMEOUT_S (default 1800).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/preempt_test.hex}"
FW_ELF="${FW_ELF:-${FW_HEX%.hex}.elf}"
HP_SYM="${HP_SYM:-hp_task_fn}"
TIMEOUT_S="${TIMEOUT_S:-1800}"
TC=~/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
OUT=build/tb_out
mkdir -p "$OUT" results/raw
[ -f "$FW_HEX" ] || { echo "RUNNER: FAIL: firmware hex not found: $FW_HEX"; exit 1; }
[ -f "$FW_ELF" ] || { echo "RUNNER: FAIL: firmware elf not found: $FW_ELF"; exit 1; }

# HP task range from ELF symbols
SYM_LINE="$("$TC/riscv-none-elf-nm" --print-size "$FW_ELF" 2>/dev/null | awk -v s="$HP_SYM" '$4==s && ($3=="T" || $3=="t") {print}')"
if [ -z "$SYM_LINE" ]; then
  echo "RUNNER: FAIL: symbol '$HP_SYM' not found in $FW_ELF"
  echo "RUNNER: text symbols present:"
  "$TC/riscv-none-elf-nm" --print-size "$FW_ELF" | awk '$3=="T" || $3=="t"' | head -40
  exit 1
fi
HP_LO="$(echo "$SYM_LINE" | awk '{print $1}')"
HP_SIZE="$(echo "$SYM_LINE" | awk '{print $2}')"
HP_HI=$(python3 -c "print('%08x' % (int('$HP_LO',16)+int('$HP_SIZE',16)))")
echo "RUNNER: HP symbol $HP_SYM: lo=0x$HP_LO hi=0x$HP_HI"

echo "RUNNER: iverilog tb_preempt"
iverilog -g2012 -o "$OUT/tb_preempt.vvp" tb/tb_preempt.sv tb/uart_sink.sv rtl/*.sv || exit 1
echo "RUNNER: vvp tb_preempt"
timeout "$TIMEOUT_S" vvp "$OUT/tb_preempt.vvp" "+hex=$FW_HEX" \
  "+hp_lo=$HP_LO" "+hp_hi=$HP_HI" 2>&1 | tee results/raw/preempt.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_preempt nonzero exit"; exit 1; }
grep -q "TB_PREEMPT: ALL PASS" results/raw/preempt.log || { echo "RUNNER: FAIL: verdict missing"; exit 1; }
echo "RUNNER: PASS"

#!/bin/bash
# tb/run_gate_preempt_vlt.sh — F3: gate-level RTOS preemption (ZERO-DELAY).
#
# Backend: Verilator 5.032 (recorded per manifest "per-run backend recorded").
# Icarus 12.0 measures ~100 cycles/sec on the 11,858-cell netlist; the F3
# workload (~350k cycles) needs ~1 CPU-hour in Icarus, marginal under load
# against the 120-min host budget. Verilator is cycle-based (zero-delay by
# construction) and runs the same netlist ~100x faster.
#
# What is identical to the Icarus gate build:
#   - synth/mcu_netlist.v (the F1 netlist, sha256 in results/f1_synth.json)
#   - rtl/bootrom.sv + rtl/sram.sv (declared behavioral memory models)
#   - synth/nangate45_cells.v (zero-delay cell models)
#   - fw/build/preempt_test.{hex,elf}, HP symbol range from the ELF
#   - 2000-cycle bound, >= 10 events (manifest F3)
# What differs: the harness (tb/gate/tb_gate_preempt.cpp replicates
# tb/tb_preempt.sv: IRQ pulsing, MEI-entry/HP-entry timestamping, latency
# bound check) instead of tb/tb_preempt.sv.
#
# Env overrides: FW_HEX, FW_ELF, HP_SYM (default vHPTask),
#   MIN_EVENTS (default 10), TIMEOUT_S (default 1800).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "F3: gate-level RTOS preemption — ZERO-DELAY (verilator backend, see header)"

VLT="${VLT_BIN:-$(command -v verilator)}"
[ -n "$VLT" ] || VLT=/home/hatch/workspace/tools/verilator-src/bin/verilator
[ -x "$VLT" ] || { echo "verilator not found (set VLT_BIN)"; exit 1; }
FW_HEX="${FW_HEX:-fw/build/preempt_test.hex}"
FW_ELF="${FW_ELF:-${FW_HEX%.hex}.elf}"
HP_SYM="${HP_SYM:-vHPTask}"
MIN_EVENTS="${MIN_EVENTS:-10}"
TIMEOUT_S="${TIMEOUT_S:-1800}"
TC="${TOOLCHAIN:-$HOME/workspace/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
[ -x "$TC/riscv-none-elf-gcc" ] || TC=${TOOLCHAIN_ROOT:-$HOME/work/toolchains}/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
LOG=tb/logs/gate_preempt_vlt.log
BIN=build/gate/vobj_preempt/tb_gate_preempt
mkdir -p build/gate tb/logs

[ -f "$FW_HEX" ] || { echo "F3: FAIL: firmware hex not found: $FW_HEX"; exit 1; }
[ -f "$FW_ELF" ] || { echo "F3: FAIL: firmware elf not found: $FW_ELF"; exit 1; }
[ -f synth/mcu_netlist.v ] || { echo "F3: FAIL: netlist missing (run synth/run_synth.sh)"; exit 1; }

SYM_LINE="$("$TC/riscv-none-elf-nm" --print-size "$FW_ELF" 2>/dev/null | awk -v s="$HP_SYM" '$4==s && ($3=="T" || $3=="t") {print}')"
[ -n "$SYM_LINE" ] || { echo "F3: FAIL: symbol '$HP_SYM' not found in $FW_ELF"; exit 1; }
HP_LO="$(echo "$SYM_LINE" | awk '{print $1}')"
HP_SIZE="$(echo "$SYM_LINE" | awk '{print $2}')"
HP_HI=$(python3 -c "print('%08x' % (int('$HP_LO',16)+int('$HP_SIZE',16)))")
echo "F3: HP symbol $HP_SYM: lo=0x$HP_LO hi=0x$HP_HI"

if [ ! -x "$BIN" ]; then
  echo "F3: building verilator harness"
  R="$ROOT"
  "$VLT" --binary --top-module sim_top --Mdir build/gate/vobj_preempt -o tb_gate_preempt \
    "$R/tb/gate/sim_top.sv" "$R/synth/mcu_netlist.v" "$R/rtl/bootrom.sv" \
    "$R/rtl/sram.sv" "$R/synth/nangate45_cells.v" \
    --exe "$R/tb/gate/tb_gate_preempt.cpp" || exit 1
fi

echo "F3: running gate sim (ZERO-DELAY, verilator)"
timeout "$TIMEOUT_S" "$BIN" "+hex=$FW_HEX" "+hp_lo=$HP_LO" "+hp_hi=$HP_HI" \
  "+min_events=$MIN_EVENTS" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
echo "F3: harness exit code = $rc"
[ $rc -eq 0 ] || { echo "F3: FAIL: gate sim nonzero exit"; exit 1; }
grep -q "F3: ALL PASS" "$LOG" || { echo "F3: FAIL: verdict missing"; exit 1; }
echo "F3: PASS (>=10 events within 2000 cycles, ZERO-DELAY, verilator backend)"

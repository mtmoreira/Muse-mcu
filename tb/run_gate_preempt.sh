#!/bin/bash
# tb/run_gate_preempt.sh — F3: gate-level RTOS preemption (ZERO-DELAY).
#
# Runs tb_preempt.sv on the synthesized netlist (synth/mcu_netlist.v) with
# the declared behavioral memory models (rtl/bootrom.sv, rtl/sram.sv) and
# zero-delay Nangate45 cell models (synth/nangate45_cells.v).
# Same 2000-cycle bound as C1; manifest F3 requires >= 10 events.
#
# This is a ZERO-DELAY gate simulation: no timing arcs are modeled, so this
# proves functional correctness of the mapped netlist, not timing closure
# (timing closure is out of scope per the manifest).
#
# Env overrides: FW_HEX (default fw/build/preempt_test.hex),
#   FW_ELF (default: FW_HEX .hex->.elf), HP_SYM (default vHPTask),
#   MIN_EVENTS (default 10), TIMEOUT_S (default 7200).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "F3: gate-level RTOS preemption — ZERO-DELAY simulation (no timing arcs modeled)"

FW_HEX="${FW_HEX:-fw/build/preempt_test.hex}"
FW_ELF="${FW_ELF:-${FW_HEX%.hex}.elf}"
HP_SYM="${HP_SYM:-vHPTask}"
MIN_EVENTS="${MIN_EVENTS:-10}"
TIMEOUT_S="${TIMEOUT_S:-7200}"
TC="${TOOLCHAIN:-$HOME/workspace/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
[ -x "$TC/riscv-none-elf-gcc" ] || TC=~/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
OUT=build/gate
LOG=tb/logs/gate_preempt.log
NETLIST=synth/mcu_netlist.v
CELLS=synth/nangate45_cells.v
mkdir -p "$OUT" tb/logs

[ -f "$FW_HEX" ] || { echo "F3: FAIL: firmware hex not found: $FW_HEX"; exit 1; }
[ -f "$FW_ELF" ] || { echo "F3: FAIL: firmware elf not found: $FW_ELF"; exit 1; }
[ -f "$NETLIST" ] || { echo "F3: FAIL: netlist missing: $NETLIST (run synth/run_synth.sh)"; exit 1; }
if [ ! -f "$CELLS" ]; then
  echo "F3: generating $CELLS"
  python3 synth/gen_cells.py --out "$CELLS" || exit 1
fi

# HP task range from ELF symbols
SYM_LINE="$("$TC/riscv-none-elf-nm" --print-size "$FW_ELF" 2>/dev/null | awk -v s="$HP_SYM" '$4==s && ($3=="T" || $3=="t") {print}')"
if [ -z "$SYM_LINE" ]; then
  echo "F3: FAIL: symbol '$HP_SYM' not found in $FW_ELF"
  exit 1
fi
HP_LO="$(echo "$SYM_LINE" | awk '{print $1}')"
HP_SIZE="$(echo "$SYM_LINE" | awk '{print $2}')"
HP_HI=$(python3 -c "print('%08x' % (int('$HP_LO',16)+int('$HP_SIZE',16)))")
echo "F3: HP symbol $HP_SYM: lo=0x$HP_LO hi=0x$HP_HI"

# cell-model coverage (same fail-closed check as F2)
echo "F3: checking cell-model coverage"
python3 - "$NETLIST" "$CELLS" <<'EOF'
import re, sys
nl, cells = sys.argv[1], sys.argv[2]
with open(nl) as f: nlt = f.read()
with open(cells) as f: ct = f.read()
defined = set(re.findall(r'^module\s+(\w+)', nlt, re.M))
used = set(re.findall(r'^\s*(?:\(\*.*?\*\)\s*)?(\w+)\s+\\?\S+\s*\(', nlt, re.M))
# drop Verilog keywords the loose pattern can catch (wire/input/module...)
used -= {'module', 'wire', 'input', 'output', 'inout', 'reg', 'assign',
         'parameter', 'localparam', 'function', 'task'}
modeled = set(re.findall(r'^module\s+(\w+)', ct, re.M))
missing = sorted((used - defined - {'bootrom', 'sram'} - modeled))
if missing:
    print(f'F3: FAIL: netlist cell types without zero-delay models: {missing[:20]}')
    sys.exit(1)
print(f'F3: cell coverage OK ({len(modeled)} models)')
EOF
[ $? -eq 0 ] || exit 1

echo "F3: iverilog gate build (netlist + behavioral memories + zero-delay cells)"
iverilog -g2012 -o "$OUT/tb_preempt_gate.vvp" \
  "$CELLS" "$NETLIST" rtl/bootrom.sv rtl/sram.sv \
  tb/tb_preempt.sv tb/uart_sink.sv || exit 1

echo "F3: vvp tb_preempt_gate (ZERO-DELAY)"
timeout "$TIMEOUT_S" vvp "$OUT/tb_preempt_gate.vvp" "+hex=$FW_HEX" \
  "+hp_lo=$HP_LO" "+hp_hi=$HP_HI" "+min_events=$MIN_EVENTS" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
echo "F3: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "F3: FAIL: gate sim nonzero exit"; exit 1; }
grep -q "TB_PREEMPT: ALL PASS" "$LOG" || { echo "F3: FAIL: verdict missing"; exit 1; }
echo "F3: PASS (>=10 events within 2000 cycles, ZERO-DELAY gate simulation)"

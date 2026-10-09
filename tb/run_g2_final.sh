#!/bin/bash
# tb/run_g2_final.sh — G2 fault injection via Verilator (deterministic).
# Derives the x5 save slot from the port SAVE macro (sp-112), verifies the
# store empirically, injects, and expects the B1 checker to report FAIL.
# Exits 0 only if "G2: ALL PASS" is printed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VLT=/home/hatch/workspace/tools/verilator-src/bin/verilator
BIN=build/rtl_vlt/vobj_g2/Vsim_top_rtl
HEX="fw/build/rtos_regtest.hex"
# pxCurrentTCB not needed; x5 slot derived from live sp. Target PC = ecall in vRegTestAsm.
PC=0x00001d5c
LOG="tb/logs/g2_final_run.log"
mkdir -p results/raw tb/logs
[ -f "$HEX" ] || { echo "G2: FAIL: missing $HEX"; exit 2; }
if [ ! -x "$BIN" ]; then
  echo "G2: building Verilator harness"
  mkdir -p build/rtl_vlt/vobj_g2
  "$VLT" --cc --public --top-module sim_top_rtl --Mdir build/rtl_vlt/vobj_g2 \
    --exe tb/rtl_vlt/tb_g2_final.cpp tb/rtl_vlt/sim_top_rtl.sv rtl/*.sv || exit 1
  make -C build/rtl_vlt/vobj_g2 -f Vsim_top_rtl.mk -j4 || exit 1
fi
# Ensure clean B1 firmware (no G2 instrumentation)
if grep -q "ulCtxSaveAddr" fw/build/rtos_regtest.elf 2>/dev/null; then
  echo "G2: rebuilding clean B1 firmware"
  rm -f fw/build/rtos_regtest.*
  make -C fw APP=rtos_regtest || exit 1
fi
echo "G2: running fault injection"
timeout 900 "$BIN" "+hex=$HEX" "+pc=$PC" > "$LOG" 2>&1
rc=$?
echo "G2: harness exit code = $rc"
[ $rc -eq 0 ] || { echo "G2: FAIL: nonzero exit; see $LOG"; exit 1; }
grep -q "G2: ALL PASS" "$LOG" || { echo "G2: FAIL: no ALL PASS; see $LOG"; exit 1; }
grep -q "injected at cycle" "$LOG" || { echo "G2: FAIL: injection not logged"; exit 1; }
grep -q "TEST regtest FAIL" "$LOG" || { echo "G2: FAIL: checker did not report FAIL"; exit 1; }
cp "$LOG" results/raw/g2_fault_ctx.log
echo "G2: RUNNER PASS"

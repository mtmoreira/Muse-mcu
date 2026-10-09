#!/bin/bash
# tb/run_gate_app_vlt.sh — F2: gate-level application subset (ZERO-DELAY).
#
# Backend: Verilator 5.032 (recorded per manifest "per-run backend recorded").
# The manifest's primary simulator is Icarus 12.0, but Icarus measures ~100
# cycles/sec on the 11,858-cell netlist (2.6M-cycle F2 workload = 7+ hours,
# far beyond the 120-min host budget). Verilator is cycle-based (zero-delay
# by construction) and runs the same netlist ~100x faster.
#
# What is identical to the Icarus gate build:
#   - synth/mcu_netlist.v (the F1 netlist, sha256 in results/f1_synth.json)
#   - rtl/bootrom.sv + rtl/sram.sv (declared behavioral memory models)
#   - synth/nangate45_cells.v (zero-delay cell models)
#   - fw/build/gate4/app_demo.{hex,elf} (FLASH_MSG_COUNT=4 firmware)
#   - 4-message flash image (lengths 0, 56, 64, 1024)
#   - tools/check_app.py --expect-nmsg 4 (the packet gate)
# What differs: the testbench harness (tb/gate/tb_gate_app.cpp drives
# clk/rst, models the SPI flash protocol in C++, samples uart_tx) instead of
# tb/tb_app.sv. The SPI flash model implements the same protocol the
# qualified spiflash.v model provides (0xAB wake, 0x03 READ, mode 0,
# MSB-first); spiflash.v itself cannot compile under Verilator
# (`assign #1` delays) and is used unmodified in the Icarus RTL runs.
#
# Env overrides: SEED (default 1), TIMEOUT_S (default 1800).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "F2: gate-level app subset — ZERO-DELAY (verilator backend, see header)"

VLT=/home/hatch/workspace/tools/verilator-src/bin/verilator
SEED="${SEED:-1}"
TIMEOUT_S="${TIMEOUT_S:-1800}"
LOG=tb/logs/gate_app_vlt.log
UARTLOG=results/raw/gate_uart.log
FW_HEX=fw/build/gate4/app_demo.hex
FLASH_IMG=fw/build/gate4/flash_f2.hex
BIN=build/gate/vobj_app/tb_gate_app
mkdir -p build/gate results/raw tb/logs fw/build/gate4

[ -f synth/mcu_netlist.v ] || { echo "F2: FAIL: netlist missing (run synth/run_synth.sh)"; exit 1; }
if [ ! -f fw/build/gate4/app_demo.hex ]; then
  echo "F2: building gate firmware (FLASH_MSG_COUNT=4)"
  make -C fw APP=app_demo BUILD=build/gate4 EXTRA_DEFS=-DFLASH_MSG_COUNT=4 || exit 1
fi
if [ ! -f "$FLASH_IMG" ]; then
  echo "F2: generating 4-message flash image (seed $SEED)"
  python3 tools/gen_flash_f2.py --seed "$SEED" --out "$FLASH_IMG" || exit 1
fi
if [ ! -x "$BIN" ]; then
  echo "F2: building verilator harness"
  R="$ROOT"
  "$VLT" --binary --top-module sim_top --Mdir build/gate/vobj_app -o tb_gate_app \
    "$R/tb/gate/sim_top.sv" "$R/synth/mcu_netlist.v" "$R/rtl/bootrom.sv" \
    "$R/rtl/sram.sv" "$R/synth/nangate45_cells.v" \
    --exe "$R/tb/gate/tb_gate_app.cpp" || exit 1
fi

echo "F2: running gate sim (ZERO-DELAY, verilator)"
timeout "$TIMEOUT_S" "$BIN" "+hex=$FW_HEX" "+firmware=$FLASH_IMG" "+uartlog=$UARTLOG" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
echo "F2: harness exit code = $rc"
[ $rc -eq 0 ] || { echo "F2: FAIL: gate sim nonzero exit"; exit 1; }
grep -q "F2: SIM PASS" "$LOG" || { echo "F2: FAIL: sim verdict missing"; exit 1; }

echo "F2: host checker tools/check_app.py --expect-nmsg 4"
python3 tools/check_app.py --uart "$UARTLOG" --flash "$FLASH_IMG" --expect-nmsg 4
crc=$?
[ $crc -eq 0 ] || { echo "F2: FAIL: check_app.py rejected the stream"; exit 1; }

echo "F2: PASS (4/4 packets, ZERO-DELAY gate simulation, verilator backend)"

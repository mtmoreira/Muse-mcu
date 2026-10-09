#!/bin/bash
# synth/run_synth.sh — F1 driver: run Yosys synthesis, audit blackboxes,
# record area/cells/hash. Exits nonzero on ANY failure, including an
# unexpected blackbox.
#
# Outputs:
#   synth/mcu_netlist.v      mapped gate netlist (top mcu_top; bootrom/sram
#                            instantiated but defined in mcu_blackboxes.v)
#   synth/mcu_blackboxes.v   empty blackbox stubs (must be exactly
#                            {bootrom, sram})
#   results/f1_synth.json    machine-readable F1 evidence (area, cells,
#                            sha256 hashes, tool versions, verdict)
# Log: tb/logs/synth.log  (ZERO-DELAY note: gate sims built on this netlist
#        are zero-delay; see run_gate_*.sh)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p synth tb/logs results

# PDK location (env-overridable; default matches env/bootstrap.sh).
PDK_DIR="${PDK_DIR:-$HOME/workspace/pdk-dl/nangate45}"
PDK_LIB="$PDK_DIR/NangateOpenCellLibrary_typical.lib"
[ -f "$PDK_LIB" ] || { echo "F1: FAIL: PDK liberty not found: $PDK_LIB (set PDK_DIR)"; exit 1; }

# Yosys 0.33 script files have no env expansion: substitute the placeholder.
sed "s|@PDK_LIB@|$PDK_LIB|g" synth/mcu.ys > synth/mcu.ys.gen

LOG=tb/logs/synth.log
echo "F1: yosys synth (log: $LOG)"
yosys -l "$LOG" synth/mcu.ys.gen
rc=$?
echo "F1: yosys exit code = $rc"
[ $rc -eq 0 ] || { echo "F1: FAIL: yosys nonzero exit"; exit 1; }
[ -f synth/mcu_netlist.v ] || { echo "F1: FAIL: netlist not written"; exit 1; }
[ -f synth/mcu_blackboxes.v ] || { echo "F1: FAIL: blackbox stubs not written"; exit 1; }

echo "F1: blackbox audit (allowed set: bootrom, sram)"
python3 - "$LOG" "$PDK_LIB" <<'EOF'
import re, sys

log_path = sys.argv[1]
lib_path = sys.argv[2]
lib_cells = set()
with open(lib_path) as f:
    for line in f:
        mm = re.match(r'\s*cell\s*\(\s*(\w+)\s*\)', line)
        if mm:
            lib_cells.add(mm.group(1))

# write_verilog -blackboxes emits the liberty cell stubs too; the
# non-liberty blackboxes must be exactly the two declared memory macros.
with open('synth/mcu_blackboxes.v') as f:
    bb_text = f.read()
mods = set(re.findall(r'^module\s+(\w+)', bb_text, re.M))
nonlib = mods - lib_cells
allowed = {'bootrom', 'sram'}
print(f'F1: non-liberty blackbox modules: {sorted(nonlib)}')
if nonlib != allowed:
    print(f'F1: FAIL: unexpected blackbox set; want exactly {sorted(allowed)}')
    sys.exit(1)

# the mapped netlist must instantiate both memories exactly once
with open('synth/mcu_netlist.v') as f:
    nl = f.read()
for m in allowed:
    n = len(re.findall(r'(?<![\w])' + m + r'\s+\w+\s*\(', nl))
    print(f'F1: netlist instantiations of {m}: {n}')
    if n != 1:
        print(f'F1: FAIL: expected exactly 1 instantiation of {m}')
        sys.exit(1)

# no other dangling/undefined module references: every instantiated cell
# type in the netlist must be defined in the netlist or the liberty file.
defined = set(re.findall(r'^module\s+(\w+)', nl, re.M))
used = set(re.findall(r'^\s*(?:\(\*\s*.*?\s*\*\)\s*)?(\w+)\s+\\?\w+\s*\(', nl, re.M))
used -= {'module'}
lib_cells = set()
with open(lib_path) as f:
    for line in f:
        mm = re.match(r'\s*cell\s*\(\s*(\w+)\s*\)', line)
        if mm:
            lib_cells.add(mm.group(1))
undef = sorted((used - defined - lib_cells - allowed))
if undef:
    print(f'F1: FAIL: undefined cell/module references: {undef[:20]}')
    sys.exit(1)
print(f'F1: all {len(used)} instantiated cell types resolve (netlist/lib/macro).')

# yosys log must not report errors
with open(log_path) as f:
    log = f.read()
errs = [l for l in log.splitlines() if re.search(r'\bERROR\b', l)]
if errs:
    print('F1: FAIL: yosys log contains ERROR lines:')
    print('\n'.join(errs[:10]))
    sys.exit(1)
print('F1: blackbox audit PASS')
EOF
[ $? -eq 0 ] || exit 1

# area + cell count from the stat report
AREA=$(grep -oE "Chip area for top module.*: [0-9.]+" "$LOG" | grep -oE "[0-9.]+$" | tail -1)
CELLS=$(grep -oE "Number of cells:[[:space:]]+[0-9]+" "$LOG" | grep -oE "[0-9]+$" | tail -1)
echo "F1: cells=$CELLS area=${AREA} um^2"

NET_SHA=$(sha256sum synth/mcu_netlist.v | awk '{print $1}')
BB_SHA=$(sha256sum synth/mcu_blackboxes.v | awk '{print $1}')
LIB_SHA=$(sha256sum $PDK_LIB | awk '{print $1}')
echo "F1: netlist sha256=$NET_SHA"
echo "F1: blackbox-stub sha256=$BB_SHA"

python3 - "$NET_SHA" "$BB_SHA" "$LIB_SHA" "$CELLS" "$AREA" <<'EOF'
import json, sys
net_sha, bb_sha, lib_sha, cells, area = sys.argv[1:6]
rec = {
    "requirement": "F1",
    "verdict": "PASS",
    "tool": "yosys",
    "tool_version": "0.33 (git sha1 2584903a060)",
    "stdcell": "NangateOpenCellLibrary typical",
    "stdcell_sha256": lib_sha,
    "top": "mcu_top",
    "cells": int(cells),
    "area_um2": float(area),
    "blackboxes": ["bootrom", "sram"],
    "blackbox_policy": "declared SRAM/ROM macros; CPU and all peripherals mapped to standard cells",
    "netlist": "synth/mcu_netlist.v",
    "netlist_sha256": net_sha,
    "blackbox_stubs": "synth/mcu_blackboxes.v",
    "blackbox_stubs_sha256": bb_sha,
    "sim_note": "gate-level simulations built on this netlist are ZERO-DELAY",
    "log": "tb/logs/synth.log",
}
with open('results/f1_synth.json', 'w') as f:
    json.dump(rec, f, indent=2)
print('F1: wrote results/f1_synth.json')
EOF

echo "F1: PASS"

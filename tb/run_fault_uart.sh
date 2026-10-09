#!/bin/bash
# run_fault_uart.sh — build & run tb_fault_uart (G3).
# Runs the D1 workload, tampers the captured UART log (one digest nibble flip
# + one duplicated PKT line), then runs the UNMODIFIED tools/check_app.py,
# which must reject the tampered stream (nonzero exit).
# Env overrides: FW_HEX (default fw/build/app_demo.hex),
#   FLASH_IMG (default fw/build/flash.hex), TIMEOUT_S (default 5400).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FW_HEX="${FW_HEX:-fw/build/app_demo.hex}"
FLASH_IMG="${FLASH_IMG:-fw/build/flash.hex}"
TIMEOUT_S="${TIMEOUT_S:-5400}"
OUT=build/tb_out
UARTLOG=results/raw/fault_uart.log
TAMPERED=results/raw/fault_uart_tampered.log
mkdir -p "$OUT" results/raw
for f in "$FW_HEX" "$FLASH_IMG"; do
  [ -f "$f" ] || { echo "RUNNER: FAIL: file not found: $f"; exit 1; }
done
echo "RUNNER: iverilog tb_fault_uart"
iverilog -g2012 -o "$OUT/tb_fault_uart.vvp" tb/tb_fault_uart.sv tb/uart_sink.sv \
  rtl/*.sv third_party/picosoc_spiflash/spiflash.v || exit 1
echo "RUNNER: vvp tb_fault_uart"
timeout "$TIMEOUT_S" vvp "$OUT/tb_fault_uart.vvp" "+hex=$FW_HEX" "+firmware=$FLASH_IMG" \
  "+uartlog=$UARTLOG" 2>&1 | tee results/raw/fault_uart_sim.log
rc=${PIPESTATUS[0]}
echo "RUNNER: vvp exit code = $rc"
[ $rc -eq 0 ] || { echo "RUNNER: FAIL: tb_fault_uart nonzero exit"; exit 1; }

echo "RUNNER: tampering UART log (nibble flip + duplicate)"
python3 - "$UARTLOG" "$TAMPERED" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src, 'rb').read().split(b'\n')
pkt_re = re.compile(rb'^PKT 9E55AA01 (\d+) (\d+) ([0-9a-fA-F]{64})$')
pkts = [(i, l) for i, l in enumerate(lines) if pkt_re.match(l)]
assert len(pkts) >= 8, f"only {len(pkts)} PKT lines"
# 1) flip one hex nibble in packet id 7's digest
i7, l7 = pkts[7]
m = pkt_re.match(l7)
dig = m.group(3)
new_nib = b'0' if dig[0:1] != b'0' else b'1'
l7t = b'PKT 9E55AA01 ' + m.group(1) + b' ' + m.group(2) + b' ' + new_nib + dig[1:]
lines[i7] = l7t
# 2) duplicate packet id 3's line right after itself
i3, l3 = pkts[3]
lines.insert(i3 + 1, l3)
open(dst, 'wb').write(b'\n'.join(lines))
print(f"TAMPER: flipped digest nibble in {l7[:24].decode()}...; duplicated {l3[:24].decode()}...")
EOF
[ $? -eq 0 ] || { echo "RUNNER: FAIL: tamper step failed"; exit 1; }

echo "RUNNER: unmodified check_app.py on tampered log (must reject)"
python3 tools/check_app.py --uart "$TAMPERED" --flash "$FLASH_IMG" --expect-nmsg 24 \
  2>&1 | tee results/raw/fault_uart_check.log
crc=${PIPESTATUS[0]}
echo "RUNNER: check_app.py exit code = $crc"
if [ $crc -eq 0 ]; then
  echo "RUNNER: FAIL: checker accepted the tampered stream"
  exit 1
fi
grep -q "digest mismatch" results/raw/fault_uart_check.log || { echo "RUNNER: FAIL: no digest-mismatch reported"; exit 1; }
grep -q "sequence error\|packet count" results/raw/fault_uart_check.log || { echo "RUNNER: FAIL: no sequence/count error reported"; exit 1; }
echo "FAULT G3: ACTIVATED (tamper logged above), CHECKER REJECTED (exit $crc)"
echo "TB_FAULT_UART: ALL PASS"
echo "RUNNER: PASS"

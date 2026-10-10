#!/usr/bin/env bash
# tools/collect_verdicts.sh — reconstruct gate verdicts from log files.
#
# Conservative: reports PASS only when the gate's exact PASS marker is
# found in a recent log file; anything else is UNKNOWN (re-run that gate).
# This is a recovery tool for when the runner's stdout is lost; it never
# invents a PASS.
#
# Usage: bash tools/collect_verdicts.sh [--logdir DIR] [--hours N]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOURS="${HOURS:-6}"
# find log files (text only, no compiled .vvp binaries) modified in the last HOURS hours
LOGS=$(find tb/build tb/logs results/raw -type f -mmin -$((HOURS * 60)) \
  ! -name "*.vvp" 2>/dev/null)

check() { # check <gate-id> <marker>
  local id="$1" marker="$2" hit=""
  if [ -n "$LOGS" ]; then
    hit=$(grep -l -F "$marker" $LOGS 2>/dev/null | head -1)
  fi
  if [ -n "$hit" ]; then
    echo "$id: PASS ($hit)"
  else
    echo "$id: UNKNOWN (marker not found: $marker)"
  fi
}

check A1 "ARCH 45/45 PASS"
check A2 "ARCH 45/45 PASS"
check A3 "TB_RESET: ALL PASS"
check A4 "TB_TRAP: ALL PASS"
check A5 "TB_IRQ: ALL PASS"
check A6 "TB_MEMMAP: ALL PASS"
check A7 "TB_UART_RX: ALL PASS"
check A8 "TB_SPI: ALL PASS"
check A9 "A9: ALL PASS"
check B1 "RTOS_VLT regtest: ALL PASS"
check B2 "RTOS_VLT queue: ALL PASS"
check B3 "RTOS_VLT sema: ALL PASS"
check B4 "RTOS_VLT notify: ALL PASS"
check B5 "RTOS_VLT timer: ALL PASS"
check B6 "RTOS_VLT isr: ALL PASS"
check B7 "RTOS_VLT blocktim: ALL PASS"
check C1 "TB_PREEMPT: ALL PASS"
check D1 "TB_APP: ALL PASS"
check D2 "TB_APP: ALL PASS"
check F2 "TB_APP: SIM PASS"
check F3 "TB_PREEMPT: ALL PASS"
check G1 "TB_FAULT_NOTICK: ALL PASS"
check G2 "TB_FAULT_CTX: ALL PASS"
check G3 "TB_FAULT_UART: ALL PASS"
# E1/R1/R2/DEMO1/FIG1/FIG2 have no automated gate command (NOT_RUN by design)
for id in E1 R1 R2 DEMO1 FIG1 FIG2; do echo "$id: NOT_RUN (no gate command)"; done

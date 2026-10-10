#!/bin/bash
# run_demo.sh — DEMO1: human-watchable end-to-end application demonstration.
# Wrapper around tb/run_app.sh (which runs tb/tb_app.sv with a live narrated
# console feed, saves the transcript to results/demo_transcript.txt, captures
# results/raw/demo_trace.vcd for FIG2, and runs tools/check_app.py).
# The manifest names this path as the DEMO1 checker; the implementation lives
# in tb/run_app.sh to avoid duplicating the 24-message workload logic.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${TOOLCHAIN:-}" ] && [ -f "$ROOT/env/activate.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/env/activate.sh"
fi
exec bash "$ROOT/tb/run_app.sh" "$@"

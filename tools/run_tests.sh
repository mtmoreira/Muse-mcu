#!/usr/bin/env bash
# tools/run_tests.sh — run the acceptance suite (self-contained).
#
# If TOOLCHAIN is unset, sources env/activate.sh (written by
# env/setup.sh). Passes all arguments through to run_acceptance.py.
#
# Usage: bash tools/run_tests.sh [--smoke]
#   --smoke: run only the labeled fast subset (A3, A4, A6, C1-quick)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${TOOLCHAIN:-}" ] && [ -f "$ROOT/env/activate.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/env/activate.sh"
fi

exec python3 "$ROOT/tools/run_acceptance.py" "$@"

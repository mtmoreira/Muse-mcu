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

# Self-heal the environment before anything else: prefer Homebrew bash 5+
# (macOS /bin/bash is 3.2, no mapfile) and force the setup.sh-built
# toolchain (Icarus 12.x, spike) first on PATH. This makes the script
# work regardless of the caller's shell/PATH.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] && [ -x /opt/homebrew/bin/bash ]; then
  exec /opt/homebrew/bin/bash "$0" "$@"
fi
_TCR="${TOOLCHAIN_ROOT:-$HOME/workspace/toolchains}"
for _d in "$_TCR/icarus-12.0/bin" \
          "$_TCR/spike-mcu/bin" \
          /opt/homebrew/bin; do
  if [ -d "$_d" ]; then
    case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH";; esac
  fi
done
export PATH
unset _d

if [ -z "${TOOLCHAIN:-}" ] && [ -f "$ROOT/env/activate.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/env/activate.sh"
fi

# Re-assert after activate.sh in case it reordered PATH.
_TCR="${TOOLCHAIN_ROOT:-$HOME/workspace/toolchains}"
for _d in "$_TCR/icarus-12.0/bin" \
          "$_TCR/spike-mcu/bin" \
          /opt/homebrew/bin; do
  if [ -d "$_d" ]; then
    case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH";; esac
  fi
done
export PATH
unset _d

# Preflight: gate scripts need bash 4+ (mapfile) and Icarus 12.x (v13
# hard-fails on this RTL's constant selects in always_*).
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "run_tests: FAIL: need bash 4+ (have ${BASH_VERSION:-unknown}); on macOS: brew install bash" >&2
  echo "run_tests: then re-run with /opt/homebrew/bin first on PATH" >&2
  exit 2
fi
if ! command -v iverilog >/dev/null 2>&1; then
  echo "run_tests: FAIL: iverilog not on PATH (run env/setup.sh first)" >&2
  exit 2
fi
IVL_VER=$(iverilog -V 2>&1 | head -1)
case "$IVL_VER" in
  *"version 12."*) ;;
  *)
    echo "run_tests: FAIL: need Icarus Verilog 12.x, found: $IVL_VER" >&2
    echo "run_tests: put the setup.sh-built v12 first on PATH:" >&2
    echo "run_tests:   export TOOLCHAIN_ROOT=\$HOME/work/toolchains" >&2
    echo "run_tests:   export PATH=\"\$TOOLCHAIN_ROOT/icarus-12.0/bin:\$PATH\"" >&2
    exit 2
    ;;
esac

# Tee a timestamped copy of the full output so a lost terminal/clipboard
# never loses the verdict summary.
TS=$(date +%Y%m%d-%H%M%S)
OUT="$ROOT/results/run_$TS.log"
mkdir -p "$ROOT/results"
echo "run_tests: full output also saved to $OUT"
python3 "$ROOT/tools/run_acceptance.py" "$@" 2>&1 | tee "$OUT"
echo "run_tests: output saved to $OUT"

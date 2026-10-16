#!/bin/bash
# Generate .gtkw/.tcl views for the given run dirs (uses the demo venv python).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HERE/.venv/bin/python"
[ -x "$PY" ] || PY=python3
for rd in "$@"; do
  "$PY" "$HERE/tools/make_gtkw.py" --run-dir "$rd"
done

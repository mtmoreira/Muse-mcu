#!/bin/bash
# demo/image/demo.sh — visual demo interface (spec Section 6).
#
#   demo.sh setup
#   demo.sh reproduce
#   demo.sh walk --run <run-id>
#   demo.sh show --run <run-id> --stage 06
#   demo.sh verify --run <run-id>
#   demo.sh negative-control --run <run-id>
#   demo.sh render-video --baseline <run-id> --fault <run-id>   (post-review)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
VENV="$HERE/.venv"
PY="$VENV/bin/python"
[ -x "$PY" ] || PY=python3
export TOOLCHAIN="${TOOLCHAIN:-$HOME/workspace/toolchains/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
TC_NM="$TOOLCHAIN/riscv-none-elf-nm"

say() { echo "[demo] $*"; }

cmd_setup() {
  say "checking dependencies"
  python3 --version
  iverilog -V 2>/dev/null | head -1 || say "WARNING: iverilog not on PATH (project env provides it)"
  gtkwave --version 2>/dev/null | head -1 || say "NOTE: gtkwave not on PATH (waveform views pending)"
  "$TOOLCHAIN/riscv-none-elf-gcc" --version | head -1
  if [ ! -x "$PY" ] || ! "$PY" -c "import cv2" 2>/dev/null; then
    say "creating venv + pinned packages"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet "opencv-python-headless==4.11.0.86" \
      "pillow==11.3.0" "matplotlib==3.10.6"
    # Fail loudly if the install did not land (a quiet pip failure
    # once let setup continue and die later on the import).
    "$PY" -c "import cv2" 2>/dev/null || {
      say "ERROR: pip install finished but cv2 is not importable in $VENV"
      say "run again; if it persists, run without --quiet to see pip's error"
      return 1
    }
  fi
  {
    echo "setup record $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "python: $(python3 --version 2>&1)"
    echo "iverilog: $(iverilog -V 2>/dev/null | head -1)"
    echo "gtkwave: $(gtkwave --version 2>/dev/null | head -1)"
    echo "gcc: $("$TOOLCHAIN/riscv-none-elf-gcc" --version | head -1)"
    "$PY" -c "import cv2, numpy, PIL, matplotlib; print('cv2', cv2.__version__); print('numpy', numpy.__version__); print('pillow', PIL.__version__); print('matplotlib', matplotlib.__version__)"
  } | tee "$HERE/SETUP_VERSIONS.txt"
  "$PY" "$HERE/tools/ref_sobel.py" qualify | tail -1
}

freeze_record() {
  local f="$1"
  {
    echo "image_demo firmware freeze $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git_head: $(git rev-parse HEAD)"
    echo "elf_sha256: $(sha256sum fw/build/image_demo.elf | cut -d' ' -f1)"
    echo "hex_sha256: $(sha256sum fw/build/image_demo.hex | cut -d' ' -f1)"
    echo "bin_sha256: $(sha256sum fw/build/image_demo.bin | cut -d' ' -f1)"
    echo "app_source_sha256: $(sha256sum fw/app/image_demo.c | cut -d' ' -f1)"
    echo "config: tick 1000 Hz, preemption on, time slicing kernel default (macro undefined), priorities IO=1 GX=2 GY=2 Combine=3"
  } > "$f"
  cat "$f"
}

run_one() { # kind runid fault
  local kind="$1" rid="$2" fault="$3"
  local rd="$HERE/runs/$rid"
  local ce
  mkdir -p "$rd"
  bash tb/run_image.sh --flash "$HERE/inputs/${kind}_flash.hex" \
       --outdir "$rd" --fault "$fault" || return 2
  cat > "$rd/meta.json" <<EOF
{"kind": "$kind", "run_id": "$rid", "fault": $fault,
 "input_raw": "$HERE/inputs/$kind.raw", "input_json": "$HERE/inputs/$kind.json",
 "ref_dir": "$HERE/refs/$kind", "flash_bin": "$HERE/inputs/${kind}_flash.bin",
 "elf": "$ROOT/fw/build/image_demo.elf"}
EOF
  "$PY" "$HERE/tools/check_image.py" --run-dir "$rd" \
    --input-raw "$HERE/inputs/$kind.raw" --ref-dir "$HERE/refs/$kind" \
    --flash-bin "$HERE/inputs/${kind}_flash.bin" \
    > "$rd/checker_console.log" 2>&1
  ce=$?
  echo "$ce" > "$rd/checker_exit.txt"
  echo "checker exit=$ce (run $rid)"
  return "$ce"
}

# Gate a finished run against its required functional outcome.
# pass:   the functional checker must have PASSED (exit 0 recorded
#         in checker_exit.txt by run_one).
# reject: the functional checker must have REJECTED the run
#         (exit 1) AND the negative-control wrapper must confirm
#         the detection (its own exit 0; it checks the injection
#         record, the single (32,32) mismatch, packet integrity).
# Returns nonzero when the requirement is not met, which stops
# cmd_reproduce.
gate_run() { # run-id pass|reject
  local rid="$1" want="$2" rd; rd=$(run_dir "$rid")
  local ce; ce=$(cat "$rd/checker_exit.txt" 2>/dev/null || echo missing)
  if [ "$want" = "pass" ]; then
    if [ "$ce" = "0" ]; then
      say "gate: $rid functional checker PASS (required)"
      return 0
    fi
    say "gate: $rid functional checker exit=$ce, expected 0 (PASS). REPRODUCE STOPS."
    return 1
  fi
  if [ "$ce" != "1" ]; then
    say "gate: $rid functional checker exit=$ce, expected 1 (the faulty application must be rejected). REPRODUCE STOPS."
    return 1
  fi
  local nc
  if ! nc=$("$PY" "$HERE/tools/negative_control.py" --run-dir "$rd" 2>&1); then
    echo "$nc"
    say "gate: $rid negative control did not confirm the detection. REPRODUCE STOPS."
    return 1
  fi
  echo "$nc"
  say "gate: $rid faulty application rejected, negative control CONFIRMED (required)"
  return 0
}

cmd_reproduce() {
  local ts rc; ts=$(date +%Y%m%d-%H%M%S)
  say "building firmware (frozen for all runs below)"
  make -C fw APP=image_demo > /dev/null || { say "firmware build FAILED"; return 1; }
  freeze_record "$HERE/runs/FREEZE-$ts.txt"
  say "generating main input + flash + reference"
  "$PY" "$HERE/tools/gen_input_image.py" --kind main --outdir "$HERE/inputs" > /dev/null
  "$PY" "$HERE/tools/build_flash.py" --raw "$HERE/inputs/main.raw" --frame 1 \
    --out-prefix "$HERE/inputs/main_flash" > /dev/null
  "$PY" "$HERE/tools/ref_sobel.py" compute --raw "$HERE/inputs/main.raw" \
    --outdir "$HERE/refs/main" > /dev/null
  say "baseline run"
  run_one main "baseline-$ts" 0; rc=$?
  [ $rc -eq 2 ] && { say "baseline run FAILED at tb level"; return 1; }
  gate_run "baseline-$ts" pass || return 1
  say "fault run"
  run_one main "fault-$ts" 1; rc=$?
  [ $rc -eq 2 ] && { say "fault run FAILED at tb level"; return 1; }
  gate_run "fault-$ts" reject || return 1
  say "post-freeze additional input (GEN1): generating extra image AFTER the freeze"
  "$PY" "$HERE/tools/gen_input_image.py" --kind extra --outdir "$HERE/inputs" > /dev/null
  "$PY" "$HERE/tools/build_flash.py" --raw "$HERE/inputs/extra.raw" --frame 2 \
    --out-prefix "$HERE/inputs/extra_flash" > /dev/null
  "$PY" "$HERE/tools/ref_sobel.py" compute --raw "$HERE/inputs/extra.raw" \
    --outdir "$HERE/refs/extra" > /dev/null
  run_one extra "extra-$ts" 0; rc=$?
  [ $rc -eq 2 ] && { say "extra run FAILED at tb level"; return 1; }
  gate_run "extra-$ts" pass || return 1
  say "building walkthrough assets"
  for rid in "baseline-$ts" "fault-$ts"; do
    "$PY" "$HERE/tools/make_assets.py" --run-dir "$HERE/runs/$rid" \
      --kind "${rid%%-*}" --input-raw "$HERE/inputs/main.raw" \
      --input-json "$HERE/inputs/main.json" --ref-dir "$HERE/refs/main" \
      --flash-bin "$HERE/inputs/main_flash.bin" \
      --elf fw/build/image_demo.elf --tc-nm "$TC_NM" || return 1
  done
  bash "$HERE/tools/make_gtkw.sh" "$HERE/runs/baseline-$ts" "$HERE/runs/fault-$ts" || true
  "$PY" "$HERE/tools/make_index.py" --runs-dir "$HERE/runs" \
    --baseline "baseline-$ts" --fault "fault-$ts" --extra "extra-$ts"
  say "reproduce complete: runs baseline-$ts, fault-$ts, extra-$ts"
  say "review index: $HERE/runs/index.html"
}

run_dir() { echo "$HERE/runs/$1"; }

cmd_verify() {
  local rid="$1" rd; rd=$(run_dir "$rid")
  [ -d "$rd" ] || { say "no such run: $rid"; return 2; }
  local kind; kind=$("$PY" -c "import json;print(json.load(open('$rd/meta.json'))['kind'])")
  "$PY" "$HERE/tools/check_image.py" --run-dir "$rd" \
    --input-raw "$HERE/inputs/$kind.raw" --ref-dir "$HERE/refs/$kind" \
    --flash-bin "$HERE/inputs/${kind}_flash.bin"
}

cmd_negative() {
  local rd; rd=$(run_dir "$1")
  cmd_verify "$1" > /dev/null 2>&1
  "$PY" "$HERE/tools/negative_control.py" --run-dir "$rd"
}

cmd_show() {
  "$PY" "$HERE/tools/show_stage.py" --here "$HERE" --run "$1" --stage "$2"
}

cmd_walk() {
  for s in 01 02 03 04 05 06 07 08; do
    cmd_show "$1" "$s"
    if [ "$s" != "08" ]; then
      printf "[demo] stage %s shown. Press Enter for the next stage (Ctrl-C to stop)... " "$s"
      read -r _ < /dev/tty || break
    fi
  done
}

cmd_render() { # --baseline ID --fault ID
  local B="" F=""
  while [ $# -gt 0 ]; do case "$1" in
    --baseline) B="$2"; shift 2;;
    --fault) F="$2"; shift 2;;
    *) shift;;
  esac; done
  [ -n "$B" ] && [ -n "$F" ] || { say "usage: demo.sh render-video --baseline ID --fault ID"; return 2; }
  [ -d "$(run_dir "$B")" ] || { say "no such run: $B"; return 2; }
  [ -d "$(run_dir "$F")" ] || { say "no such run: $F"; return 2; }
  say "rendering video from reviewed runs: $B + $F"
  "$PY" "$HERE/tools/render_video.py" --baseline-dir "$(run_dir "$B")" \
    --fault-dir "$(run_dir "$F")" --out-dir "$HERE/video"
}

case "${1:-}" in
  setup) cmd_setup;;
  reproduce) cmd_reproduce;;
  verify) shift; while [ $# -gt 0 ]; do case "$1" in --run) cmd_verify "$2"; exit $?;; esac; shift; done;;
  negative-control) shift; while [ $# -gt 0 ]; do case "$1" in --run) cmd_negative "$2"; exit $?;; esac; shift; done;;
  show) shift; R=""; S=""; while [ $# -gt 0 ]; do case "$1" in --run) R="$2"; shift 2;; --stage) S="$2"; shift 2;; *) shift;; esac; done; cmd_show "$R" "$S";;
  walk) shift; while [ $# -gt 0 ]; do case "$1" in --run) cmd_walk "$2"; exit 0;; esac; shift; done;;
  render-video) shift; cmd_render "$@"; exit $?;;
  *) echo "usage: demo.sh setup|reproduce|walk --run ID|show --run ID --stage NN|verify --run ID|negative-control --run ID|render-video --baseline ID --fault ID" >&2; exit 2;;
esac

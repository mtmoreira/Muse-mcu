#!/usr/bin/env bash
# Muse MCU Phase 0 bootstrap (R1 gate).
#
# Provisions ALL pinned tools on a clean Ubuntu 24.04 host:
#   - apt packages: build-essential, autoconf, g++, flex, bison, git, python3,
#     device-tree-compiler, yosys (must be 0.33), iverilog (12.x if offered)
#   - Icarus Verilog 12.0: from apt if the distro offers a 12.x candidate,
#     otherwise built from source (tag v12_0) into ~/workspace/toolchains/icarus-12.0
#   - xpack riscv-none-elf-gcc 15.2.0: downloaded, sha256-verified, extracted to
#     ~/workspace/toolchains/riscv/
#   - Nangate45 PDK: NOT fetched by this script. The user places it at
#     ~/workspace/pdk-dl/nangate45/; the script verifies presence and sha256.
#
# Ends with a version-check section that prints every tool version and exits
# nonzero on any mismatch. Log the run with:
#   bash env/bootstrap.sh > bootstrap.log 2>&1; echo "exit=$?" >> bootstrap.log
#
# Install roots can be overridden: TOOLCHAIN_ROOT, PDK_DIR, UPSTREAM_DL_DIR.
set -euo pipefail

GCC_VER="15.2.0"
GCC_TAG="xpack-riscv-none-elf-gcc-15.2.0-1"
GCC_SHA="aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758"
GCC_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/${GCC_TAG}-linux-x64.tar.gz"
ICARUS_REQ="12"
ICARUS_PREFIX_NAME="icarus-12.0"
YOSYS_REQ="0.33"
PYTHON_MIN_MAJOR=3
PYTHON_MIN_MINOR=10

TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-$HOME/workspace/toolchains}"
PDK_DIR="${PDK_DIR:-$HOME/workspace/pdk-dl/nangate45}"
UPSTREAM_DL_DIR="${UPSTREAM_DL_DIR:-$HOME/workspace/.upstream-dl}"
ICARUS_PREFIX="$TOOLCHAIN_ROOT/$ICARUS_PREFIX_NAME"
GCC_PREFIX="$TOOLCHAIN_ROOT/riscv/$GCC_TAG"
GCC_TAR="$UPSTREAM_DL_DIR/${GCC_TAG}-linux-x64.tar.gz"
IVL_BUILD_LOG="$UPSTREAM_DL_DIR/iverilog-build.log"

PDK_LIB_SHA="8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1"
PDK_MACROLEF_SHA="840b01e500826096d1edcc752350834da647fdbf360798f243f8122b52b357c3"
PDK_TECHLEF_SHA="834a79295054cd4209178d1bade67c353863c47bb4b3c22ee38b862b7cec37f2"

FAILURES=0
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

log() { printf '[bootstrap] %s\n' "$*"; }
fail() { printf '[bootstrap] FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

# ---------------- 1. OS sanity ----------------
log "OS: $(. /etc/os-release && echo "$NAME $VERSION")"
if ! grep -qE '^VERSION_ID="24\.04"' /etc/os-release 2>/dev/null; then
  log "WARNING: not Ubuntu 24.04; pinned versions were qualified on 24.04 only."
fi

# ---------------- 2. apt packages ----------------
log "Updating apt and installing base packages..."
$SUDO apt-get update -q
$SUDO apt-get install -y -q \
  build-essential autoconf g++ flex bison git python3 device-tree-compiler

# ---------------- 3. yosys 0.33 (apt; abort if the distro version is not 0.33) ----------------
log "Checking yosys 0.33 availability..."
YOSYS_CANDIDATE="$(apt-cache policy yosys 2>/dev/null | awk '/Candidate:/ {print $2}' || true)"
log "yosys apt candidate: ${YOSYS_CANDIDATE:-(none)}"
if [[ ! "$YOSYS_CANDIDATE" =~ ^${YOSYS_REQ//./\.} ]]; then
  log "ABORT: this host's apt offers yosys '${YOSYS_CANDIDATE}', not the pinned 0.33."
  log "The acceptance contract (manifest.yaml tool_versions) pins synth: yosys-0.33."
  log "Provision yosys 0.33 some other way (e.g. build tag v0.33 from source) and rerun."
  exit 1
fi
$SUDO apt-get install -y -q yosys
log "yosys installed: $(yosys --version)"

# ---------------- 4. iverilog 12.x ----------------
# Prefer apt when it offers 12.x; otherwise build v12_0 from source.
IVL_CANDIDATE="$(apt-cache policy iverilog 2>/dev/null | awk '/Candidate:/ {print $2}' || true)"
log "iverilog apt candidate: ${IVL_CANDIDATE:-(none)}"
if [[ "$IVL_CANDIDATE" =~ ^${ICARUS_REQ}\. ]]; then
  log "apt offers iverilog 12.x; installing from apt."
  $SUDO apt-get install -y -q iverilog
elif command -v iverilog >/dev/null 2>&1 && iverilog -V 2>/dev/null | grep -q "version ${ICARUS_REQ}\."; then
  log "iverilog 12.x already installed; keeping it."
else
  log "apt does not offer iverilog 12.x; building Icarus Verilog 12.0 from source."
  mkdir -p "$UPSTREAM_DL_DIR" "$TOOLCHAIN_ROOT"
  IVL_SRC="$UPSTREAM_DL_DIR/iverilog"
  if [ ! -d "$IVL_SRC" ]; then
    git clone --depth 1 --branch v12_0 https://github.com/steveicarus/iverilog "$IVL_SRC"
  fi
  {
    echo "=== Icarus Verilog v12_0 source build $(date -u +%FT%TZ) ==="
    cd "$IVL_SRC"
    sh autoconf.sh
    ./configure --prefix="$ICARUS_PREFIX"
    make -j"$(nproc)"
    make install
    echo "=== build done ==="
  } > "$IVL_BUILD_LOG" 2>&1
  log "source build log: $IVL_BUILD_LOG"
fi
export PATH="$ICARUS_PREFIX/bin:$PATH"
log "iverilog: $(iverilog -V 2>/dev/null | head -1)"

# ---------------- 5. xpack riscv-none-elf-gcc 15.2.0 ----------------
log "Provisioning $GCC_TAG..."
mkdir -p "$UPSTREAM_DL_DIR" "$TOOLCHAIN_ROOT/riscv"
if [ ! -f "$GCC_TAR" ]; then
  log "Downloading $GCC_URL"
  curl -fL -o "$GCC_TAR" "$GCC_URL"
fi
echo "$GCC_SHA  $GCC_TAR" | sha256sum -c -
if [ ! -x "$GCC_PREFIX/bin/riscv-none-elf-gcc" ]; then
  log "Extracting to $TOOLCHAIN_ROOT/riscv/"
  tar -xzf "$GCC_TAR" -C "$TOOLCHAIN_ROOT/riscv/"
fi
log "gcc: $("$GCC_PREFIX/bin/riscv-none-elf-gcc" --version | head -1)"

# ---------------- 6. Nangate45 PDK (user-placed; verified here) ----------------
log "Verifying PDK at $PDK_DIR ..."
for f in NangateOpenCellLibrary_typical.lib; do
  p="$PDK_DIR/$f"
  if [ ! -f "$p" ]; then
    log "ABORT: PDK file missing: $p"
    log "Place the Nangate45 PDK at $PDK_DIR (or set PDK_DIR) with files:"
    log "  NangateOpenCellLibrary_typical.lib, NangateOpenCellLibrary.macro.lef, NangateOpenCellLibrary.tech.lef"
    exit 1
  fi
  ACTUAL="$(sha256sum "$p" | awk '{print $1}')"
  [ "$f" = "NangateOpenCellLibrary_typical.lib" ] && WANT="$PDK_LIB_SHA"
  if [ "$ACTUAL" != "$WANT" ]; then
    log "ABORT: sha256 mismatch for $f (want $WANT, got $ACTUAL)"
    exit 1
  fi
  log "sha256 OK: $f"
done
for f in NangateOpenCellLibrary.macro.lef NangateOpenCellLibrary.tech.lef; do
  p="$PDK_DIR/$f"
  [ -f "$p" ] || { log "ABORT: PDK file missing: $p"; exit 1; }
  ACTUAL="$(sha256sum "$p" | awk '{print $1}')"
  [ "$f" = "NangateOpenCellLibrary.macro.lef" ] && WANT="$PDK_MACROLEF_SHA"
  [ "$f" = "NangateOpenCellLibrary.tech.lef" ] && WANT="$PDK_TECHLEF_SHA"
  if [ "$ACTUAL" != "$WANT" ]; then
    log "ABORT: sha256 mismatch for $f (want $WANT, got $ACTUAL)"
    exit 1
  fi
  log "sha256 OK: $f"
done

# ---------------- 7. version check (all pinned tools) ----------------
log "=========== VERSION CHECK ==========="

IVL_OUT="$(iverilog -V 2>&1 | head -1 || true)"
echo "iverilog : $IVL_OUT"
echo "           path: $(command -v iverilog)"
if echo "$IVL_OUT" | grep -q "Icarus Verilog version ${ICARUS_REQ}\."; then
  echo "           pinned 12.x: OK"
else
  fail "iverilog is not version 12.x"
fi

YOSYS_OUT="$(yosys --version 2>&1 || true)"
echo "yosys    : $YOSYS_OUT"
echo "           path: $(command -v yosys)"
if echo "$YOSYS_OUT" | grep -q "Yosys ${YOSYS_REQ} "; then
  echo "           pinned 0.33: OK"
else
  fail "yosys is not version 0.33"
fi

GCC_BIN="$GCC_PREFIX/bin/riscv-none-elf-gcc"
GCC_OUT="$("$GCC_BIN" --version 2>&1 | head -1 || true)"
echo "riscv gcc: $GCC_OUT"
echo "           path: $GCC_BIN"
if echo "$GCC_OUT" | grep -q "$GCC_VER"; then
  echo "           pinned 15.2.0: OK"
else
  fail "riscv-none-elf-gcc is not version 15.2.0"
fi
echo "gcc tarball sha256: $(sha256sum "$GCC_TAR" | awk '{print $1}')"
if [ "$(sha256sum "$GCC_TAR" | awk '{print $1}')" = "$GCC_SHA" ]; then
  echo "           tarball sha256: OK"
else
  fail "gcc tarball sha256 mismatch"
fi

echo "pdk lib  : $PDK_LIB_SHA"
echo "pdk macro: $PDK_MACROLEF_SHA"
echo "pdk tech : $PDK_TECHLEF_SHA"
echo "           dir: $PDK_DIR (verified above)"

DTC_OUT="$(dtc --version 2>&1 | head -1 || true)"
echo "dtc      : $DTC_OUT"
echo "           path: $(command -v dtc)"
command -v dtc >/dev/null 2>&1 || fail "device-tree-compiler missing"

PY_OUT="$(python3 --version 2>&1 || true)"
echo "python3  : $PY_OUT"
PY_MAJOR="$(python3 -c 'import sys; print(sys.version_info[0])' 2>/dev/null || echo 0)"
PY_MINOR="$(python3 -c 'import sys; print(sys.version_info[1])' 2>/dev/null || echo 0)"
if [ "$PY_MAJOR" -gt "$PYTHON_MIN_MAJOR" ] || { [ "$PY_MAJOR" -eq "$PYTHON_MIN_MAJOR" ] && [ "$PY_MINOR" -ge "$PYTHON_MIN_MINOR" ]; }; then
  echo "           >=3.10: OK"
else
  fail "python3 is older than 3.10"
fi

echo ""
echo "Suggested PATH additions:"
echo "  export PATH=\"$ICARUS_PREFIX/bin:\$PATH\""
echo "  export PATH=\"$GCC_PREFIX/bin:\$PATH\""
echo "  export PDK_DIR=\"$PDK_DIR\""
echo ""

if [ "$FAILURES" -ne 0 ]; then
  log "VERSION CHECK FAILED with $FAILURES failure(s)."
  exit 1
fi
log "VERSION CHECK PASSED. Bootstrap complete."

#!/usr/bin/env bash
# env/setup.sh — self-contained dependency setup for the Muse MCU
# acceptance suite.
#
# Checks every dependency; installs only what is missing or
# wrong-versioned. Idempotent: safe to re-run at any time.
#
# Supported: macOS (arm64 and x64) and Ubuntu 24.04.
#
# Usage:  bash env/setup.sh [--yes]
#   --yes   install without prompting (default: prompt before each install)
#
# When it reports ALL OK, activate the environment and run the suite:
#   source env/activate.sh && make acceptance
#
# Install roots (overridable):
#   TOOLCHAIN_ROOT  default $HOME/workspace/toolchains
#   PDK_DIR         default $HOME/workspace/pdk-dl/nangate45
#
# Pinned versions live in env/VERSIONS.md; this script enforces the
# same pins (gcc 15.2.0, iverilog 12.x, yosys 0.33, spike @ e448970b).

set -u

YES=0
[ "${1:-}" = "--yes" ] && YES=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TOOLCHAIN_ROOT="${TOOLCHAIN_ROOT:-$HOME/workspace/toolchains}"
PDK_DIR="${PDK_DIR:-$HOME/workspace/pdk-dl/nangate45}"
DL_DIR="${DL_DIR:-$HOME/workspace/.setup-dl}"

GCC_VER="15.2.0"
GCC_TAG="xpack-riscv-none-elf-gcc-15.2.0-1"
GCC_BASE="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1"
IVL_TAG="v12_0"
YOSYS_TAG="yosys-0.33"
SPIKE_PIN="e448970b1668f7893f88e54824e1387a3e5fe09b"
PDK_LIB_SHA="8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1"
PDK_URL="https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/raw/master/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib"

OS=""; ARCH=""
case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *) echo "setup: unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64)        ARCH=x64 ;;
  *) echo "setup: unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$OS" = mac ]; then
  NCPU="$(sysctl -n hw.ncpu)"
  GCC_TAR="${GCC_TAG}-darwin-${ARCH}.tar.gz"
else
  NCPU="$(nproc)"
  if [ "$ARCH" = arm64 ]; then GCC_TAR="${GCC_TAG}-linux-arm64.tar.gz";
  else GCC_TAR="${GCC_TAG}-linux-x64.tar.gz"; fi
fi

# Pinned sha256 where we have ground truth (verified 2026-10-09).
gcc_sha_for() {
  case "$1" in
    *darwin-arm64*) echo "6588e8351455fad8aca37551f0e5a5543f3346bfa9a837cf03cbd3bdd4989f8f" ;;
    *linux-x64*)   echo "aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758" ;;
    *) echo "" ;;
  esac
}

FAILURES=0
log()  { printf '[setup] %s\n' "$*"; }
ok()   { printf '[setup] OK: %s\n' "$*"; }
fail() { printf '[setup] FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

confirm() {
  # confirm "prompt text" -> 0 if approved
  if [ "$YES" = 1 ]; then return 0; fi
  printf '[setup] %s [y/N] ' "$1"
  read -r ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

have() { command -v "$1" >/dev/null 2>&1; }

sha256() {
  if have shasum; then shasum -a 256 "$1" | awk '{print $1}';
  else sha256sum "$1" | awk '{print $1}'; fi
}

# ---------------------------------------------------------------- basics
log "OS=$OS arch=$ARCH ncpu=$NCPU"

if [ "$OS" = mac ]; then
  if ! have brew; then
    fail "Homebrew not found. Install it first: https://brew.sh — then re-run."
  fi
  for t in cc make git curl; do
    have "$t" || fail "missing '$t' (Xcode command line tools: run: xcode-select --install)"
  done
else
  if ! have sudo; then fail "sudo required on Linux for apt installs"; fi
  MISSING_PKGS=""
  for t in cc make git curl python3; do have "$t" || MISSING_PKGS="$MISSING_PKGS $t"; done
  if [ -n "$MISSING_PKGS" ]; then
    if confirm "apt-get install build-essential git curl python3?"; then
      sudo apt-get update -qq && sudo apt-get install -y -qq build-essential git curl python3 \
        || fail "apt install failed"
    else
      fail "missing:$MISSING_PKGS"
    fi
  fi
fi

# ---------------------------------------------------------------- python
if have python3 && python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)"; then
  ok "python3 $(python3 -c 'import sys; print(sys.version.split()[0])')"
else
  fail "python3 >= 3.10 required"
fi
if python3 -c "import yaml" 2>/dev/null; then
  ok "pyyaml present"
else
  if confirm "pip install pyyaml?"; then
    python3 -m pip install --user pyyaml 2>/dev/null \
      || python3 -m pip install --user --break-system-packages pyyaml 2>/dev/null \
      || fail "pyyaml install failed"
    python3 -c "import yaml" 2>/dev/null && ok "pyyaml installed"
  else
    fail "pyyaml missing (tools/run_acceptance.py needs it)"
  fi
fi

# ------------------------------------------------- riscv-none-elf-gcc 15.2.0
GCC_BIN="$TOOLCHAIN_ROOT/riscv/$GCC_TAG/bin/riscv-none-elf-gcc"
if [ -x "$GCC_BIN" ] && "$GCC_BIN" --version 2>/dev/null | grep -q "15\.2\.0"; then
  ok "riscv-none-elf-gcc 15.2.0 ($GCC_BIN)"
else
  if confirm "download xPack riscv-none-elf-gcc 15.2.0 ($GCC_TAR)?"; then
    mkdir -p "$DL_DIR" "$TOOLCHAIN_ROOT/riscv"
    TARBALL="$DL_DIR/$GCC_TAR"
    [ -f "$TARBALL" ] || curl -sSL -o "$TARBALL" "$GCC_BASE/$GCC_TAR" \
      || fail "download failed: $GCC_BASE/$GCC_TAR"
    WANT="$(gcc_sha_for "$GCC_TAR")"
    if [ -n "$WANT" ]; then
      GOT="$(sha256 "$TARBALL")"
      if [ "$GOT" != "$WANT" ]; then
        fail "gcc tarball sha256 mismatch (got $GOT)"
      else
        log "gcc tarball sha256 verified"
      fi
    else
      log "no pinned hash for $GCC_TAR; trusting TLS + version check below"
    fi
    if [ "$FAILURES" = 0 ]; then
      tar xzf "$TARBALL" -C "$TOOLCHAIN_ROOT/riscv" || fail "extract failed"
      if [ -x "$GCC_BIN" ] && "$GCC_BIN" --version 2>/dev/null | grep -q "15\.2\.0"; then
        ok "riscv-none-elf-gcc 15.2.0 installed"
      else
        fail "gcc install did not produce a working 15.2.0"
      fi
    fi
  else
    fail "riscv-none-elf-gcc 15.2.0 missing"
  fi
fi

# ---------------------------------------------------------------- iverilog 12.x
ivl_ok() { have iverilog && iverilog -V 2>/dev/null | grep -q "version 12\."; }
if ivl_ok; then
  ok "iverilog $(iverilog -V 2>/dev/null | head -1)"
else
  if [ "$OS" = mac ]; then
    confirm "brew install icarus-verilog?" && brew install icarus-verilog >/dev/null 2>&1
  else
    confirm "apt-get install iverilog?" && sudo apt-get install -y -qq iverilog >/dev/null 2>&1
  fi
  if ivl_ok; then
    ok "iverilog $(iverilog -V 2>/dev/null | head -1)"
  else
    log "package iverilog is not 12.x; building v12_0 from source"
    if confirm "build Icarus v12_0 from source (~5 min)?"; then
      if [ "$OS" = mac ]; then
        brew install autoconf bison flex gperf >/dev/null 2>&1 || fail "brew deps failed"
        export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
      else
        sudo apt-get install -y -qq autoconf bison flex gperf >/dev/null 2>&1 || fail "apt deps failed"
      fi
      if [ "$FAILURES" = 0 ]; then
        IVL_SRC="$DL_DIR/iverilog-src"; IVL_PRE="$TOOLCHAIN_ROOT/icarus-12.0"
        IVL_LOG="$DL_DIR/iverilog-build.log"
        [ -d "$IVL_SRC" ] || git clone -q https://github.com/steveicarus/iverilog.git "$IVL_SRC" \
          || fail "iverilog clone failed"
        ( cd "$IVL_SRC" && git checkout -q "$IVL_TAG" && sh autoconf.sh >"$IVL_LOG" 2>&1 \
          && ./configure --prefix="$IVL_PRE" >>"$IVL_LOG" 2>&1 \
          && make -j"$NCPU" >>"$IVL_LOG" 2>&1 && make install >>"$IVL_LOG" 2>&1 ) \
          || { fail "iverilog source build failed (log: $IVL_LOG)"; tail -20 "$IVL_LOG" >&2; }
        export PATH="$IVL_PRE/bin:$PATH"
        ivl_ok && ok "iverilog 12.x built from source ($IVL_PRE/bin)"
      fi
    else
      fail "iverilog 12.x missing (manifest pins 12.0 as primary backend)"
    fi
  fi
fi

# ---------------------------------------------------------------- verilator 5.x
if have verilator && verilator --version 2>/dev/null | grep -qE "Verilator 5\."; then
  ok "verilator $(verilator --version 2>/dev/null)"
else
  if [ "$OS" = mac ]; then
    confirm "brew install verilator?" && brew install verilator >/dev/null 2>&1
  else
    confirm "apt-get install verilator?" && sudo apt-get install -y -qq verilator >/dev/null 2>&1
  fi
  if have verilator && verilator --version 2>/dev/null | grep -qE "Verilator 5\."; then
    ok "verilator $(verilator --version 2>/dev/null)"
  else
    fail "verilator 5.x missing"
  fi
fi

# ---------------------------------------------------------------- yosys 0.33 (source build; pinned)
YOSYS_PRE="$TOOLCHAIN_ROOT/yosys-0.33"
yosys_ok() { have yosys && yosys -V 2>/dev/null | grep -q "Yosys 0\.33"; }
if yosys_ok; then
  ok "yosys $(yosys -V 2>/dev/null | head -1)"
else
  log "yosys 0.33 not on PATH; building from source (~10 min)"
  if confirm "build Yosys 0.33 from source?"; then
    if [ "$OS" = mac ]; then
      brew install bison flex gawk libffi pkg-config >/dev/null 2>&1 || fail "brew deps failed"
      export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
    else
      sudo apt-get install -y -qq bison flex gawk libffi-dev pkg-config tcl-dev >/dev/null 2>&1 \
        || fail "apt deps failed"
    fi
    if [ "$FAILURES" = 0 ]; then
      YS_SRC="$DL_DIR/yosys-src"
      [ -d "$YS_SRC" ] || git clone -q https://github.com/YosysHQ/yosys.git "$YS_SRC" \
        || fail "yosys clone failed"
      YS_LOG="$DL_DIR/yosys-build.log"
      ( cd "$YS_SRC" && git checkout -q "$YOSYS_TAG" \
        && make -j"$NCPU" PREFIX="$YOSYS_PRE" >"$YS_LOG" 2>&1 \
        && make install PREFIX="$YOSYS_PRE" >>"$YS_LOG" 2>&1 ) \
        || { fail "yosys source build failed (log: $YS_LOG)"; tail -20 "$YS_LOG" >&2; }
      export PATH="$YOSYS_PRE/bin:$PATH"
      if have yosys && yosys -V 2>/dev/null | grep -q "Yosys 0\.33"; then
        ok "yosys 0.33 built from source ($YOSYS_PRE/bin)"
      else
        fail "yosys 0.33 build did not produce a working binary"
      fi
    fi
  else
    fail "yosys 0.33 missing (F1 synthesis was qualified on 0.33)"
  fi
fi

# ---------------------------------------------------------------- spike (pinned commit)
SPIKE_PRE="$TOOLCHAIN_ROOT/spike-mcu"
SPIKE_BIN_DEFAULT="$SPIKE_PRE/bin/spike"
spike_ok() { [ -x "${SPIKE_BIN:-$SPIKE_BIN_DEFAULT}" ]; }
if spike_ok; then
  ok "spike (${SPIKE_BIN:-$SPIKE_BIN_DEFAULT})"
else
  log "spike not found; building pinned commit $SPIKE_PIN (~5 min)"
  if confirm "build Spike from source?"; then
    if [ "$OS" = mac ]; then
      brew install dtc >/dev/null 2>&1 || fail "brew dtc failed"
    else
      sudo apt-get install -y -qq device-tree-compiler >/dev/null 2>&1 || fail "apt dtc failed"
    fi
    if [ "$FAILURES" = 0 ]; then
      SP_SRC="$DL_DIR/spike-src"
      [ -d "$SP_SRC" ] || git clone -q https://github.com/riscv/riscv-isa-sim.git "$SP_SRC" \
        || fail "spike clone failed"
      SP_LOG="$DL_DIR/spike-build.log"
      ( cd "$SP_SRC" && git checkout -q "$SPIKE_PIN" && mkdir -p build && cd build \
        && ../configure --prefix="$SPIKE_PRE" >"$SP_LOG" 2>&1 \
        && make -j"$NCPU" >>"$SP_LOG" 2>&1 && make install >>"$SP_LOG" 2>&1 ) \
        || { fail "spike build failed (log: $SP_LOG)"; tail -20 "$SP_LOG" >&2; }
      if [ -x "$SPIKE_BIN_DEFAULT" ]; then
        ok "spike built ($SPIKE_BIN_DEFAULT)"
      else
        fail "spike build did not produce $SPIKE_BIN_DEFAULT"
      fi
    fi
  else
    fail "spike missing (A1/A2 golden signatures need it)"
  fi
fi

# ---------------------------------------------------------------- Nangate45 PDK (F1)
PDK_LIB="$PDK_DIR/NangateOpenCellLibrary_typical.lib"
if [ -f "$PDK_LIB" ] && [ "$(sha256 "$PDK_LIB")" = "$PDK_LIB_SHA" ]; then
  ok "Nangate45 typical.lib (sha256 verified)"
else
  log "Nangate45 liberty missing or hash mismatch; trying public mirror"
  if confirm "download NangateOpenCellLibrary_typical.lib (6.7 MB)?"; then
    mkdir -p "$PDK_DIR"
    curl -sSL -o "$PDK_LIB" "$PDK_URL" || fail "PDK download failed"
    if [ -f "$PDK_LIB" ] && [ "$(sha256 "$PDK_LIB")" = "$PDK_LIB_SHA" ]; then
      ok "Nangate45 typical.lib downloaded + sha256 verified"
    else
      rm -f "$PDK_LIB"
      fail "PDK mirror hash mismatch; fetch it manually into $PDK_DIR (sha256 must be $PDK_LIB_SHA)"
    fi
  else
    fail "Nangate45 liberty missing at $PDK_LIB (F1 synthesis needs it)"
  fi
fi

# ---------------------------------------------------------------- activate.sh
# (printf keeps the ${VAR:-default} expansions literal in the output file)
{
  echo "# Generated by env/setup.sh -- source before running the suite:"
  echo "#   source env/activate.sh"
  echo "export TOOLCHAIN_ROOT=\"$TOOLCHAIN_ROOT\""
  echo "export TOOLCHAIN=\"$TOOLCHAIN_ROOT/riscv/$GCC_TAG/bin\""
  echo "export PDK_DIR=\"$PDK_DIR\""
  echo 'export SPIKE_BIN="${SPIKE_BIN:-'"$SPIKE_BIN_DEFAULT"'}"'
  echo "export PATH=\"$TOOLCHAIN_ROOT/yosys-0.33/bin:$TOOLCHAIN_ROOT/icarus-12.0/bin:$TOOLCHAIN_ROOT/spike-mcu/bin:\$PATH\""
} > env/activate.sh
log "wrote env/activate.sh"

# ---------------------------------------------------------------- summary
echo
if [ "$FAILURES" = 0 ]; then
  log "ALL OK — activate and run:"
  echo "    cd $ROOT && source env/activate.sh && make acceptance"
else
  fail "$FAILURES item(s) still missing — resolve the FAIL lines above, then re-run."
  exit 1
fi

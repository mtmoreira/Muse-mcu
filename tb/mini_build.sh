#!/bin/bash
# Build a Phase-3a mini-program: tb/prog_<name>.S -> tb/build/<name>.elf -> tb/build/<name>.hex
# Usage: mini_build.sh <name>
set -euo pipefail
NAME="$1"
MMCU="${MMCU:-$HOME/workspace/Muse-mcu}"
TC="$HOME/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
mkdir -p "$MMCU/tb/build"
"$TC/riscv-none-elf-gcc" -march=rv32i_zicsr -mabi=ilp32 -T "$MMCU/tb/mini.ld" \
  -nostdlib -nostartfiles -Wl,--no-relax \
  -o "$MMCU/tb/build/$NAME.elf" "$MMCU/tb/prog_$NAME.S"
python3 "$MMCU/tb/elf2hex.py" "$MMCU/tb/build/$NAME.elf" "$MMCU/tb/build/$NAME.hex" \
  "$TC/riscv-none-elf-objcopy"

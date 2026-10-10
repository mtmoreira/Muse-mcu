#!/usr/bin/env bash
# fw/build.sh — build all Muse MCU firmware images.
#
# Self-contained: if TOOLCHAIN is unset, sources env/activate.sh
# (written by env/setup.sh). Builds fw/build/<app>.{elf,hex} for every
# app in APPS via fw/Makefile.
#
# Usage: bash fw/build.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${TOOLCHAIN:-}" ] && [ -f "$ROOT/env/activate.sh" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/env/activate.sh"
fi
if [ -z "${TOOLCHAIN:-}" ] || [ ! -x "$TOOLCHAIN/riscv-none-elf-gcc" ]; then
  echo "build.sh: no working RISC-V toolchain (run env/setup.sh first)" >&2
  exit 1
fi

APPS="hello uart_rx_test spi_test timer_gpio_test pingpong rtos_regtest rtos_queue rtos_sema rtos_notify rtos_timer rtos_isr rtos_blocktim preempt_test app_demo"

FAIL=0
for a in $APPS; do
  echo "build.sh: APP=$a"
  if ! make -C "$ROOT/fw" APP="$a"; then FAIL=1; fi
done

if [ "$FAIL" != 0 ]; then echo "build.sh: FAIL"; exit 1; fi
echo "build.sh: ALL OK ($(echo "$APPS" | wc -w | tr -d ' ') apps)"

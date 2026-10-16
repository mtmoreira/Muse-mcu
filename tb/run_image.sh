#!/bin/bash
# tb/run_image.sh — build & run tb_image (visual demo).
# Usage: bash tb/run_image.sh --flash <flash.hex> --outdir <dir> [--fault 0|1]
# Buffer addresses are resolved from the firmware ELF (nm), never guessed.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FLASH=""; OUTDIR=""; FAULT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --flash) FLASH="$2"; shift 2;;
    --outdir) OUTDIR="$2"; shift 2;;
    --fault) FAULT="$2"; shift 2;;
    *) echo "run_image: unknown arg $1" >&2; exit 2;;
  esac
done
[ -n "$FLASH" ] && [ -n "$OUTDIR" ] || { echo "run_image: need --flash and --outdir" >&2; exit 2; }
TC=${TOOLCHAIN_ROOT:-$HOME/work/toolchains}/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
[ -x "$TC/riscv-none-elf-nm" ] || TC="$HOME/workspace/toolchains/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
FW_HEX="fw/build/image_demo.hex"
FW_ELF="fw/build/image_demo.elf"
[ -f "$FW_HEX" ] || { echo "run_image: FAIL: $FW_HEX missing (build firmware first)" >&2; exit 1; }
mkdir -p "$OUTDIR" build/tb_out

addr_of() {
  "$TC/riscv-none-elf-nm" --print-size "$FW_ELF" | awk -v s="$1" '$4==s {print $1}'
}
IN_BASE=$(addr_of img_in); GX_BASE=$(addr_of img_gx)
GY_BASE=$(addr_of img_gy); OUT_BASE=$(addr_of img_out)
[ -n "$IN_BASE" ] && [ -n "$OUT_BASE" ] || { echo "run_image: FAIL: buffer symbols not found" >&2; exit 1; }
cat > "$OUTDIR/symbols.json" <<EOF
{"img_in": "0x$IN_BASE", "img_gx": "0x$GX_BASE", "img_gy": "0x$GY_BASE", "img_out": "0x$OUT_BASE",
 "elf": "$FW_ELF"}
EOF
echo "run_image: buffers in=0x$IN_BASE gx=0x$GX_BASE gy=0x$GY_BASE out=0x$OUT_BASE fault=$FAULT"
echo "run_image: iverilog tb_image"
iverilog -g2012 -o build/tb_out/tb_image.vvp \
  tb/tb_image.sv tb/uart_sink.sv third_party/picosoc_spiflash/spiflash.v rtl/*.sv || exit 1
echo "run_image: vvp tb_image (outdir $OUTDIR)"
timeout 3600 vvp build/tb_out/tb_image.vvp \
  "+hex=$FW_HEX" "+firmware=$FLASH" "+outdir=$OUTDIR" \
  "+in_base=$IN_BASE" "+gx_base=$GX_BASE" "+gy_base=$GY_BASE" "+out_base=$OUT_BASE" \
  "+fault=$FAULT" 2>&1 | tee "$OUTDIR/tb_console.log"
rc=${PIPESTATUS[0]}
echo "run_image: vvp exit code = $rc"
grep -q "TB_IMAGE: PROTOCOL PASS" "$OUTDIR/tb_console.log" || { echo "run_image: FAIL: protocol did not pass"; exit 1; }
echo "run_image: PASS (protocol)"

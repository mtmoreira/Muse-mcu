#!/bin/bash
# Build one stub firmware: build.sh <name> <srcs...>
set -e
TC=~/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
D=~/workspace/Muse-mcu/tb/stub_fw
mkdir -p $D/build
name="$1"; shift
$TC/riscv-none-elf-gcc -march=rv32izicsr -mabi=ilp32 -Os -ffreestanding -nostdlib \
  -T $D/link.ld -o $D/build/$name.elf $D/crt0.S "$@" -lgcc
$TC/riscv-none-elf-objcopy -O binary $D/build/$name.elf $D/build/$name.bin
python3 - "$D/build/$name.bin" "$D/build/$name.hex" <<'EOF'
import sys
data = open(sys.argv[1],'rb').read()
assert len(data) <= 65536, f"ROM image too big: {len(data)}"
data = data + b'\x00' * (65536 - len(data))
with open(sys.argv[2],'w') as f:
    for i in range(0, 65536, 4):
        w = int.from_bytes(data[i:i+4], 'little')
        f.write(f"{w:08x}\n")
EOF
echo "built $D/build/$name.hex"

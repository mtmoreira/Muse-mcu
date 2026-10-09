# Running the acceptance suite on macOS

Tested target: Apple Silicon Mac (darwin-arm64). Intel Mac works too,
pick the `darwin-x64` xPack tarball in step 3.

All repo paths below are relative to the clone. The suite no longer
contains hardcoded Linux paths: tool locations resolve via `$PATH` and
the env vars `TOOLCHAIN`, `SPIKE_BIN`, `VLT_BIN`, `PDK_DIR`.

## 1. Clone

```bash
mkdir -p /Users/matheustrev/work && cd /Users/matheustrev/work
git clone https://github.com/mtmoreira/Muse-mcu.git
cd Muse-mcu
git checkout work/mcu-acceptance-v1
```

## 2. Homebrew tools

```bash
brew install icarus-verilog verilator device-tree-compiler python3
pip3 install pyyaml
```

Check the Icarus version: `iverilog -V` must report **12.x** (the
manifest pins Icarus 12.0 as the primary backend). If Homebrew ships a
newer major, build v12_0 from source:

```bash
git clone https://github.com/steveicarus/iverilog.git
cd iverilog && git checkout v12_0
sh autoconf.sh && ./configure --prefix=$HOME/workspace/toolchains/icarus-12.0
make -j$(sysctl -n hw.ncpu) && make install
export PATH=$HOME/workspace/toolchains/icarus-12.0/bin:$PATH
```

## 3. RISC-V GCC 15.2.0 (xPack)

```bash
mkdir -p ~/workspace/toolchains/riscv && cd ~/workspace/toolchains/riscv
# Apple Silicon:
curl -LO https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-darwin-arm64.tar.gz
# Intel Mac: use ...-darwin-x64.tar.gz instead
tar xzf xpack-riscv-none-elf-gcc-15.2.0-1-darwin-*.tar.gz
export TOOLCHAIN=$HOME/workspace/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
$TOOLCHAIN/riscv-none-elf-gcc --version   # expect 15.2.0
```

## 4. Yosys 0.33 (F1 synthesis fidelity)

Homebrew's Yosys is much newer; the F1 gate was qualified on 0.33,
so build that tag from source:

```bash
brew install bison flex gawk libffi
git clone https://github.com/YosysHQ/yosys && cd yosys
git checkout yosys-0.33
make -j$(sysctl -n hw.ncpu) && sudo make install
yosys -V   # expect 0.33
```

## 5. Spike (A1/A2 golden signatures)

```bash
git clone https://github.com/riscv/riscv-isa-sim && cd riscv-isa-sim
git checkout e448970b1668f7893f88e54824e1387a3e5fe09b
mkdir build && cd build
../configure --prefix=$HOME/workspace/toolchains/spike-mcu
make -j$(sysctl -n hw.ncpu) && make install
export SPIKE_BIN=$HOME/workspace/toolchains/spike-mcu/bin/spike
```

## 6. Nangate45 PDK (F1 synthesis only)

The suite needs `NangateOpenCellLibrary_typical.lib` at
`$PDK_DIR` (default `~/workspace/pdk-dl/nangate45`). It ships with
OpenROAD's platform files; verify the hash after download:

```bash
mkdir -p ~/workspace/pdk-dl/nangate45 && cd ~/workspace/pdk-dl/nangate45
# fetch NangateOpenCellLibrary_typical.lib from a public mirror, e.g.
# the nangate45 platform dir of OpenROAD-flow-scripts, then:
shasum -a 256 NangateOpenCellLibrary_typical.lib
# expect 8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1
```

## 7. Run

```bash
cd /Users/matheustrev/work/Muse-mcu
export TOOLCHAIN=$HOME/workspace/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin
export SPIKE_BIN=$HOME/workspace/toolchains/spike-mcu/bin/spike
# (add the icarus-12.0 PATH export here too if you built it from source)
make acceptance
```

A full run takes several hours (the long Verilator gates dominate).
For a quick smoke test: `python3 tools/run_acceptance.py --smoke`.

## Notes / known differences vs the Linux reference run

- Verilator from Homebrew will be newer than 5.032. That is fine: the
  backend version is recorded per-gate in `results/*.json`; it is the
  same RTL, firmware, and checkers.
- Icarus must be 12.x; newer majors are untested with these testbenches.
- `results/raw/` and `tb/logs/` are gitignored build artifacts; only
  `results/*.json`, `results/*.md`, and the figures are committed.

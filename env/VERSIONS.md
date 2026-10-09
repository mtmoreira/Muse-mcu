# Muse MCU — pinned tool versions (Phase 0, 2026-10-08)

Recorded by `env/bootstrap.sh` Phase 0 provisioning on the reference VM.
`source` = where the tool came from; `sha256` = tarball/lib hash where pinned.

| tool | version | source | sha256 |
|------|---------|--------|--------|
| riscv-none-elf-gcc | 15.2.0 (xPack GNU RISC-V Embedded GCC x86_64) | xpack-dev-tools release asset `xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz` (`.../releases/download/v15.2.0-1/...`) | `aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758` |
| Icarus Verilog | 12.0 (stable), package `12.0-2build2` | Ubuntu 24.04 apt (`/usr/bin/iverilog`); apt offered 12.x so no source build was needed | n/a (distro package) |
| Yosys | 0.33 (git sha1 2584903a060) | Ubuntu 24.04 apt (`/usr/bin/yosys`) | n/a (distro package) |
| device-tree-compiler | DTC 1.7.0, package `1.7.0-2build1` | Ubuntu 24.04 apt (`/usr/bin/dtc`) | n/a (distro package) |
| Nangate45 typical lib | NangateOpenCellLibrary_typical.lib | local, `~/workspace/pdk-dl/nangate45/` | `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1` |
| Nangate45 macro LEF | NangateOpenCellLibrary.macro.lef | local, `~/workspace/pdk-dl/nangate45/` | `840b01e500826096d1edcc752350834da647fdbf360798f243f8122b52b357c3` |
| Nangate45 tech LEF | NangateOpenCellLibrary.tech.lef | local, `~/workspace/pdk-dl/nangate45/` | `834a79295054cd4209178d1bade67c353863c47bb4b3c22ee38b862b7cec37f2` |
| Python | 3.12.3 (>=3.10 required) | Ubuntu 24.04 system python3 | n/a |

Install paths (reference VM, 2026-10-08):
- gcc: `~/workspace/building-ai-computer/toolchains/riscv/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc`
- yosys: `/usr/bin/yosys`
- iverilog: `/usr/bin/iverilog` (smoke-tested: compiles and runs a Verilog testbench)
- dtc: `/usr/bin/dtc` (smoke-tested: compiles a DTS to DTB)
- icarus source fallback: not used (apt provided 12.x)

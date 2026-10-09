# synth/ — F1 open-source synthesis

## Blackbox policy (declared per manifest F1)

`synth/mcu.ys` synthesizes the **full platform** (`mcu_top`: RV32I CPU +
bus + CLINT + GPIO + UART0 + SPI0) with Yosys 0.33 against the Nangate45
typical liberty.

- **Blackboxed (declared): `bootrom`, `sram`.** These are the SRAM/ROM
  behavioral models the manifest allows. They are converted with the Yosys
  `blackbox` command *before* `synth`, so their 16Kx32 / 32Kx32 arrays are
  never mapped to flip-flops. Their empty stubs are written to
  `synth/mcu_blackboxes.v` (`write_verilog -blackboxes`).
- **Everything else — the CPU and every peripheral — is mapped to standard
  cells.** `run_synth.sh` audits the `-blackboxes` artifact and fails the
  gate (nonzero exit) if the blackbox set is anything other than exactly
  `{bootrom, sram}`. It also verifies every instantiated cell type in
  `synth/mcu_netlist.v` resolves to a netlist module, a liberty cell, or one
  of the two declared macros.

## Gate-level simulation (F2/F3)

Gate sims are **zero-delay** (this is labeled in every gate log/report;
timing closure is out of scope per the manifest). For simulation, the
behavioral memory models are substituted for the blackbox stubs:

- `synth/mcu_netlist.v` (mapped logic; instantiates `bootrom`/`sram`)
- `rtl/bootrom.sv`, `rtl/sram.sv` (the declared behavioral models — the same
  files the testbenches backdoor-load with `$readmemh`)
- `synth/nangate45_cells.v` (zero-delay functional models of the liberty
  cells, auto-generated from the pinned liberty by `synth/gen_cells.py`)

`tb/run_gate_app.sh` and `tb/run_gate_preempt.sh` build the gate sim with
exactly this file set (plus the testbench and its models).

## Files

| File | Purpose |
|------|---------|
| `mcu.ys` | Yosys 0.33 synthesis script (F1 checker) |
| `run_synth.sh` | driver: runs the script, audits blackboxes, records evidence |
| `gen_cells.py` | generates `nangate45_cells.v` from the pinned liberty |
| `nangate45_cells.v` | generated zero-delay cell models (for gate sim only) |
| `mcu_netlist.v` | mapped gate netlist (committed, sha256 in `results/`) |
| `mcu_blackboxes.v` | empty stubs for the two declared macros (committed) |

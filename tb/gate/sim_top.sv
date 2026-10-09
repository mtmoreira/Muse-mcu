// tb/gate/sim_top.sv — Verilator top for F2/F3 gate-level runs.
//
// Instantiates the synthesized netlist (mcu_top) with the declared behavioral
// memory models. The C++ harness drives clk/rst/tb_irq/spi_miso and samples
// uart_tx.
//
// The SPI flash is modeled in the C++ harness (0xAB wake, 0x03 READ, mode 0,
// MSB-first), functionally equivalent to the qualified spiflash.v model for
// the transactions the firmware performs. (spiflash.v uses `assign #1`
// delays, which Verilator cannot compile; the RTL Icarus runs use the
// qualified Verilog model unmodified.)
//
// Firmware image loaded via plusarg: +hex=<app.hex> (32-bit words, one per
// line, into dut.rom.mem).
//
// This is a ZERO-DELAY gate simulation: Verilator is cycle-based and models
// no timing arcs. Timing closure is out of scope per the manifest.
`timescale 1ns/1ps

module sim_top (
  input  logic        clk,
  input  logic        rst,
  input  logic        tb_irq,
  input  logic        spi_miso,
  output logic        uart_tx,
  output logic        spi_sck,
  output logic        spi_mosi,
  output logic        spi_cs_n,
  output logic [31:0] dbg_pc,
  output logic        dbg_instr_valid,
  output logic        dbg_trap_taken,
  output logic [31:0] dbg_mcause
);

  string hex_path;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(uart_tx), .uart_rx(1'b1),
    .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n),
    .gpio_in(8'h00), .gpio_out(), .gpio_oe(),
    .tb_test_irq(tb_irq),
    .dbg_pc(dbg_pc), .dbg_instr_valid(dbg_instr_valid),
    .dbg_trap_taken(dbg_trap_taken), .dbg_mcause(dbg_mcause)
  );

  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("SIM_TOP: FATAL: +hex=<file> plusarg missing");
      $finish;
    end
    $readmemh(hex_path, dut.rom.mem);
    $display("SIM_TOP: loaded ROM %s", hex_path);
  end

endmodule

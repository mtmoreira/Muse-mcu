// tb/rtl_vlt/sim_top_rtl.sv — Verilator top for RTL (non-gate) runs.
//
// Instantiates the fresh RTL mcu_top (not the synthesized netlist).
// Firmware image loaded via plusarg: +hex=<app.hex> (32-bit words, one per
// line, into dut.rom.mem).
//
// Backend: Verilator (recorded per manifest "per-run backend recorded").
// The manifest's primary simulator is Icarus 12.0; Verilator is used for
// gates whose cycle budget exceeds Icarus throughput (A9: 50M+ cycles,
// B5: ~27M+ cycles). Same RTL, same firmware, same checkers.
`timescale 1ns/1ps

module sim_top_rtl (
  input  logic        clk,
  input  logic        rst,
  input  logic        tb_irq,
  input  logic        spi_miso,
  input  logic [7:0]  gpio_in,
  output logic        uart_tx,
  output logic        spi_sck,
  output logic        spi_mosi,
  output logic        spi_cs_n,
  output logic [7:0]  gpio_out,
  output logic [7:0]  gpio_oe,
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
    .gpio_in(gpio_in), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .tb_test_irq(tb_irq),
    .dbg_pc(dbg_pc), .dbg_instr_valid(dbg_instr_valid),
    .dbg_trap_taken(dbg_trap_taken), .dbg_mcause(dbg_mcause)
  );

  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("SIM_TOP_RTL: FATAL: +hex=<file> plusarg missing");
      $finish;
    end
    $readmemh(hex_path, dut.rom.mem);
    $display("SIM_TOP_RTL: loaded ROM %s", hex_path);
  end

endmodule

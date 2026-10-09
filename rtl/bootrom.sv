// Muse MCU — bootrom
// 16384 x 32-bit boot ROM, combinational read on two independent read ports
// (the bus serves the CPU fetch and data ports in the same cycle, so the ROM
// exposes one read port per CPU port). Testbench backdoor: the testbench loads
// the firmware image hierarchically, e.g.
//   string h; $value$plusargs("hex=%s", h); $readmemh(h, dut.rom.mem);
// (32-bit words, one per line). The initial/$value$plusargs form is deliberately
// NOT in this file: Yosys 0.33 (the pinned synth tool) cannot parse `string` or
// $value$plusargs, so this module stays synth-clean; the backdoor lives in tb.

module bootrom (
  input  logic [13:0] if_addr,
  output logic [31:0] if_rdata,
  input  logic [13:0] d_addr,
  output logic [31:0] d_rdata
);

  logic [31:0] mem [0:16383];

  assign if_rdata = mem[if_addr];
  assign d_rdata  = mem[d_addr];

endmodule

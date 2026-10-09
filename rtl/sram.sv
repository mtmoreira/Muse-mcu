// Muse MCU — sram
// 32768 x 32-bit SRAM (128 KiB). Combinational read on two independent read
// ports (one per CPU port, served in the same cycle) and one synchronous
// write port with per-byte write strobes. Writes take effect on the rising
// clock edge; reads are combinational. The array has no reset (contents are
// undefined until written, as on real SRAM).

module sram (
  input  logic        clk,
  input  logic [14:0] if_addr,
  output logic [31:0] if_rdata,
  input  logic [14:0] d_raddr,
  output logic [31:0] d_rdata,
  input  logic [14:0] d_waddr,
  input  logic [31:0] d_wdata,
  input  logic [3:0]  d_wstrb
);

  logic [31:0] mem [0:32767];

  assign if_rdata = mem[if_addr];
  assign d_rdata  = mem[d_raddr];

  always_ff @(posedge clk) begin
    if (d_wstrb[0]) mem[d_waddr][7:0]   <= d_wdata[7:0];
    if (d_wstrb[1]) mem[d_waddr][15:8]  <= d_wdata[15:8];
    if (d_wstrb[2]) mem[d_waddr][23:16] <= d_wdata[23:16];
    if (d_wstrb[3]) mem[d_waddr][31:24] <= d_wdata[31:24];
  end

endmodule

// Muse MCU — gpio
// Base 0x10010000, 4 KiB region.
//   data_in    @0x0  RO: live pin levels (combinational from gpio_in)
//   data_out   @0x4  RW: output drive values (low byte)
//   dir        @0x8  RW: direction, 1=output (low byte)
//   dbg_scratch@0xC  RW: 32-bit test-observation register
//   irq_status @0x10 W1C: bit0 set on any gpio_in edge, cleared by writing 1
// gpio_oe = dir, gpio_out = data_out. gpio_irq = irq_status[0] (sticky until
// cleared). Input pins are double-synchronized; an edge is any change of any
// synchronized input bit.

module gpio (
  input  logic        clk,
  input  logic        rst,     // synchronous, active-high
  input  logic        we,      // MMIO write strobe for this peripheral
  input  logic [15:0] off,     // byte offset within the GPIO region
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata,
  input  logic [7:0]  gpio_in,
  output logic [7:0]  gpio_out,
  output logic [7:0]  gpio_oe,
  output logic        gpio_irq
);

  logic [7:0]  data_out_q;
  logic [7:0]  dir_q;
  logic [31:0] scratch_q;
  logic        irq_status_q;
  logic [7:0]  in_s1, in_s2;
  logic [31:0] wmask;
  logic        edge_any, w_clr;

  assign wmask = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};

  // Combinational read decode (data_in reads the live pins)
  always_comb begin
    rdata = 32'h00000000;
    case (off)
      16'h0000: rdata = {24'h000000, gpio_in};
      16'h0004: rdata = {24'h000000, data_out_q};
      16'h0008: rdata = {24'h000000, dir_q};
      16'h000C: rdata = scratch_q;
      16'h0010: rdata = {31'h0000000, irq_status_q};
      default:  rdata = 32'h00000000;
    endcase
  end

  // Input synchronizer + edge detect. During reset the synchronizer follows
  // the pins, so no phantom edge is reported at reset release when pins are
  // strapped high.
  always_ff @(posedge clk) begin
    if (rst) begin
      in_s1 <= gpio_in;
      in_s2 <= gpio_in;
    end else begin
      in_s1 <= gpio_in;
      in_s2 <= in_s1;
    end
  end
  assign edge_any = |(in_s1 ^ in_s2);

  // W1C clear of irq_status[0]
  assign w_clr = we && (off == 16'h0010) && wstrb[0] && wdata[0];

  always_ff @(posedge clk) begin
    if (rst) begin
      data_out_q   <= 8'h00;
      dir_q        <= 8'h00;
      scratch_q    <= 32'h00000000;
      irq_status_q <= 1'b0;
    end else begin
      if (we && (off == 16'h0004) && wstrb[0]) data_out_q <= wdata[7:0];
      if (we && (off == 16'h0008) && wstrb[0]) dir_q      <= wdata[7:0];
      if (we && (off == 16'h000C)) scratch_q <= (scratch_q & ~wmask) | (wdata & wmask);
      // An edge in the same cycle as a W1C clear wins (event is not lost).
      irq_status_q <= edge_any ? 1'b1 : (w_clr ? 1'b0 : irq_status_q);
    end
  end

  assign gpio_out = data_out_q;
  assign gpio_oe  = dir_q;
  assign gpio_irq = irq_status_q;

endmodule

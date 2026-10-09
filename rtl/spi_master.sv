// Muse MCU — spi_master (SPI0)
// Base 0x10030000, 4 KiB region.
//   ctrl    @0x0  RW: bit0 go (write 1 to start; auto-clears, reads as 0)
//   status  @0x4  RO: bit0 busy; bit1 done_sticky (W1C)
//   txdata  @0x8  RW: byte to transmit
//   rxdata  @0xC  RO: byte received by the last completed transfer
//   cs      @0x10 RW: bit0 directly drives spi_cs_n (software chip-select)
//   clkdiv  @0x14 RW: half-period divider; reset 16
// SPI mode 0 (CPOL=0, CPHA=0), MSB-first. Writing ctrl.go=1 while idle
// latches txdata and shifts 8 bits: MOSI is driven from the falling edge of
// SCK, MISO is sampled on the rising edge of SCK, and the SCK period is
// 2*clkdiv clock cycles. At completion: busy=0, done_sticky=1, rxdata holds
// the received byte, and spi_done pulses for one cycle. A go written while
// busy is ignored. done_sticky is cleared by writing 1 to status[1].

module spi_master (
  input  logic        clk,
  input  logic        rst,     // synchronous, active-high
  input  logic        we,      // MMIO write strobe for this peripheral
  input  logic [15:0] off,     // byte offset within the SPI region
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata,
  output logic        spi_sck,
  output logic        spi_mosi,
  input  logic        spi_miso,
  output logic        spi_cs_n,
  output logic        spi_done  // 1-cycle pulse at transfer completion
);

  logic [7:0]  txdata_q, rxdata_q;
  logic        cs_q;
  logic [15:0] clkdiv_q;
  logic        busy_q, done_sticky_q, done_q;
  logic [7:0]  shreg_q;
  logic [3:0]  edges_q;  // half-period edges elapsed: 0..15 (8 rising + 8 falling)
  logic [15:0] hc_q;     // half-period countdown
  logic        sck_q, mosi_q;
  logic        miso_s1, miso_s2; // input synchronizer

  logic [15:0] div_eff;
  logic        go;

  // Half period is div_eff cycles => SCK period is 2*div_eff cycles.
  // clkdiv < 2 is clamped to 2 (SCK can never be faster than clk/4).
  assign div_eff = (clkdiv_q < 16'd2) ? 16'd2 : clkdiv_q;
  assign go      = we && (off == 16'h0000) && wstrb[0] && wdata[0] && !busy_q;

  // Combinational read decode (ctrl.go auto-clears: reads as 0)
  always_comb begin
    rdata = 32'h00000000;
    case (off)
      16'h0000: rdata = 32'h00000000;
      16'h0004: rdata = {30'h00000000, done_sticky_q, busy_q};
      16'h0008: rdata = {24'h000000, txdata_q};
      16'h000C: rdata = {24'h000000, rxdata_q};
      16'h0010: rdata = {31'h0000000, cs_q};
      16'h0014: rdata = {16'h0000, clkdiv_q};
      default:  rdata = 32'h00000000;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      txdata_q     <= 8'h00;
      rxdata_q     <= 8'h00;
      cs_q         <= 1'b1; // deselected
      clkdiv_q     <= 16'd16;
      busy_q       <= 1'b0;
      done_sticky_q<= 1'b0;
      done_q       <= 1'b0;
      shreg_q      <= 8'h00;
      edges_q      <= 4'd0;
      hc_q         <= 16'd0;
      sck_q        <= 1'b0; // CPOL=0: idle low
      mosi_q       <= 1'b0;
      miso_s1      <= 1'b0;
      miso_s2      <= 1'b0;
    end else begin
      done_q <= 1'b0; // default: single-cycle pulse

      // MISO input synchronizer (sampled on SCK rising edges below)
      miso_s1 <= spi_miso;
      miso_s2 <= miso_s1;

      // Register writes
      if (we && (off == 16'h0008) && wstrb[0]) txdata_q <= wdata[7:0];
      if (we && (off == 16'h0010) && wstrb[0]) cs_q     <= wdata[0];
      if (we && (off == 16'h0014)) begin
        if (wstrb[0]) clkdiv_q[7:0]  <= wdata[7:0];
        if (wstrb[1]) clkdiv_q[15:8] <= wdata[15:8];
      end
      // W1C clear of done_sticky (a completion in the same cycle re-sets it;
      // the set below is ordered after this clear so no event is lost).
      if (we && (off == 16'h0004) && wstrb[0] && wdata[1])
        done_sticky_q <= 1'b0;

      if (!busy_q) begin
        if (go) begin
          busy_q  <= 1'b1;
          shreg_q <= txdata_q;
          mosi_q  <= txdata_q[7]; // MSB first, stable before first rising SCK
          sck_q   <= 1'b0;
          edges_q <= 4'd0;
          hc_q    <= div_eff - 16'd1;
        end
      end else if (hc_q == 16'd0) begin
        hc_q  <= div_eff - 16'd1;
        sck_q <= ~sck_q;
        if (sck_q == 1'b0) begin
          // Rising edge (CPHA=0): sample synchronized MISO, shift left.
          shreg_q <= {shreg_q[6:0], miso_s2};
        end else begin
          // Falling edge: present the next MOSI bit (shreg[7] already holds
          // the next transmit bit after the last rising-edge shift).
          mosi_q <= shreg_q[7];
        end
        if (edges_q == 4'd15) begin
          // 16th edge is the final falling edge: SCK back to idle low,
          // all 8 MISO bits already shifted into shreg_q.
          busy_q        <= 1'b0;
          done_sticky_q <= 1'b1;
          done_q        <= 1'b1;
          rxdata_q      <= shreg_q;
        end else begin
          edges_q <= edges_q + 4'd1;
        end
      end else begin
        hc_q <= hc_q - 16'd1;
      end
    end
  end

  assign spi_sck  = sck_q;
  assign spi_mosi = mosi_q;
  assign spi_cs_n = cs_q;
  assign spi_done = done_q;

endmodule

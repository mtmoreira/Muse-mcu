// Muse MCU — clint (core-local interruptor)
// Base 0x10000000, 64 KiB region.
//   msip     @0x0    bit0 RW (machine software interrupt pending)
//   mtimecmp @0x4000 64-bit RW (two 32-bit halves @0x4000/@0x4004)
//   mtime    @0xBFF8 64-bit RW (two 32-bit halves @0xBFF8/@0xBFFC),
//                      free-running, +1 every clock cycle
// All register writes are byte-strobe aware. A write to either mtime half
// replaces that half for the cycle (the +1 increment is skipped that cycle).
// MTI (irq_timer) = (mtime >= mtimecmp). MSI (irq_sw) = msip[0].
// mtimecmp resets to all-ones so no timer interrupt is pending before
// firmware programs it.

module clint (
  input  logic        clk,
  input  logic        rst,     // synchronous, active-high
  input  logic        we,      // MMIO write strobe for this peripheral
  input  logic [15:0] off,     // byte offset within the CLINT region
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata,
  output logic        irq_timer, // MTI
  output logic        irq_sw     // MSI
);

  logic [31:0] msip_q;
  logic [63:0] mtimecmp_q;
  logic [63:0] mtime_q;
  logic [31:0] wmask;

  assign wmask = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};

  // Combinational read decode
  always_comb begin
    rdata = 32'h00000000;
    case (off)
      16'h0000: rdata = msip_q;
      16'h4000: rdata = mtimecmp_q[31:0];
      16'h4004: rdata = mtimecmp_q[63:32];
      16'hBFF8: rdata = mtime_q[31:0];
      16'hBFFC: rdata = mtime_q[63:32];
      default:  rdata = 32'h00000000;
    endcase
  end

  logic w_msip, w_cmp_lo, w_cmp_hi, w_time_lo, w_time_hi;
  assign w_msip    = we && (off == 16'h0000);
  assign w_cmp_lo  = we && (off == 16'h4000);
  assign w_cmp_hi  = we && (off == 16'h4004);
  assign w_time_lo = we && (off == 16'hBFF8);
  assign w_time_hi = we && (off == 16'hBFFC);

  always_ff @(posedge clk) begin
    if (rst) begin
      msip_q     <= 32'h00000000;
      mtimecmp_q <= 64'hFFFF_FFFF_FFFF_FFFF;
      mtime_q    <= 64'h0000000000000000;
    end else begin
      if (w_msip)    msip_q <= (msip_q & ~wmask) | (wdata & wmask);
      if (w_cmp_lo)  mtimecmp_q[31:0]  <= (mtimecmp_q[31:0]  & ~wmask) | (wdata & wmask);
      if (w_cmp_hi)  mtimecmp_q[63:32] <= (mtimecmp_q[63:32] & ~wmask) | (wdata & wmask);
      if (w_time_lo || w_time_hi) begin
        if (w_time_lo) mtime_q[31:0]  <= (mtime_q[31:0]  & ~wmask) | (wdata & wmask);
        if (w_time_hi) mtime_q[63:32] <= (mtime_q[63:32] & ~wmask) | (wdata & wmask);
      end else begin
        mtime_q <= mtime_q + 64'd1;
      end
    end
  end

  assign irq_timer = (mtime_q >= mtimecmp_q);
  assign irq_sw    = msip_q[0];

endmodule

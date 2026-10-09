// Muse MCU — uart (UART0)
// Base 0x10020000, 4 KiB region.
//   txdata  @0x0 WO: push a byte for transmit (accepted when !tx_full)
//   rxdata  @0x4 RO: pop the received byte (a read clears rx_empty)
//   status  @0x8 RO: bit0 tx_full, bit1 rx_empty, bit2 tx_busy
//   bauddiv @0xC RW: clocks per bit; reset 434 (115200 baud at 50 MHz)
// 8N1 on both directions. TX has a one-byte holding register in front of the
// shift register, so one byte can be queued while another shifts out.
// RX is a single-byte buffer: each completed frame sets rx_empty=0 and emits
// a one-cycle uart_rx_ready pulse (a new frame overwrites an unread byte).
// uart_rx is double-synchronized; the start bit is detected on a falling
// edge and data bits are sampled at bit centers using bauddiv.

module uart (
  input  logic        clk,
  input  logic        rst,     // synchronous, active-high
  input  logic        we,      // MMIO write strobe for this peripheral
  input  logic [15:0] off,     // byte offset within the UART region
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata,
  input  logic        rx_pop,  // strobe: CPU read of rxdata
  output logic        uart_tx,
  input  logic        uart_rx,
  output logic        uart_rx_ready // 1-cycle pulse when a byte is received
);

  logic [15:0] bauddiv_q;

  // TX state
  logic [7:0]  tx_hold_q;
  logic        tx_hold_v;
  logic [9:0]  tx_shift_q;   // {stop, d7..d0, start}
  logic        tx_busy_q;
  logic [3:0]  tx_bitcnt_q;  // 0..9
  logic [15:0] tx_cnt_q;

  // RX state
  logic        rx_s1, rx_s2;
  logic        rx_busy_q;
  logic [3:0]  rx_bitcnt_q;  // samples taken: 0..7 data, 8 = stop
  logic [15:0] rx_cnt_q;
  logic [7:0]  rx_shift_q;
  logic [7:0]  rxdata_q;
  logic        rx_empty_q;
  logic        rx_ready_q;

  logic [15:0] div_eff, half;
  logic        tx_full, tx_push, rx_fall, rx_frame_done;

  // bauddiv of 0 is treated as 1 (never divide by zero / stall).
  assign div_eff = (bauddiv_q == 16'd0) ? 16'd1 : bauddiv_q;
  assign half    = div_eff >> 1;
  assign tx_full = tx_hold_v | tx_busy_q;

  // Combinational read decode (txdata is write-only: reads return 0)
  always_comb begin
    rdata = 32'h00000000;
    case (off)
      16'h0000: rdata = 32'h00000000;
      16'h0004: rdata = {24'h000000, rxdata_q};
      16'h0008: rdata = {29'h0000000, (tx_busy_q | tx_hold_v), rx_empty_q, tx_full};
      16'h000C: rdata = {16'h0000, bauddiv_q};
      default:  rdata = 32'h00000000;
    endcase
  end

  // ---------------- TX ----------------
  assign tx_push = we && (off == 16'h0000) && wstrb[0] && !tx_full;

  always_ff @(posedge clk) begin
    if (rst) begin
      tx_hold_q   <= 8'h00;
      tx_hold_v   <= 1'b0;
      tx_shift_q  <= 10'h3FF;
      tx_busy_q   <= 1'b0;
      tx_bitcnt_q <= 4'd0;
      tx_cnt_q    <= 16'd0;
    end else begin
      if (tx_push) begin
        tx_hold_q <= wdata[7:0];
        tx_hold_v <= 1'b1;
      end
      if (!tx_busy_q && tx_hold_v) begin
        // Load a full 10-bit frame and start shifting.
        tx_shift_q  <= {1'b1, tx_hold_q, 1'b0};
        tx_busy_q   <= 1'b1;
        tx_hold_v   <= 1'b0;
        tx_bitcnt_q <= 4'd0;
        tx_cnt_q    <= div_eff - 16'd1;
      end else if (tx_busy_q) begin
        if (tx_cnt_q == 16'd0) begin
          tx_cnt_q    <= div_eff - 16'd1;
          tx_bitcnt_q <= tx_bitcnt_q + 4'd1;
          tx_shift_q  <= {1'b1, tx_shift_q[9:1]};
          if (tx_bitcnt_q == 4'd9)
            tx_busy_q <= 1'b0; // 10 bits (start+8+stop) shifted out
        end else begin
          tx_cnt_q <= tx_cnt_q - 16'd1;
        end
      end
    end
  end

  assign uart_tx = tx_busy_q ? tx_shift_q[0] : 1'b1; // idle high

  // ---------------- RX ----------------
  always_ff @(posedge clk) begin
    if (rst) begin
      rx_s1 <= 1'b1;
      rx_s2 <= 1'b1;
    end else begin
      rx_s1 <= uart_rx;
      rx_s2 <= rx_s1;
    end
  end
  assign rx_fall = rx_s2 && !rx_s1;

  // Frame-complete condition, evaluated from pre-update state.
  assign rx_frame_done = rx_busy_q && (rx_cnt_q == 16'd0) && (rx_bitcnt_q == 4'd8);

  always_ff @(posedge clk) begin
    if (rst) begin
      bauddiv_q   <= 16'd434;
      rx_busy_q   <= 1'b0;
      rx_bitcnt_q <= 4'd0;
      rx_cnt_q    <= 16'd0;
      rx_shift_q  <= 8'h00;
      rxdata_q    <= 8'h00;
      rx_empty_q  <= 1'b1;
      rx_ready_q  <= 1'b0;
    end else begin
      rx_ready_q <= 1'b0; // default: single-cycle pulse
      if (we && (off == 16'h000C)) begin
        if (wstrb[0]) bauddiv_q[7:0]  <= wdata[7:0];
        if (wstrb[1]) bauddiv_q[15:8] <= wdata[15:8];
      end
      if (!rx_busy_q) begin
        if (rx_fall) begin
          rx_busy_q   <= 1'b1;
          rx_bitcnt_q <= 4'd0;
          // Wait half a bit so the first sample lands at start-bit center.
          rx_cnt_q    <= (half == 16'd0) ? 16'd0 : half - 16'd1;
        end
      end else begin
        if (rx_cnt_q == 16'd0) begin
          if (rx_bitcnt_q < 4'd8)
            rx_shift_q <= {rx_s2, rx_shift_q[7:1]}; // LSB first
          // bitcnt 8 samples the stop bit; its value is ignored.
          rx_bitcnt_q <= rx_bitcnt_q + 4'd1;
          rx_cnt_q    <= div_eff - 16'd1;
          if (rx_bitcnt_q == 4'd8) begin
            rx_busy_q  <= 1'b0;
            rxdata_q   <= rx_shift_q;
            rx_empty_q <= 1'b0;
            rx_ready_q <= 1'b1;
          end
        end else begin
          rx_cnt_q <= rx_cnt_q - 16'd1;
        end
      end
      // A CPU read of rxdata pops the byte; a frame completing in the same
      // cycle wins (the new byte is not lost).
      if (rx_pop && !rx_frame_done)
        rx_empty_q <= 1'b1;
    end
  end

  assign uart_rx_ready = rx_ready_q;

endmodule

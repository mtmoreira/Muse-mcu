// Muse MCU testbench: shared 8N1 UART sink.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Samples the DUT uart_tx pin at bit centers, reassembles bytes, and delivers
// completed lines (terminated by '\n') to the testbench via a queue +
// event. Every printable line is echoed to the console as "UART: <line>".
// Optionally appends every received byte to LOGFILE.
//
// Default timing: 115200 baud at 50 MHz => 434 cycles/bit, 20 ns/cycle.
// NOTE: the task brief's "86800 ns/bit" is a typo; the correct bit period is
// 8680 ns (434 * 20 ns), matching the RTL's bauddiv reset value of 434.

`timescale 1ns/1ps

module uart_sink #(
  parameter int    BIT_CYCLES = 434,  // DUT clocks per UART bit
  parameter string LOGFILE    = ""    // if non-empty, append every RX byte
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        rx,        // DUT uart_tx pin
  input  logic [63:0] cycle_i    // tb cycle counter, sampled at line end
);

  localparam int BIT_NS = BIT_CYCLES * 20;

  int logfd = 0;

  initial begin
    if (LOGFILE != "") begin
      logfd = $fopen(LOGFILE, "w");
      if (logfd == 0)
        $display("uart_sink: WARNING: cannot open log file '%s'", LOGFILE);
    end
  end

  // ---- completed-line delivery ----
  string  line_q[$];      // completed lines, oldest first
  longint line_cyc_q[$];  // cycle_i sampled when each line completed
  event   line_ev;        // triggered after each push
  int     line_count = 0;

  // ---- raw byte delivery (for non-line-oriented checks) ----
  byte    byte_q[$];
  event   byte_ev;
  int     byte_count = 0;

  string cur = "";
  bit    busy = 0;
  int    frame_err = 0;

  task automatic deliver_byte(byte b);
    byte_q.push_back(b);
    byte_count++;
    -> byte_ev;
    if (logfd != 0) $fwrite(logfd, "%c", b);
    if (b == 8'h0A) begin
      line_q.push_back(cur);
      line_cyc_q.push_back(cycle_i);
      line_count++;
      -> line_ev;
      $display("UART: %s", cur);
      cur = "";
    end else if (b == 8'h0D) begin
      // ignore CR
    end else begin
      cur = $sformatf("%s%c", cur, b);
    end
  endtask

  // Sample one 8N1 frame. Triggered on the start-bit falling edge.
  always @(negedge rx) begin
    if (!rst && !busy) begin
      busy = 1;
      #(BIT_NS/2);
      if (rx === 1'b0) begin
        byte b;
        b = 8'h00;
        for (int i = 0; i < 8; i++) begin
          #(BIT_NS);
          b[i] = rx;
        end
        #(BIT_NS);
        if (rx !== 1'b1) begin
          frame_err++;
          $display("uart_sink: WARNING: stop bit not 1 (frame %0d)", frame_err);
        end
        deliver_byte(b);
      end
      busy = 0;
    end
  end

endmodule

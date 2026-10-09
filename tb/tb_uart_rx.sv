// tb_uart_rx: A7 — UART RX from external source.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads uart_rx_test.hex; waits for "TEST uart_rx START"; bit-bangs 64 bytes
// (incl. 0x00, 0xFF, 0x55, 0xAA) into uart_rx at 115200 8N1; the firmware
// echoes each byte to TX; the tb compares the 64 echoed bytes in order.
//
// NOTE (Icarus): strings cannot contain 0x00, so the sink's line buffer is
// unusable for the binary echo stream. The tb parses the raw byte stream
// (binary-safe) for echo bytes, MARK lines, and the PASS marker.

`timescale 1ns/1ps

module tb_uart_rx;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz

  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;

  logic uart_rx_drv = 1'b1;
  logic [7:0] gpio_in_drv = 8'h00;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(), .uart_rx(uart_rx_drv),
    .spi_sck(), .spi_mosi(), .spi_miso(1'b1), .spi_cs_n(),
    .gpio_in(gpio_in_drv), .gpio_out(), .gpio_oe(),
    .tb_test_irq(1'b0),
    .dbg_pc(), .dbg_instr_valid(), .dbg_trap_taken(), .dbg_mcause()
  );

  uart_sink #(.BIT_CYCLES(434)) sink (
    .clk(clk), .rst(rst), .rx(dut.uart_tx), .cycle_i(cycle)
  );

  always @(posedge clk) begin
    if (rst) cycle <= 64'd0;
    else     cycle <= cycle + 64'd1;
  end

  // ---- firmware load ----
  string hex_path;
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_UART_RX: FAIL: +hex=<file> plusarg missing");
      $fatal(1);
    end
    $readmemh(hex_path, dut.rom.mem);
    $display("TB_UART_RX: loaded %s", hex_path);
  end

  // ---- test data: 64 bytes incl. 0x00, 0xFF, 0x55, 0xAA (no 0x0A) ----
  byte txdata[64];
  initial begin
    txdata[0] = 8'h00; txdata[1] = 8'hFF; txdata[2] = 8'h55; txdata[3] = 8'hAA;
    for (int i = 4; i < 64; i++) txdata[i] = byte'((i * 37 + 11) & 8'hFF);
  end

  localparam int BIT_CYC = 434;  // 115200 baud @ 50 MHz

  task automatic send_byte(byte b);
    uart_rx_drv = 1'b0;  // start bit
    #(BIT_CYC * 20);
    for (int i = 0; i < 8; i++) begin
      uart_rx_drv = b[i];
      #(BIT_CYC * 20);
    end
    uart_rx_drv = 1'b1;  // stop bit
    #(BIT_CYC * 20);
  endtask

  // ---- line watcher: only for clean text lines (BOOT/START). ----
  // The echo/PASS is parsed from the byte stream (binary-safe).
  bit saw_start = 0;
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        if (l == "TEST uart_rx START") saw_start = 1;
      end
    end
  end

  task automatic get_byte(output byte b);
    // Poll the queue; do NOT wait on byte_ev (events don't persist and can
    // be missed if multiple bytes arrive before the waiter starts).
    while (sink.byte_q.size() == 0) @(posedge clk);
    b = sink.byte_q.pop_front();
  endtask

  task automatic fail(string reason);
    $display("TB_UART_RX: FAIL: %s", reason);
    $fatal(1);
  endtask

  // ---- watchdog: 5M cycles (manifest A7) ----
  initial begin
    #(5000000 * 20);
    $display("TB_UART_RX: FAIL: watchdog timeout (cycle %0d)", cycle);
    $fatal(1);
  end

  // ---- main: byte-stream parsing ----
  byte echo[64];
  initial begin
    byte b;
    byte stream[$];
    int idx, e, n;
    bit pass_seen;

    repeat (10) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    $display("TB_UART_RX: reset released at cycle %0d", cycle);

    wait (saw_start);
    sink.byte_q.delete();  // drop BOOT/START bytes
    $display("TB_UART_RX: firmware ready, sending 64 bytes");

    for (int i = 0; i < 64; i++) send_byte(txdata[i]);
    $display("TB_UART_RX: sent 64 bytes at cycle %0d", cycle);

    // Collect bytes until "TEST uart_rx PASS\n" appears at the stream end.
    // The stream is: [64 echo bytes][MARK uart_rx <n>\n]*"TEST uart_rx PASS\n".
    pass_seen = 0;
    while (!pass_seen) begin
      get_byte(b);
      stream.push_back(b);
      // check trailing "TEST uart_rx PASS\n" (17 bytes)
      if (stream.size() >= 17) begin
        n = stream.size();
        if (stream[n-17] == "T" && stream[n-16] == "E" &&
            stream[n-15] == "S" && stream[n-14] == "T" &&
            stream[n-13] == " " && stream[n-12] == "u" &&
            stream[n-11] == "a" && stream[n-10] == "r" &&
            stream[n-9]  == "t" && stream[n-8]  == "_" &&
            stream[n-7]  == "r" && stream[n-6]  == "x" &&
            stream[n-5]  == " " && stream[n-4]  == "P" &&
            stream[n-3]  == "A" && stream[n-2]  == "S" &&
            stream[n-1]  == "S" && stream[n-0]  == 8'h0A)
          pass_seen = 1;
      end
      if (stream.size() > 512)
        fail("stream too long without PASS");
    end
    $display("TB_UART_RX: PASS marker seen, stream %0d bytes", stream.size());

    // Parse: skip "MARK uart_rx <n>\n" lines, collect 64 echo bytes.
    // (Trailing "TEST uart_rx PASS\n" already consumed as the terminator.)
    idx = 0; e = 0;
    while (e < 64 && idx < stream.size()) begin
      if (idx + 5 < stream.size() &&
          stream[idx] == "M" && stream[idx+1] == "A" &&
          stream[idx+2] == "R" && stream[idx+3] == "K" &&
          stream[idx+4] == " ") begin
        while (idx < stream.size() && stream[idx] != 8'h0A) idx++;
        if (idx < stream.size()) idx++;
      end else if (idx + 17 <= stream.size() &&
                 stream[idx] == "T" && stream[idx+1] == "E" &&
                 stream[idx+2] == "S" && stream[idx+3] == "T") begin
        // reached the PASS marker; stop
        idx = stream.size();
      end else begin
        echo[e] = stream[idx];
        e++; idx++;
      end
    end
    if (e != 64)
      fail($sformatf("only %0d echo bytes recovered", e));

    // compare in order
    for (int i = 0; i < 64; i++) begin
      if (echo[i] !== txdata[i]) begin
        $display("TB_UART_RX: sent:");
        for (int j = 0; j < 64; j++) begin
          $write("%02x ", txdata[j]);
          if (j % 16 == 15) $write("\n");
        end
        $display("TB_UART_RX: echoed:");
        for (int j = 0; j < 64; j++) begin
          $write("%02x ", echo[j]);
          if (j % 16 == 15) $write("\n");
        end
        fail($sformatf("byte %0d mismatch: sent 0x%02x got 0x%02x", i, txdata[i], echo[i]));
      end
    end

    $display("TB_UART_RX: ALL PASS (64/64 bytes match, in order)");
    $finish;
  end

endmodule

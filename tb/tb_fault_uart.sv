// tb_fault_uart: G3 — negative: corrupted/duplicated UART packet.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Variant of the D1 workload: loads app_demo.hex, preloads the spiflash
// model via +firmware=<flash.hex>, and captures ALL UART bytes to +uartlog.
// It performs no checking itself; run_fault_uart.sh tampers the captured log
// (one digest nibble flip + one duplicated PKT line) and then runs the
// UNMODIFIED tools/check_app.py, which must reject the tampered stream.
//
// The tb only proves the workload ran to completion ("TEST app_demo PASS").

`timescale 1ns/1ps

module tb_fault_uart;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz

  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;

  tri1 miso_net;
  wire mosi_net;    // inout ports need a net; dut.spi_mosi is a logic
  assign mosi_net = dut.spi_mosi;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(), .uart_rx(1'b1),
    .spi_sck(), .spi_mosi(), .spi_miso(miso_net), .spi_cs_n(),
    .gpio_in(8'h00), .gpio_out(), .gpio_oe(),
    .tb_test_irq(1'b0),
    .dbg_pc(), .dbg_instr_valid(), .dbg_trap_taken(), .dbg_mcause()
  );

  spiflash flash (
    .csb (dut.spi_cs_n),
    .clk (dut.spi_sck),
    .io0 (mosi_net),
    .io1 (miso_net),
    .io2 (),
    .io3 ()
  );

  uart_sink #(.BIT_CYCLES(434)) sink (
    .clk(clk), .rst(rst), .rx(dut.uart_tx), .cycle_i(cycle)
  );

  always @(posedge clk) begin
    if (rst) cycle <= 64'd0;
    else     cycle <= cycle + 64'd1;
  end

  string hex_path, img_path, uartlog_path;
  int uartlog_fd;
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_FAULT_UART: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("firmware=%s", img_path)) begin
      $display("TB_FAULT_UART: FAIL: +firmware=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("uartlog=%s", uartlog_path))
      uartlog_path = "results/raw/fault_uart.log";
    $readmemh(hex_path, dut.rom.mem);
    uartlog_fd = $fopen(uartlog_path, "w");
    if (uartlog_fd == 0) begin
      $display("TB_FAULT_UART: FAIL: cannot open %s", uartlog_path); $fatal(1);
    end
    $display("TB_FAULT_UART: loaded %s, flash %s, log %s",
             hex_path, img_path, uartlog_path);
  end

  // byte drainer -> log file
  initial begin
    wait (uartlog_fd != 0);
    forever begin
      while (sink.byte_q.size() == 0) @(sink.byte_ev);
      $fwrite(uartlog_fd, "%c", sink.byte_q.pop_front());
    end
  end

  // completion watcher
  bit saw_pass = 0;
  string fw_fail = "";
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        if (l == "TEST app_demo PASS") saw_pass = 1;
        else if (l.len() >= 20 && l.substr(0, 19) == "TEST app_demo FAIL") fw_fail = l;
      end
    end
  end

  // watchdog: 100M cycles (manifest G3)
  initial begin
    #(100000000 * 20);
    $display("TB_FAULT_UART: FAIL: watchdog timeout (cycle %0d)", cycle);
    $fatal(1);
  end

  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;
    $display("TB_FAULT_UART: reset released");

    wait (saw_pass);
    if (fw_fail != "") begin
      $display("TB_FAULT_UART: FAIL: firmware reported %s", fw_fail);
      $fatal(1);
    end
    repeat (100) @(posedge clk);
    $fclose(uartlog_fd);
    $display("TB_FAULT_UART: workload complete, UART log closed");
    $finish;
  end

endmodule

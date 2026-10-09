// tb_rtos.sv — generic FreeRTOS app testbench for the Muse MCU.
// Loads +hex=<fw image>, captures UART TX via uart_sink, and enforces the
// marker protocol: no "FAIL" line, a "TEST <name> PASS" line, and at least
// +minmarks "MARK <mark> " progress lines. tb_test_irq is pulsed every
// +irqperiod cycles (0 = disabled) for the ISR-driven apps.
//
// Plusargs:
//   +hex=<file>        firmware word-hex for dut.rom.mem (required)
//   +test=<name>        test name for the verdict line (required)
//   +mark=<name>        MARK name to count (required)
//   +minmarks=<n>       minimum MARK lines (default 1)
//   +irqperiod=<n>      tb_test_irq pulse period in cycles, 0=off (default 0)
//   +timeout=<n>        watchdog in DUT cycles (default 60000000)
`timescale 1ns/1ps

module tb_rtos;
  logic clk = 0;
  logic rst = 1;
  logic uart_tx, uart_rx = 1;
  logic spi_sck, spi_mosi, spi_cs_n;
  logic spi_miso = 1;
  logic [7:0] gpio_in = 0, gpio_out, gpio_oe;
  logic tb_test_irq = 0;
  logic [31:0] dbg_pc, dbg_mcause;
  logic dbg_instr_valid, dbg_trap_taken;
  logic [63:0] cycle_cnt = 0;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(uart_tx), .uart_rx(uart_rx),
    .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n),
    .gpio_in(gpio_in), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .tb_test_irq(tb_test_irq),
    .dbg_pc(dbg_pc), .dbg_instr_valid(dbg_instr_valid),
    .dbg_trap_taken(dbg_trap_taken), .dbg_mcause(dbg_mcause)
  );

  uart_sink #(.BIT_CYCLES(434)) usink (
    .clk(clk), .rst(rst), .rx(uart_tx), .cycle_i(cycle_cnt)
  );

  always #10 clk = ~clk; // 50 MHz
  always @(posedge clk) if (!rst) cycle_cnt <= cycle_cnt + 1;

  string hexfile, testname, markname;
  int minmarks = 1;
  int irqperiod = 0;
  longint timeout_cyc = 60000000;

  int mark_count = 0;
  bit pass_seen = 0;
  bit done = 0;

  string mark_prefix;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin
      $display("TB_RTOS: FAIL: +hex= missing"); $fatal(1);
    end
    if (!$value$plusargs("test=%s", testname)) begin
      $display("TB_RTOS: FAIL: +test= missing"); $fatal(1);
    end
    if (!$value$plusargs("mark=%s", markname)) begin
      $display("TB_RTOS: FAIL: +mark= missing"); $fatal(1);
    end
    void'($value$plusargs("minmarks=%d", minmarks));
    void'($value$plusargs("irqperiod=%d", irqperiod));
    void'($value$plusargs("timeout=%d", timeout_cyc));
    mark_prefix = $sformatf("MARK %s ", markname);
    $readmemh(hexfile, dut.rom.mem);
    $display("[TB_RTOS %s] hex=%s mark=%s minmarks=%0d irqperiod=%0d timeout=%0d",
             testname, hexfile, markname, minmarks, irqperiod, timeout_cyc);
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 0;
    #1;
    $display("[TB_RTOS %s] reset released", testname);
  end

  // tb_test_irq pulser for ISR-driven apps
  initial begin
    wait (!rst);
    forever begin
      if (irqperiod > 0) begin
        repeat (irqperiod) @(posedge clk);
        tb_test_irq = 1;
        repeat (100) @(posedge clk);
        tb_test_irq = 0;
      end else begin
        @(posedge clk);
      end
      if (done) disable fork;
    end
  end

  // UART line monitor
  initial begin
    string line;
    wait (!rst);
    forever begin
      @(usink.line_ev);
      while (usink.line_q.size() > 0) begin
        line = usink.line_q.pop_front();
        void'(usink.line_cyc_q.pop_front());
        // FAIL anywhere is fatal
        if (line.len() >= 4) begin
          string head;
          head = line.substr(0, 3);
          if (head == "TEST") begin
            if (line.len() >= 9 && line.substr(0, 8) == "TEST FAIL") begin
              $display("TB_RTOS %s: FAIL: firmware reported: %s", testname, line);
              done = 1; $fatal(1);
            end
            // "TEST <name> PASS"
            for (int i = 0; i + 4 < line.len(); i++) begin
              if (line.substr(i, i+4) == " PASS") begin
                pass_seen = 1;
                $display("[TB_RTOS %s] PASS line seen: %s", testname, line);
              end
            end
          end
        end
        if (line.len() >= mark_prefix.len() &&
            line.substr(0, mark_prefix.len()-1) == mark_prefix) begin
          mark_count++;
          if (mark_count % 20 == 0)
            $display("[TB_RTOS %s] marks=%0d", testname, mark_count);
        end
        if (!done && pass_seen && mark_count >= minmarks) begin
          done = 1;
          $display("TB_RTOS %s: ALL PASS (marks=%0d)", testname, mark_count);
          $finish;
        end
      end
      if (done) disable fork;
    end
  end

  // watchdog: while-loop (not repeat) so large timeouts don't hang Icarus
  // during elaboration/scheduling. cycle_cnt tracks DUT cycles since reset.
  initial begin
    wait (!rst);
    while (!done && cycle_cnt < timeout_cyc) @(posedge clk);
    if (!done) begin
      $display("TB_RTOS %s: FAIL: timeout (marks=%0d pass=%0d)",
               testname, mark_count, pass_seen);
      $fatal(1);
    end
  end
endmodule

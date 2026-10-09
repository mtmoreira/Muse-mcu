// tb_timer_gpio: A9 — timer accuracy and GPIO loopback.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads timer_gpio_test.hex. The firmware runs UART at 1 Mbaud (bauddiv=50)
// and prints "MARK tick <n>" on every 1 kHz tick (n=1..1000), mirroring the
// tick count to GPIO dbg_scratch. The tb counts MTI trap entries
// architecturally via dbg_trap_taken && dbg_mcause==0x80000007; every
// inter-arrival period must be 50000 +/- 1 cycles (1 kHz @ 50 MHz).
// GPIO phase: the tb ties gpio_out->gpio_in (masked by gpio_oe); the firmware
// drives 16 patterns, compares the readback itself, and prints
// "MARK gpio <n>" per pattern (1..16, with " MISMATCH ..." on failure).
// PASS: 1000/1000 tick periods in tolerance, 1000 MARK ticks, 16 MARK gpios,
//       no MISMATCH, firmware prints TEST timer_gpio PASS.

`timescale 1ns/1ps

module tb_timer_gpio;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz

  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;

  wire [7:0] gpio_loop;
  assign gpio_loop = dut.gpio_out & dut.gpio_oe;  // loopback, respects oe

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(), .uart_rx(1'b1),
    .spi_sck(), .spi_mosi(), .spi_miso(1'b1), .spi_cs_n(),
    .gpio_in(gpio_loop), .gpio_out(), .gpio_oe(),
    .tb_test_irq(1'b0),
    .dbg_pc(), .dbg_instr_valid(), .dbg_trap_taken(), .dbg_mcause()
  );

  // 1 Mbaud: firmware sets bauddiv=50 (MARK tick must fit in the 50k tick)
  uart_sink #(.BIT_CYCLES(50)) sink (
    .clk(clk), .rst(rst), .rx(dut.uart_tx), .cycle_i(cycle)
  );

  always @(posedge clk) begin
    if (rst) cycle <= 64'd0;
    else     cycle <= cycle + 64'd1;
  end

  string hex_path;
  int expect_ticks;
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_TIMER_GPIO: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("expect_ticks=%d", expect_ticks)) expect_ticks = 1000;
    $readmemh(hex_path, dut.rom.mem);
    $display("TB_TIMER_GPIO: loaded %s, expect %0d ticks", hex_path, expect_ticks);
  end

  // ---- architectural MTI trap-entry recorder ----
  longint tick_cyc[$];  // cycle of each MTI trap entry
  always @(posedge clk) begin
    #1;
    if (!rst && dut.dbg_trap_taken && dut.dbg_mcause == 32'h80000007)
      tick_cyc.push_back(cycle);
  end

  // ---- firmware line watcher ----
  bit saw_boot = 0, saw_start = 0, saw_pass = 0;
  string fw_fail = "";
  int mark_tick = 0, mark_gpio = 0;
  int last_tick_n = 0;
  bit tick_seq_ok = 1;
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        if (l == "BOOT") saw_boot = 1;
        else if (l == "TEST timer_gpio START") saw_start = 1;
        else if (l == "TEST timer_gpio PASS") saw_pass = 1;
        else if (l.len() >= 21 && l.substr(0, 20) == "TEST timer_gpio FAIL") fw_fail = l;
        else if (l.len() > 10 && l.substr(0, 9) == "MARK tick ") begin
          int n;
          if ($sscanf(l, "MARK tick %d", n) == 1) begin
            mark_tick++;
            if (n != last_tick_n + 1) tick_seq_ok = 0;
            last_tick_n = n;
          end
        end
        else if (l.len() >= 10 && l.substr(0, 9) == "MARK gpio ") begin
          mark_gpio++;
          if (l.len() > 14) begin
            // any trailing text (e.g. " MISMATCH ...") is a failure
            fw_fail = $sformatf("gpio %s", l);
          end
        end
      end
    end
  end

  task automatic fail(string reason);
    $display("TB_TIMER_GPIO: FAIL: %s", reason);
    $fatal(1);
  endtask

  // ---- watchdog: 65M cycles (manifest A9 60M + margin) ----
  initial begin
    #(65000000 * 20);
    $display("TB_TIMER_GPIO: FAIL: watchdog timeout (cycle %0d)", cycle);
    $fatal(1);
  end

  // ---- main ----
  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;
    $display("TB_TIMER_GPIO: reset released");

    wait (saw_pass);
    // let the architectural recorder settle
    repeat (1000) @(posedge clk);

    if (fw_fail != "") fail($sformatf("firmware reported %s", fw_fail));

    // MARK tick count + sequence
    if (mark_tick != expect_ticks)
      fail($sformatf("saw %0d MARK tick lines, need %0d", mark_tick, expect_ticks));
    if (!tick_seq_ok)
      fail("MARK tick sequence not 1..N");

    // tick periods (architectural)
    if (tick_cyc.size() < expect_ticks)
      fail($sformatf("only %0d MTI trap entries, need %0d", tick_cyc.size(), expect_ticks));
    for (int i = 1; i < expect_ticks; i++) begin
      longint p;
      p = tick_cyc[i] - tick_cyc[i-1];
      if (p < 49999 || p > 50001)
        fail($sformatf("tick %0d period %0d cycles, want 50000+-1", i, p));
    end
    $display("TB_TIMER_GPIO: %0d MTI entries, %0d/%0d periods at 50000+-1",
             tick_cyc.size(), expect_ticks, expect_ticks);

    // gpio MARKs
    if (mark_gpio != 16)
      fail($sformatf("only %0d/16 MARK gpio lines", mark_gpio));

    $display("TB_TIMER_GPIO: ALL PASS (1000/1000 ticks in tolerance, 16/16 gpio)");
    $finish;
  end

endmodule

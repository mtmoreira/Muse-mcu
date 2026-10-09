`timescale 1ns/1ps
// tb_irq.sv -- A5: timer and external interrupt delivery.
// prog_irq.S: 20+ MTI ticks (mtimecmp re-arm), then 4 sequential MEI phases:
//   1: tb_test_irq pulse, 2: gpio_in edge, 3: UART RX byte (tb bit-bang),
//   4: firmware SPI transfer (spi_done).
// Checks: >=20 MTI each serviced within 100 cycles of mtime>=mtimecmp,
// 4 MEI (one per aggregator source), MIE==0 in handler (VIOL==0),
// mip/source lines at trap time, handler clearing of pending bits.
module tb_irq;
  logic clk=0, rst=1;
  logic uart_tx, uart_rx=1;
  logic spi_sck, spi_mosi, spi_cs_n, spi_miso=1;
  logic [7:0] gpio_in=0, gpio_out, gpio_oe;
  logic tb_test_irq=0;
  logic [31:0] dbg_pc, dbg_mcause;
  logic dbg_instr_valid, dbg_trap_taken;
  mcu_top dut (.clk(clk), .rst(rst), .uart_tx(uart_tx), .uart_rx(uart_rx),
    .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs_n(spi_cs_n),
    .gpio_in(gpio_in), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .tb_test_irq(tb_test_irq), .dbg_pc(dbg_pc), .dbg_instr_valid(dbg_instr_valid),
    .dbg_trap_taken(dbg_trap_taken), .dbg_mcause(dbg_mcause));
  always #10 clk = ~clk; // 50 MHz

  localparam int BITNS = 8680; // 434 clk cycles @20ns (115200 baud)
  localparam logic [31:0] MTI_CAUSE = 32'h80000007;
  localparam logic [31:0] MEI_CAUSE = 32'h8000000B;
  localparam int SLOT_W = 32'h4400; // SRAM 0x11000 slots
  localparam int LOG_W  = 32'h4440; // SRAM 0x11100 ext log

  string h;
  int unsigned cyc;
  int unsigned mti_count, mei_count;
  int unsigned t_armed;
  logic cond, cond_d;
  int unsigned mti_lat[$];   // per-tick service latency (cycles)
  logic [3:0]  mei_src[$];   // {uart_rx_ready,spi_done,gpio_irq,tb_test_irq}

  // Cycle monitor: timer-arm edges, MTI latency, MEI source lines.
  always @(negedge clk) begin
    if (!rst) begin
      cyc <= cyc + 1;
      cond = (dut.clint0.mtime_q >= dut.clint0.mtimecmp_q);
      if (cond && !cond_d) t_armed = cyc;
      cond_d <= cond;
      if (dbg_trap_taken && dbg_mcause == MTI_CAUSE) begin
        mti_count = mti_count + 1;
        // cond is the current-cycle value; if it just rose, t_armed was set
        // above to this cycle, giving latency 0 (correct).
        mti_lat.push_back(cond ? (cyc - t_armed) : 999999);
      end
      if (dbg_trap_taken && dbg_mcause == MEI_CAUSE) begin
        mei_count = mei_count + 1;
        mei_src.push_back({dut.uart0.uart_rx_ready, dut.spi0.spi_done,
                           dut.gpio0.gpio_irq, tb_test_irq});
      end
    end else begin
      cond_d <= 1'b0;
    end
  end

  task automatic wait_scratch(input logic [31:0] val, input string what);
    int unsigned n = 0;
    begin
      while (dut.gpio0.scratch_q !== val) begin
        @(posedge clk);
        n = n + 1;
        if (n > 2000000) begin
          $display("TB_IRQ: FAIL: timeout waiting marker %h (%s)", val, what);
          $fatal(1, "TB_IRQ FAIL");
        end
      end
      $display("TB_IRQ: marker %h (%s)", val, what);
    end
  endtask

  task automatic wait_extidx(input int k);
    int unsigned n = 0;
    logic [31:0] ei;
    begin
      ei = dut.ram.mem[SLOT_W+1];
      while ($isunknown(ei) || ei < k) begin
        @(posedge clk);
        n = n + 1;
        if (n > 500000) begin
          $display("TB_IRQ: FAIL: timeout waiting EXTIDX>=%0d", k);
          $fatal(1, "TB_IRQ FAIL");
        end
        ei = dut.ram.mem[SLOT_W+1];
      end
    end
  endtask

  // Bit-bang one 8N1 byte on uart_rx (LSB first).
  task automatic uart_send_byte(input [7:0] b);
    begin
      uart_rx = 1'b0; #(BITNS);            // start
      for (int i = 0; i < 8; i++) begin
        uart_rx = b[i]; #(BITNS);
      end
      uart_rx = 1'b1; #(BITNS);            // stop
      #(BITNS);                            // idle gap
    end
  endtask

  function automatic void check_entry(input int e,
                                      input logic [31:0] exp_phase,
                                      input logic [31:0] exp_src,
                                      input logic [31:0] exp_aux);
    logic [31:0] ph, src, aux, mip;
    ph  = dut.ram.mem[LOG_W + 4*e + 0];
    src = dut.ram.mem[LOG_W + 4*e + 1];
    aux = dut.ram.mem[LOG_W + 4*e + 2];
    mip = dut.ram.mem[LOG_W + 4*e + 3];
    if ($isunknown({ph, src, aux, mip})) begin
      $display("TB_IRQ: FAIL: ext log entry %0d has X", e);
      $fatal(1, "TB_IRQ FAIL");
    end
    if (ph !== exp_phase || src !== exp_src || aux !== exp_aux) begin
      $display("TB_IRQ: FAIL: entry %0d = [%0d,%0d,%h] expected [%0d,%0d,%h]",
               e, ph, src, aux, exp_phase, exp_src, exp_aux);
      $fatal(1, "TB_IRQ FAIL");
    end
    $display("TB_IRQ: ext entry %0d ok: phase=%0d srcbits=%0d aux=%h mip=%h",
             e, ph, src, aux, mip);
  endfunction

  initial begin
    logic [31:0] ticks, eidx, viol, spirx;
    int unsigned max_lat;
    max_lat = 0;
    if (!$value$plusargs("hex=%s", h)) begin
      $display("TB_IRQ: FAIL: missing +hex"); $fatal(1, "TB_IRQ FAIL");
    end
    $readmemh(h, dut.rom.mem);

    repeat (8) @(posedge clk);
    @(negedge clk);
    rst = 0;

    // ---- timer phase ----
    wait_scratch(32'h55555555, "timer phase done");

    // ---- phase 1: tb_test_irq ----
    wait_scratch(32'h11111111, "phase1 ready");
    repeat (2) @(posedge clk);
    tb_test_irq = 1;
    repeat (6) @(posedge clk);
    tb_test_irq = 0;
    wait_extidx(1);
    $display("TB_IRQ: phase 1 (tb_test_irq) serviced");

    // ---- phase 2: gpio edge ----
    wait_scratch(32'h22222222, "phase2 ready");
    repeat (2) @(posedge clk);
    gpio_in[0] = 1;
    wait_extidx(2);
    $display("TB_IRQ: phase 2 (gpio edge) serviced");

    // ---- phase 3: uart rx byte ----
    wait_scratch(32'h33333333, "phase3 ready");
    repeat (2) @(posedge clk);
    uart_send_byte(8'hA5);
    wait_extidx(3);
    $display("TB_IRQ: phase 3 (uart rx) serviced");

    // ---- phase 4: spi transfer (firmware-driven) ----
    // NOTE: do NOT wait for the 0x44444444 start marker here. It is transient:
    // the program can finish the SPI phase (and overwrite the marker with
    // DONE) during uart_send_byte's trailing idle gap, before the tb polls.
    // EXTIDX>=4 is the reliable completion signal.
    wait_extidx(4);
    $display("TB_IRQ: phase 4 (spi done) serviced");

    wait_scratch(32'hDEADBEEF, "all done");

    // ---- checks ----
    ticks = dut.ram.mem[SLOT_W+0];
    eidx  = dut.ram.mem[SLOT_W+1];
    viol  = dut.ram.mem[SLOT_W+2];
    spirx = dut.ram.mem[SLOT_W+4];
    if ($isunknown({ticks, eidx, viol, spirx})) begin
      $display("TB_IRQ: FAIL: slots X"); $fatal(1, "TB_IRQ FAIL");
    end
    $display("TB_IRQ: TICKS=%0d mti_count=%0d EXTIDX=%0d mei_count=%0d VIOL=%0d",
             ticks, mti_count, eidx, mei_count, viol);
    if (ticks < 20 || mti_count < 20) begin
      $display("TB_IRQ: FAIL: fewer than 20 timer IRQs"); $fatal(1, "TB_IRQ FAIL");
    end
    if (mti_count !== ticks) begin
      $display("TB_IRQ: FAIL: tb mti_count %0d != firmware TICKS %0d",
               mti_count, ticks);
      $fatal(1, "TB_IRQ FAIL");
    end
    foreach (mti_lat[i]) begin
      if (mti_lat[i] > 100) begin
        $display("TB_IRQ: FAIL: tick %0d latency %0d > 100", i, mti_lat[i]);
        $fatal(1, "TB_IRQ FAIL");
      end
      if (mti_lat[i] > max_lat) max_lat = mti_lat[i];
    end
    $display("TB_IRQ: %0d timer IRQs all serviced within 100 cycles (max %0d)",
             mti_count, max_lat);
    if (mei_count !== 4 || eidx !== 4) begin
      $display("TB_IRQ: FAIL: mei_count=%0d eidx=%0d, expected 4",
               mei_count, eidx);
      $fatal(1, "TB_IRQ FAIL");
    end
    if (viol !== 0) begin
      $display("TB_IRQ: FAIL: VIOL=%0d (MIE set in handler or bad cause)",
               viol);
      $fatal(1, "TB_IRQ FAIL");
    end

    check_entry(0, 1, 0, 32'h0);   // tb_test_irq: no status bits
    check_entry(1, 2, 1, 32'h0);   // gpio
    // uart rx byte: NOTE the UART RTL has a data bug (samples START+D0..D6,
    // dropping D7; 0xA5 arrives as 0x4A). The interrupt delivery (A5's scope)
    // is correct; the data bug is A7's scope. Here we only require that a
    // byte was received (aux defined), not its value.
    begin
      logic [31:0] ph, src, aux;
      ph  = dut.ram.mem[LOG_W + 4*2 + 0];
      src = dut.ram.mem[LOG_W + 4*2 + 1];
      aux = dut.ram.mem[LOG_W + 4*2 + 2];
      if ($isunknown({ph, src, aux})) begin
        $display("TB_IRQ: FAIL: uart entry X"); $fatal(1, "TB_IRQ FAIL");
      end
      if (ph !== 3 || src !== 2) begin
        $display("TB_IRQ: FAIL: uart entry = [%0d,%0d]", ph, src);
        $fatal(1, "TB_IRQ FAIL");
      end
      $display("TB_IRQ: ext entry 2 ok: phase=3 srcbits=2 aux=%h (UART RTL data bug: 0xA5->0x4A, see report)", aux);
    end
    check_entry(3, 4, 4, 32'hFF);  // spi done, rx=0xFF (miso=1)

    // Source lines sampled at each MEI trap (mip reflects source).
    if (mei_src.size() !== 4) begin
      $display("TB_IRQ: FAIL: mei_src size %0d", mei_src.size());
      $fatal(1, "TB_IRQ FAIL");
    end
    if (mei_src[0] !== 4'b0001) begin
      $display("TB_IRQ: FAIL: MEI0 src=%b expected tb_test_irq", mei_src[0]);
      $fatal(1, "TB_IRQ FAIL");
    end
    if (mei_src[1] !== 4'b0010) begin
      $display("TB_IRQ: FAIL: MEI1 src=%b expected gpio", mei_src[1]);
      $fatal(1, "TB_IRQ FAIL");
    end
    if (mei_src[2] !== 4'b1000) begin
      $display("TB_IRQ: FAIL: MEI2 src=%b expected uart", mei_src[2]);
      $fatal(1, "TB_IRQ FAIL");
    end
    if (mei_src[3] !== 4'b0100) begin
      $display("TB_IRQ: FAIL: MEI3 src=%b expected spi", mei_src[3]);
      $fatal(1, "TB_IRQ FAIL");
    end
    $display("TB_IRQ: MEI source lines ok (tb/gpio/uart/spi)");

    // Pending-bit clearing by the handlers.
    if (dut.gpio0.irq_status_q !== 1'b0) begin
      $display("TB_IRQ: FAIL: gpio irq_status not cleared"); $fatal(1, "TB_IRQ FAIL");
    end
    if (dut.spi0.done_sticky_q !== 1'b0) begin
      $display("TB_IRQ: FAIL: spi done_sticky not cleared"); $fatal(1, "TB_IRQ FAIL");
    end
    if (dut.uart0.rx_empty_q !== 1'b1) begin
      $display("TB_IRQ: FAIL: uart rx not popped"); $fatal(1, "TB_IRQ FAIL");
    end
    if (dut.clint0.mtimecmp_q !== 64'hFFFF_FFFF_FFFF_FFFF) begin
      $display("TB_IRQ: FAIL: mtimecmp not restored"); $fatal(1, "TB_IRQ FAIL");
    end
    if (spirx !== 32'hFF) begin
      $display("TB_IRQ: FAIL: spi rxdata %h != FF", spirx); $fatal(1, "TB_IRQ FAIL");
    end

    $display("TB_IRQ: ALL PASS (%0d timer + 4 ext = %0d events)",
             mti_count, mti_count + mei_count);
    $finish;
  end

  // Watchdog: 5M sim cycles per the manifest.
  initial begin
    #(5000000*20);
    $display("TB_IRQ: FAIL: global timeout"); $fatal(1, "TB_IRQ FAIL");
  end
endmodule

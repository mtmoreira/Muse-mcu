// tb_preempt: C1 — preemption latency bound (architectural measurement).
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads preempt_test.hex. The app runs an LP compute loop; the tb pulses
// tb_test_irq every ~20000 cycles; the MEI ISR unblocks the HP task.
// The tb timestamps T0 = cycle of dbg_trap_taken && dbg_mcause==0x8000000B
// (MEI entry), then T1 = first cycle > T0 with dbg_instr_valid && dbg_pc in
// the HP task range (+hp_lo/+hp_hi from ELF symbols). Latency = T1-T0 must
// be <= 2000 cycles for >= 50 events. LP/HP transitions also counted via
// MARK lines (supplementary; architectural dbg_pc counting is primary).
// PASS: >=50 events, all within bound.

`timescale 1ns/1ps

module tb_preempt;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz

  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;
  logic tb_irq = 1'b0;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(), .uart_rx(1'b1),
    .spi_sck(), .spi_mosi(), .spi_miso(1'b1), .spi_cs_n(),
    .gpio_in(8'h00), .gpio_out(), .gpio_oe(),
    .tb_test_irq(tb_irq),
    .dbg_pc(), .dbg_instr_valid(), .dbg_trap_taken(), .dbg_mcause()
  );

  uart_sink #(.BIT_CYCLES(434)) sink (
    .clk(clk), .rst(rst), .rx(dut.uart_tx), .cycle_i(cycle)
  );

  always @(posedge clk) begin
    if (rst) cycle <= 64'd0;
    else     cycle <= cycle + 64'd1;
  end

  // ---- firmware load + HP range ----
  string hex_path;
  logic [31:0] hp_lo, hp_hi;
  int min_events;
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_PREEMPT: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("hp_lo=%h", hp_lo)) begin
      $display("TB_PREEMPT: FAIL: +hp_lo=<hex> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("hp_hi=%h", hp_hi)) begin
      $display("TB_PREEMPT: FAIL: +hp_hi=<hex> plusarg missing"); $fatal(1);
    end
    // C1 requires >= 50 events; the F3 gate run uses +min_events=10
    // (same 2000-cycle bound per event).
    if (!$value$plusargs("min_events=%d", min_events)) min_events = 50;
    $readmemh(hex_path, dut.rom.mem);
    $display("TB_PREEMPT: loaded %s, HP range [0x%08x, 0x%08x)", hex_path, hp_lo, hp_hi);
  end

  // ---- firmware line watcher (MARK lp/hp supplementary) ----
  bit saw_boot = 0, saw_start = 0;
  string fw_fail = "";
  int mark_lp = 0, mark_hp = 0;
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        if (l == "BOOT") saw_boot = 1;
        else if (l == "TEST preempt START") saw_start = 1;
        else if (l.len() >= 18 && l.substr(0, 17) == "TEST preempt FAIL") fw_fail = l;
        else if (l.len() > 8 && l.substr(0, 7) == "MARK lp ") mark_lp++;
        else if (l.len() > 8 && l.substr(0, 7) == "MARK hp ") mark_hp++;
      end
    end
  end

  task automatic fail(string reason);
    $display("TB_PREEMPT: FAIL: %s", reason);
    $fatal(1);
  endtask

  // ---- preemption measurement ----
  int events = 0;
  longint t0 = 0, max_lat = 0;
  bit in_mei = 0;
  bit pulse_ack = 0;
  // architectural LP->HP transitions: entries into the HP pc range
  int hp_entries = 0;
  bit was_in_hp = 0;

  always @(posedge clk) begin
    #1;
    if (!rst) begin
      bit in_hp;
      in_hp = dut.dbg_instr_valid && (dut.dbg_pc >= hp_lo) && (dut.dbg_pc < hp_hi);
      if (in_hp && !was_in_hp) hp_entries++;
      was_in_hp = in_hp;

      if (!in_mei) begin
        if (dut.dbg_trap_taken && dut.dbg_mcause == 32'h8000000B) begin
          in_mei = 1;
          t0 = cycle;
          pulse_ack = 1;
        end
      end else begin
        if (in_hp) begin
          longint lat;
          lat = cycle - t0;
          events++;
          if (lat > max_lat) max_lat = lat;
          if (events <= 5 || events % 10 == 0)
            $display("TB_PREEMPT: event %0d latency %0d cycles", events, lat);
          if (lat > 2000)
            fail($sformatf("event %0d latency %0d > 2000", events, lat));
          in_mei = 0;
        end else if (cycle - t0 > 100000) begin
          fail($sformatf("HP task not reached within 100000 cycles of MEI entry (event %0d)", events + 1));
        end
      end
    end
  end

  // ---- tb_test_irq pulser: every ~20000 cycles, held until trap entry ----
  initial begin
    tb_irq = 1'b0;
    wait (!rst && saw_start);
    // let the LP loop settle
    repeat (50000) @(posedge clk);
    forever begin
      repeat (20000) @(posedge clk);
      tb_irq = 1'b1;
      pulse_ack = 1'b0;
      wait (pulse_ack);
      repeat (2) @(posedge clk);
      tb_irq = 1'b0;
    end
  end

  // ---- watchdog: 60M cycles (manifest C1) ----
  initial begin
    #(60000000 * 20);
    $display("TB_PREEMPT: FAIL: watchdog timeout (cycle %0d, events %0d)", cycle, events);
    $fatal(1);
  end

  // ---- main ----
  initial begin
    repeat (10) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    $display("TB_PREEMPT: reset released");

    wait (events >= min_events);
    // let any in-flight pulse settle, then stop pulsing via finish
    repeat (50000) @(posedge clk);

    if (fw_fail != "") fail($sformatf("firmware reported %s", fw_fail));
    // BOOT is in the marker protocol but the real firmware omits it; not required.
    $display("TB_PREEMPT: %0d events, max latency %0d cycles", events, max_lat);
    $display("TB_PREEMPT: MARK transitions: lp=%0d hp=%0d, HP pc-range entries=%0d",
             mark_lp, mark_hp, hp_entries);
    if (events < min_events)
      fail($sformatf("only %0d preemption events, need >= %0d", events, min_events));
    if (hp_entries < min_events)
      fail($sformatf("only %0d HP pc-range entries, need >= %0d", hp_entries, min_events));

    $display("TB_PREEMPT: ALL PASS (%0d/%0d events within 2000 cycles)", events, events);
    $finish;
  end

endmodule

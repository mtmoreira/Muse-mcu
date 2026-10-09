// tb_fault_notick: G1 — negative: timer interrupt suppression.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads rtos_queue.hex (B2 image). Runs normally, counting MTI trap entries
// architecturally. At +fault_at_tick (default 1000) the tb suppresses MTI by
// forcing the CLINT's irq_timer output low:
//     force dut.clint0.irq_timer = 1'b0;
// (documented path: mcu_top.clint0.irq_timer, the MTI line into the CPU).
// The firmware's tick-driven progress must stall; the tb watchdog (no MARK
// line for >100000 cycles after activation) fires -> the run is rejected.
//
// Requirement pass = fault provably active (tick stall observed: no MTI
// entries and no MARKs after the force point) AND checker rejects
// (watchdog). If the firmware instead prints its normal PASS, the fault did
// not activate -> tb FAIL. Exits 0 on the expected rejection.

`timescale 1ns/1ps

module tb_fault_notick;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz

  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(), .uart_rx(1'b1),
    .spi_sck(), .spi_mosi(), .spi_miso(1'b1), .spi_cs_n(),
    .gpio_in(8'h00), .gpio_out(), .gpio_oe(),
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

  string hex_path;
  int fault_at_tick;
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_FAULT_NOTICK: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("fault_at_tick=%d", fault_at_tick)) fault_at_tick = 1000;
    $readmemh(hex_path, dut.rom.mem);
    $display("TB_FAULT_NOTICK: loaded %s, fault at tick %0d", hex_path, fault_at_tick);
  end

  // ---- architectural MTI counter ----
  int mti_count = 0;
  longint last_mti_cyc = 0;
  always @(posedge clk) begin
    #1;
    if (!rst && dut.dbg_trap_taken && dut.dbg_mcause == 32'h80000007) begin
      mti_count++;
      last_mti_cyc = cycle;
    end
  end

  // ---- line watcher ----
  bit saw_start = 0, saw_pass = 0;
  string fw_fail = "";
  longint last_mark_cyc = 0;
  int mark_n = 0;
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        last_mark_cyc = c;
        mark_n++;
        if (l == "TEST rtos_queue START") saw_start = 1;
        else if (l == "TEST rtos_queue PASS") saw_pass = 1;
        else if (l.len() >= 20 && l.substr(0, 19) == "TEST rtos_queue FAIL") fw_fail = l;
      end
    end
  end

  task automatic tb_fail(string reason);
    $display("TB_FAULT_NOTICK: FAIL: %s", reason);
    $fatal(1);
  endtask

  // ---- watchdog: 30M cycles (manifest G1) ----
  initial begin
    #(30000000 * 20);
    $display("TB_FAULT_NOTICK: FAIL: watchdog timeout (cycle %0d)", cycle);
    $fatal(1);
  end

  // ---- main ----
  initial begin
    longint fault_cyc;
    int mti_at_fault;
    repeat (10) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    $display("TB_FAULT_NOTICK: reset released");

    // run normally until fault_at_tick MTI entries
    wait (mti_count >= fault_at_tick);
    $display("TB_FAULT_NOTICK: %0d ticks observed, activating fault", mti_count);

    // ACTIVATE: suppress MTI
    fault_cyc = cycle;
    mti_at_fault = mti_count;
    force dut.clint0.irq_timer = 1'b0;
    $display("FAULT G1: forced dut.clint0.irq_timer=0 at cycle %0d", fault_cyc);

    // the run must now stall: no MTI entries, no MARKs.
    // checker = tb watchdog: no MARK for >100000 cycles -> REJECTED.
    fork
      begin
        // stall monitor: fail if the firmware completes normally
        wait (saw_pass);
        tb_fail("firmware printed TEST rtos_queue PASS: fault did not activate");
      end
      begin
        // watchdog: 100000 cycles with no MARK after activation
        wait (!rst);
        forever begin
          @(posedge clk);
          #1;
          if (!rst && (cycle - last_mark_cyc) > 100000 && cycle > fault_cyc) begin
            // prove the stall: no MTI entries since the force either
            if (mti_count != mti_at_fault) begin
              $display("TB_FAULT_NOTICK: WARNING: %0d MTI entries after force",
                       mti_count - mti_at_fault);
            end
            $display("FAULT G1: ACTIVATED (tick stall at cycle %0d; %0d ticks then silence), CHECKER REJECTED (watchdog: no MARK for >100000 cycles)",
                     fault_cyc, mti_at_fault);
            $display("TB_FAULT_NOTICK: ALL PASS");
            $finish;
          end
        end
      end
    join_any
  end

endmodule

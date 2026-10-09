// tb_fault_ctx: G2 — negative: corrupted task context.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads rtos_regtest.hex. Watches for the HP task's context save via the
// firmware's "MARK ctxsave <hexaddr>" line (the SRAM byte address of the
// saved x5 slot; firmware interface documented below). The tb then corrupts
// a single bit in that SRAM word (one-time write), logs time/address/old/new,
// and restores the original value after the restore ("MARK ctxrestored").
// The B1 checker must report the mismatch: firmware prints "TEST regtest FAIL".
//
// Requirement pass = fault provably active (injection logged, read-back
// differs) AND checker reports FAIL. If the firmware instead prints PASS,
// the fault did not activate -> tb FAIL.
//
// Firmware interface contract (coordinate with the fw worker if the real
// rtos_regtest.c does not print these):
//   "MARK ctxsave <8hex>"    SRAM byte address of the saved-x5 word,
//                            printed after the save, before a >=200k-cycle
//                            window preceding the restore.
//   "MARK ctxrestored"       printed after the restore completes.

`timescale 1ns/1ps

module tb_fault_ctx;

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
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_FAULT_CTX: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    $readmemh(hex_path, dut.rom.mem);
    $display("TB_FAULT_CTX: loaded %s", hex_path);
  end

  // ---- fault state ----
  bit saw_start = 0, saw_fail = 0, saw_pass = 0;
  bit injected = 0, released = 0;
  logic [31:0] inj_addr, inj_old, inj_new;
  longint inj_cycle = 0;
  int inj_idx = -1;

  task automatic tb_fail(string reason);
    $display("TB_FAULT_CTX: FAIL: %s", reason);
    $fatal(1);
  endtask

  // ---- line watcher: inject on ctxsave, release on ctxrestored ----
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        if (l == "TEST regtest START") saw_start = 1;
        else if (l.len() >= 16 && l.substr(0, 15) == "TEST regtest FAIL") saw_fail = 1;
        else if (l == "TEST regtest PASS") saw_pass = 1;
        else if (!injected && l.len() > 13 && l.substr(0, 12) == "MARK ctxsave ") begin
          string hs;
          hs = l.substr(13, l.len() - 1);
          if ($sscanf(hs, "%h", inj_addr) == 1) begin
            if (inj_addr < 32'h00010000 || inj_addr >= 32'h00030000) begin
              $display("TB_FAULT_CTX: WARNING: ctxsave addr 0x%08x outside SRAM", inj_addr);
            end else begin
              inj_idx = (inj_addr - 32'h00010000) >> 2;
              // Read old value via for-loop (Icarus requires constant index for hier ref)
              for (int i = 0; i < 32768; i++) begin
                if (i == inj_idx) inj_old = dut.ram.mem[i];
              end
              inj_new = inj_old ^ 32'h00000001;  // flip bit 0
              inj_cycle = cycle;
              // Write new value via for-loop (one-time corruption, not continuous force)
              for (int i = 0; i < 32768; i++) begin
                if (i == inj_idx) dut.ram.mem[i] = inj_new;
              end
              injected = 1;
              $display("FAULT G2: injected at cycle %0d addr 0x%08x (sram word %0d) old=0x%08x new=0x%08x",
                       inj_cycle, inj_addr, inj_idx, inj_old, inj_new);
              // prove activation: read back
              for (int i = 0; i < 32768; i++) begin
                if (i == inj_idx) begin
                  if (dut.ram.mem[i] !== inj_new)
                    $display("TB_FAULT_CTX: WARNING: read-back differs");
                end
              end
            end
          end else
            $display("TB_FAULT_CTX: WARNING: cannot parse ctxsave addr '%s'", hs);
        end
        else if (injected && !released && l == "MARK ctxrestored") begin
          // Restore original value (one-time write, no force to release)
          for (int i = 0; i < 32768; i++) begin
            if (i == inj_idx) dut.ram.mem[i] = inj_old;
          end
          released = 1;
          $display("FAULT G2: value restored at cycle %0d", cycle);
        end
      end
    end
  end

  // ---- watchdog: 30M cycles (manifest G2) ----
  initial begin
    #(30000000 * 20);
    $display("TB_FAULT_CTX: FAIL: watchdog timeout (cycle %0d)", cycle);
    $fatal(1);
  end

  // ---- main ----
  initial begin
    repeat (10) @(posedge clk);
    rst = 1'b0;
    $display("TB_FAULT_CTX: reset released");

    wait (saw_fail || saw_pass);
    repeat (100) @(posedge clk);

    if (saw_pass)
      tb_fail("firmware printed TEST regtest PASS: fault did not activate");
    if (!injected)
      tb_fail("never saw MARK ctxsave: fault did not activate");

    $display("FAULT G2: ACTIVATED (bit flip at cycle %0d addr 0x%08x old=0x%08x new=0x%08x), CHECKER REJECTED (firmware TEST regtest FAIL)",
             inj_cycle, inj_addr, inj_old, inj_new);
    $display("TB_FAULT_CTX: ALL PASS");
    $finish;
  end

endmodule

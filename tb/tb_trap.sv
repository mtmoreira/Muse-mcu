`timescale 1ns/1ps
// tb_trap.sv -- A4: synchronous trap behavior.
// prog_trap.S installs a direct-mtvec handler logging
// [caseid, exp_mepc, mcause, mepc, mtval] per trap to SRAM 0x10000.
// Checks 8/8: mcause/mepc/mtval per the RISC-V privileged spec (M-mode),
// plus an independent dbg_trap_taken cause sequence [2,11,3,4,6,4,1,7].
module tb_trap;
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

  string h;
  int unsigned cycles;
  // SRAM byte 0x10000 -> word index 0x4000 (bus uses addr[16:2]).
  localparam int LOG_WIDX  = 32'h4000;
  localparam int DONE_WIDX = 32'h4045; // byte 0x10114

  logic [31:0] exp_cause [0:7];
  logic [31:0] exp_mtval [0:7];
  logic [31:0] trap_seq [$];

  // Independent trap-cause observation at instruction boundaries.
  always @(negedge clk) begin
    if (!rst && dbg_trap_taken) trap_seq.push_back(dbg_mcause);
  end

  function automatic logic [31:0] logw(input int i);
    return dut.ram.mem[LOG_WIDX + i];
  endfunction

  initial begin
    exp_cause[0] = 32'd2;  exp_mtval[0] = 32'hFFFFFFFF; // illegal
    exp_cause[1] = 32'd11; exp_mtval[1] = 32'h0;        // ecall
    exp_cause[2] = 32'd3;  exp_mtval[2] = 32'h0;        // ebreak
    exp_cause[3] = 32'd4;  exp_mtval[3] = 32'h00010001; // misaligned LW
    exp_cause[4] = 32'd6;  exp_mtval[4] = 32'h00010003; // misaligned SW
    exp_cause[5] = 32'd4;  exp_mtval[5] = 32'h00010001; // misaligned LH
    exp_cause[6] = 32'd1;  exp_mtval[6] = 32'h20000000; // fetch unmapped
    exp_cause[7] = 32'd7;  exp_mtval[7] = 32'h20000000; // store unmapped

    if (!$value$plusargs("hex=%s", h)) begin
      $display("TB_TRAP: FAIL: missing +hex"); $fatal(1, "TB_TRAP FAIL");
    end
    $readmemh(h, dut.rom.mem);

    repeat (8) @(posedge clk);
    @(negedge clk);
    rst = 0;

    cycles = 0;
    while (dut.ram.mem[DONE_WIDX] !== 32'hDEADBEEF) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 500000) begin
        $display("TB_TRAP: FAIL: timeout waiting DONE (traps seen=%0d)",
                 trap_seq.size());
        $fatal(1, "TB_TRAP FAIL");
      end
    end

    // Check 1: independent trap sequence from dbg pins.
    if (trap_seq.size() != 8) begin
      $display("TB_TRAP: FAIL: trap_seq size %0d != 8", trap_seq.size());
      $fatal(1, "TB_TRAP FAIL");
    end
    for (int i = 0; i < 8; i++) begin
      if (trap_seq[i] !== exp_cause[i]) begin
        $display("TB_TRAP: FAIL: trap_seq[%0d]=%0d expected %0d",
                 i, trap_seq[i], exp_cause[i]);
        $fatal(1, "TB_TRAP FAIL");
      end
    end
    $display("TB_TRAP: dbg trap sequence ok: 2,11,3,4,6,4,1,7");

    // Check 2: per-case log [caseid, exp_mepc, mcause, mepc, mtval].
    for (int i = 0; i < 8; i++) begin
      logic [31:0] cid, emepc, cause, mepc, mtval;
      cid   = logw(5*i+0);
      emepc = logw(5*i+1);
      cause = logw(5*i+2);
      mepc  = logw(5*i+3);
      mtval = logw(5*i+4);
      if ($isunknown({cid, emepc, cause, mepc, mtval})) begin
        $display("TB_TRAP: FAIL: case %0d log has X", i+1);
        $fatal(1, "TB_TRAP FAIL");
      end
      if (cid !== i+1) begin
        $display("TB_TRAP: FAIL: case %0d cid=%0d", i+1, cid);
        $fatal(1, "TB_TRAP FAIL");
      end
      if (cause !== exp_cause[i]) begin
        $display("TB_TRAP: FAIL: case %0d mcause=%0d expected %0d",
                 i+1, cause, exp_cause[i]);
        $fatal(1, "TB_TRAP FAIL");
      end
      if (mepc !== emepc) begin
        $display("TB_TRAP: FAIL: case %0d mepc=%h expected %h",
                 i+1, mepc, emepc);
        $fatal(1, "TB_TRAP FAIL");
      end
      if (mtval !== exp_mtval[i]) begin
        $display("TB_TRAP: FAIL: case %0d mtval=%h expected %h",
                 i+1, mtval, exp_mtval[i]);
        $fatal(1, "TB_TRAP FAIL");
      end
      $display("TB_TRAP: case %0d ok: cause=%0d mepc=%h mtval=%h",
               i+1, cause, mepc, mtval);
    end

    $display("TB_TRAP: ALL PASS (8/8)");
    $finish;
  end

  // Watchdog: 500k sim cycles per the manifest.
  initial begin
    #(500000*20);
    $display("TB_TRAP: FAIL: global timeout"); $fatal(1, "TB_TRAP FAIL");
  end
endmodule

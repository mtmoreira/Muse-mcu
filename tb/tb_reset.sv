`timescale 1ns/1ps
// tb_reset.sv -- A3: reset and startup behavior.
// Hold rst for N cycles (N in {1,8,100} selected by +seed=1/2/3), then check:
//   - dbg_pc==0 within 2 cycles of release, no X on dbg_pc/dbg_mcause
//   - the first retiring instruction is the reset-vector word (PC 0)
//   - CSR dump from prog_reset.S: mstatus/mie/mtvec/mscratch/mepc/mcause/
//     mtval==0, misa==0x40000100, mip==0; regfile all zero (else 0xDEADDEAD)
module tb_reset;
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

  int N, seed;
  string h;
  logic [31:0] word0;
  int unsigned cycles;
  // Bus maps SRAM byte address A to word index A[16:2] (no base subtraction):
  // byte 0x10000 -> mem[0x4000].
  localparam int SRAM_BASE_WIDX = 32'h4000;

  task check_csr(input int idx, input string cname, input logic [31:0] exp);
    logic [31:0] v;
    v = dut.ram.mem[idx];
    if ($isunknown(v)) begin
      $display("TB_RESET: FAIL: csr %s is X", cname); $fatal(1, "TB_RESET FAIL");
    end
    if (v !== exp) begin
      $display("TB_RESET: FAIL: csr %s=%h expected %h", cname, v, exp);
      $fatal(1, "TB_RESET FAIL");
    end
    $display("TB_RESET: csr %s=%h ok", cname, v);
  endtask

  initial begin
    if (!$value$plusargs("hex=%s", h)) begin
      $display("TB_RESET: FAIL: missing +hex"); $fatal(1, "TB_RESET FAIL");
    end
    if (!$value$plusargs("seed=%d", seed)) seed = 1;
    case (seed)
      1: N = 1;
      2: N = 8;
      3: N = 100;
      default: begin
        $display("TB_RESET: FAIL: bad +seed=%0d", seed); $fatal(1, "TB_RESET FAIL");
      end
    endcase
    $readmemh(h, dut.rom.mem);
    word0 = dut.rom.mem[0];
    if ($isunknown(word0)) begin
      $display("TB_RESET: FAIL: rom word0 X"); $fatal(1, "TB_RESET FAIL");
    end

    repeat (N) @(posedge clk);
    @(negedge clk);
    rst = 0;
    #1;
    // PC must be 0 right after release (within 2 cycles), with no X.
    if ($isunknown(dbg_pc)) begin
      $display("TB_RESET: FAIL: dbg_pc X after release"); $fatal(1, "TB_RESET FAIL");
    end
    if (dbg_pc !== 32'h0) begin
      $display("TB_RESET: FAIL: dbg_pc=%h after release, expected 0", dbg_pc);
      $fatal(1, "TB_RESET FAIL");
    end
    // First retiring instruction must be the reset-vector word at PC 0.
    if (dbg_instr_valid !== 1'b1) begin
      $display("TB_RESET: FAIL: no instruction retiring right after release");
      $fatal(1, "TB_RESET FAIL");
    end
    if ($isunknown(dbg_mcause)) begin
      $display("TB_RESET: FAIL: dbg_mcause X"); $fatal(1, "TB_RESET FAIL");
    end
    $display("TB_RESET: seed=%0d N=%0d pc=0 first_retire_ok rom0=%h",
             seed, N, word0);

    // Wait for the program's DONE marker (0x10024 -> ram word 0x4009).
    cycles = 0;
    while (dut.ram.mem[SRAM_BASE_WIDX+9] !== 32'hDEADBEEF &&
           dut.ram.mem[SRAM_BASE_WIDX+9] !== 32'hDEADDEAD) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 100000) begin
        $display("TB_RESET: FAIL: timeout waiting for DONE");
        $fatal(1, "TB_RESET FAIL");
      end
      if ($isunknown(dbg_pc)) begin
        $display("TB_RESET: FAIL: dbg_pc X at cycle %0d", cycles);
        $fatal(1, "TB_RESET FAIL");
      end
    end
    if (dut.ram.mem[SRAM_BASE_WIDX+9] === 32'hDEADDEAD) begin
      $display("TB_RESET: FAIL: regfile had nonzero register");
      $fatal(1, "TB_RESET FAIL");
    end

    check_csr(SRAM_BASE_WIDX+0, "mstatus",  32'h00000000);
    check_csr(SRAM_BASE_WIDX+1, "mie",      32'h00000000);
    check_csr(SRAM_BASE_WIDX+2, "mtvec",    32'h00000000);
    check_csr(SRAM_BASE_WIDX+3, "mscratch", 32'h00000000);
    check_csr(SRAM_BASE_WIDX+4, "mepc",     32'h00000000);
    check_csr(SRAM_BASE_WIDX+5, "mcause",   32'h00000000);
    check_csr(SRAM_BASE_WIDX+6, "mtval",    32'h00000000);
    check_csr(SRAM_BASE_WIDX+7, "misa",     32'h40000100);
    check_csr(SRAM_BASE_WIDX+8, "mip",      32'h00000000);

    $display("TB_RESET: ALL PASS");
    $finish;
  end

  // Watchdog: 100k sim cycles per the manifest.
  initial begin
    #(100000*20);
    $display("TB_RESET: FAIL: global timeout"); $fatal(1, "TB_RESET FAIL");
  end
endmodule

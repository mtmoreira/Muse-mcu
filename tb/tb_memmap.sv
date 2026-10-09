`timescale 1ns/1ps
// tb_memmap.sv -- A6: memory map and access widths.
// prog_memmap.S performs 40 directed accesses, logging 3 words
// [status, actual, expected] per test to SRAM 0x12000
// (status = id, or 0x80000000|id on fail). Tests 39/40 log
// [status, mcause, mtval] from the trap handler.
// The tb requires 40/40 pass and independently re-checks test 1 (LW of the
// ROM last word) against the loaded image, plus the trap causes.
module tb_memmap;
  logic clk=0, rst=1;
  logic uart_tx, uart_rx=1;
  logic spi_sck, spi_mosi, spi_cs_n, spi_miso=1;
  logic [7:0] gpio_in, gpio_out, gpio_oe;
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
  // SRAM byte 0x12000 -> word 0x4800; DONE byte 0x121E0 -> word 0x4878.
  localparam int LOG_W  = 32'h4800;
  localparam int DONE_W = 32'h4878;

  initial begin
    gpio_in = 8'h5A; // test 26 reads GPIO data_in
    if (!$value$plusargs("hex=%s", h)) begin
      $display("TB_MEMMAP: FAIL: missing +hex"); $fatal(1, "TB_MEMMAP FAIL");
    end
    $readmemh(h, dut.rom.mem);

    repeat (8) @(posedge clk);
    @(negedge clk);
    rst = 0;

    cycles = 0;
    while (dut.ram.mem[DONE_W] !== 32'hDEADBEEF) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 200000) begin
        $display("TB_MEMMAP: FAIL: timeout waiting DONE");
        $fatal(1, "TB_MEMMAP FAIL");
      end
    end
    $display("TB_MEMMAP: DONE after %0d cycles", cycles);

    for (int i = 0; i < 40; i++) begin
      logic [31:0] st, v1, v2;
      st = dut.ram.mem[LOG_W + 3*i + 0];
      v1 = dut.ram.mem[LOG_W + 3*i + 1];
      v2 = dut.ram.mem[LOG_W + 3*i + 2];
      if ($isunknown({st, v1, v2})) begin
        $display("TB_MEMMAP: FAIL: test %0d log X", i+1);
        $fatal(1, "TB_MEMMAP FAIL");
      end
      if (st !== (i+1)) begin
        $display("TB_MEMMAP: FAIL: test %0d status=%h (actual=%h expected=%h)",
                 i+1, st, v1, v2);
        $fatal(1, "TB_MEMMAP FAIL");
      end
      // Independent value re-checks.
      if (i+1 == 1) begin
        // LW of ROM last word must equal the loaded image word.
        if (v1 !== dut.rom.mem[32'h3FFF]) begin
          $display("TB_MEMMAP: FAIL: test 1 LW=%h image=%h",
                   v1, dut.rom.mem[32'h3FFF]);
          $fatal(1, "TB_MEMMAP FAIL");
        end
      end else if (i+1 == 39) begin
        if (v1 !== 32'd5 || v2 !== 32'h20000000) begin
          $display("TB_MEMMAP: FAIL: test 39 cause=%0d mtval=%h", v1, v2);
          $fatal(1, "TB_MEMMAP FAIL");
        end
      end else if (i+1 == 40) begin
        if (v1 !== 32'd7 || v2 !== 32'h20000000) begin
          $display("TB_MEMMAP: FAIL: test 40 cause=%0d mtval=%h", v1, v2);
          $fatal(1, "TB_MEMMAP FAIL");
        end
      end else begin
        if (v1 !== v2) begin
          $display("TB_MEMMAP: FAIL: test %0d actual=%h != expected=%h",
                   i+1, v1, v2);
          $fatal(1, "TB_MEMMAP FAIL");
        end
      end
    end

    $display("TB_MEMMAP: ALL PASS (40/40)");
    $finish;
  end

  // Watchdog: 200k sim cycles per the manifest.
  initial begin
    #(200000*20);
    $display("TB_MEMMAP: FAIL: global timeout"); $fatal(1, "TB_MEMMAP FAIL");
  end
endmodule

`timescale 1ns/1ps
// tb_arch.sv -- A1/A2: riscv-arch-test signature capture.
// Loads fw/build/arch/<name>.hex (via +hex=, test name via +name=).
// The arch-test shim writes PASS_MAGIC (0xDEADBEEF) or FAIL_MAGIC (0xDEADDEAD)
// to DONE_ADDR 0x0001FFF0 and the signature to SIGBASE 0x00018000
// (word count in the first word), then ends with ecall (mcause 11).
// On PASS the tb dumps the signature words to +sigfile= for the golden
// comparison (tools/check_arch.py). Per-test watchdog: 2M cycles.
module tb_arch;
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

  // Bus maps SRAM byte A to word index A[16:2] (no base subtraction).
  localparam int DONE_WIDX = 32'h7FFC; // 0x0001FFF0
  localparam int DEFAULT_SIG_WIDX = 32'h6000; // 0x00018000
  localparam logic [31:0] PASS_MAGIC = 32'hDEADBEEF;
  localparam logic [31:0] FAIL_MAGIC = 32'hDEADDEAD;
  // Largest flat .hex image: arch_jal.ld XMEM is 192 KiB = 49152 words.
  localparam int HEX_MAX = 65536;

  string h, tname, sigpath, sigbase_s;
  int unsigned cycles, sig_widx;
  logic ecall_seen;

  always @(negedge clk) begin
    if (!rst && dbg_trap_taken && dbg_mcause == 32'd11) ecall_seen = 1'b1;
  end

  initial begin
    int fd, nwords, i;
    logic [31:0] done, count;
    logic [31:0] heximg [0:HEX_MAX-1];
    logic [31:0] dummy;
    if (!$value$plusargs("hex=%s", h)) begin
      $display("TB_ARCH: FAIL: missing +hex"); $fatal(1, "TB_ARCH FAIL");
    end
    if (!$value$plusargs("name=%s", tname)) tname = "unknown";
    if (!$value$plusargs("sigfile=%s", sigpath)) begin
      $display("TB_ARCH: FAIL: missing +sigfile"); $fatal(1, "TB_ARCH FAIL");
    end
    // Per-test signature word index (default 0x6000 = 0x00018000;
    // I-jal-00 uses 0x9000 = 0x00024000). Passed by tb/run_arch.sh from
    // fw/build/arch/sigbase.json (hex digits, no 0x prefix).
    sig_widx = DEFAULT_SIG_WIDX;
    if ($value$plusargs("sigbase=%s", sigbase_s)) begin
      if ($sscanf(sigbase_s, "%h", sig_widx) != 1) begin
        $display("TB_ARCH: FAIL: bad +sigbase=%s", sigbase_s);
        $fatal(1, "TB_ARCH FAIL");
      end
    end

    // The .hex is a flat 32-bit word image from byte 0x0: words [0:16384)
    // go to ROM, words [16384:] to SRAM at word index 0x4000+i
    // (SRAM word index is byte_addr[16:2], no base subtraction).
    fd = $fopen(h, "r");
    if (fd == 0) begin
      $display("TB_ARCH: FAIL: cannot open %s", h); $fatal(1, "TB_ARCH FAIL");
    end
    nwords = 0;
    while (!$feof(fd)) begin
      if ($fscanf(fd, "%h", dummy) == 1) nwords = nwords + 1;
    end
    $fclose(fd);
    if (nwords == 0 || nwords > HEX_MAX) begin
      $display("TB_ARCH: FAIL: bad hex length %0d", nwords);
      $fatal(1, "TB_ARCH FAIL");
    end
    $readmemh(h, heximg);
    for (i = 0; i < 16384 && i < nwords; i = i + 1)
      dut.rom.mem[i] = heximg[i];
    // SRAM word index is byte_addr[16:2] truncated to the 15-bit SRAM
    // index (bus_interconnect.sv), so mask to [14:0] exactly like the bus.
    // This matters for I-jal-00: its signature lives at byte 0x00024000
    // (word 0x9000), which the bus aliases to mem[0x1000].
    for (i = 16384; i < nwords; i = i + 1)
      dut.ram.mem[(32'h4000 + (i - 16384)) & 32'h7FFF] = heximg[i];
    $display("TB_ARCH %s: loaded %0d words, sig_widx=%h", tname, nwords, sig_widx);

    repeat (8) @(posedge clk);
    @(negedge clk);
    rst = 0;
    ecall_seen = 1'b0;

    cycles = 0;
    done = dut.ram.mem[DONE_WIDX];
    while (done !== PASS_MAGIC && done !== FAIL_MAGIC && !ecall_seen) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > 2000000) begin
        $display("TB_ARCH %s: FAIL: timeout (2M cycles)", tname);
        $fatal(1, "TB_ARCH FAIL");
      end
      done = dut.ram.mem[DONE_WIDX];
    end

    if (done === FAIL_MAGIC) begin
      $display("TB_ARCH %s: FAIL: target reported FAIL_MAGIC", tname);
      $fatal(1, "TB_ARCH FAIL");
    end
    if (done !== PASS_MAGIC) begin
      $display("TB_ARCH %s: FAIL: ecall without PASS_MAGIC (done=%h)",
               tname, done);
      $fatal(1, "TB_ARCH FAIL");
    end

    // Dump the signature: word count in first word, then the words.
    // Mask to the 15-bit SRAM index like the bus (see load loop above).
    count = dut.ram.mem[sig_widx & 32'h7FFF];
    if ($isunknown(count) || count == 0 || count > 4096) begin
      $display("TB_ARCH %s: FAIL: bad signature count %h", tname, count);
      $fatal(1, "TB_ARCH FAIL");
    end
    fd = $fopen(sigpath, "w");
    if (fd == 0) begin
      $display("TB_ARCH %s: FAIL: cannot open %s", tname, sigpath);
      $fatal(1, "TB_ARCH FAIL");
    end
    for (int i = 0; i < count; i++) begin
      logic [31:0] w;
      w = dut.ram.mem[(sig_widx + 1 + i) & 32'h7FFF];
      if ($isunknown(w)) begin
        $display("TB_ARCH %s: FAIL: signature word %0d X", tname, i);
        $fclose(fd);
        $fatal(1, "TB_ARCH FAIL");
      end
      $fwrite(fd, "%08h\n", w);
    end
    $fclose(fd);
    $display("TB_ARCH %s: PASS sig_words=%0d", tname, count);
    $finish;
  end
endmodule

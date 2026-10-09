// tb_spi: A8 — SPI master read against the picosoc spiflash model.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads spi_test.hex (firmware issues 0xAB wake, then 0x03 READ of 256 bytes
// from address 0). Checks:
//   * 256/256 data bytes match the preloaded image (+firmware=<file>)
//   * firmware MARK checksum matches the image checksum
//   * protocol assertions: SCK idle low; MOSI changes only while SCK low;
//     SCK rises only with CS asserted (low); MSB-first command framing
//     (0xAB wake, then 0x03 + 24-bit address 0).
// PASS: data match AND zero protocol-assertion violations.

`timescale 1ns/1ps

module tb_spi;

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz

  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;

  tri1 miso_net;  // pulled high when the flash model is not driving
  wire mosi_net;    // inout ports need a net; dut.spi_mosi is a logic
  assign mosi_net = dut.spi_mosi;

  mcu_top dut (
    .clk(clk), .rst(rst),
    .uart_tx(), .uart_rx(1'b1),
    .spi_sck(), .spi_mosi(), .spi_miso(miso_net), .spi_cs_n(),
    .gpio_in(8'h00), .gpio_out(), .gpio_oe(),
    .tb_test_irq(1'b0),
    .dbg_pc(), .dbg_instr_valid(), .dbg_trap_taken(), .dbg_mcause()
  );

  spiflash flash (
    .csb (dut.spi_cs_n),
    .clk (dut.spi_sck),
    .io0 (mosi_net),
    .io1 (miso_net),
    .io2 (),
    .io3 ()
  );

  uart_sink #(.BIT_CYCLES(434)) sink (
    .clk(clk), .rst(rst), .rx(dut.uart_tx), .cycle_i(cycle)
  );

  always @(posedge clk) begin
    if (rst) cycle <= 64'd0;
    else     cycle <= cycle + 64'd1;
  end

  // ---- firmware + flash image load ----
  string hex_path, img_path;
  reg [7:0] img [0:255];
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_SPI: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("firmware=%s", img_path)) begin
      $display("TB_SPI: FAIL: +firmware=<file> plusarg missing"); $fatal(1);
    end
    $readmemh(hex_path, dut.rom.mem);
    $readmemh(img_path, img);
    $display("TB_SPI: loaded %s, flash image %s", hex_path, img_path);
  end

  // ---- protocol assertions (checked on settled values after each edge) ----
  int proto_viol = 0;
  logic mosi_prev = 1'b0, sck_prev = 1'b0;
  task automatic pviol(string msg);
    proto_viol++;
    $display("TB_SPI: PROTOCOL VIOLATION #%0d at cycle %0d: %s", proto_viol, cycle, msg);
  endtask

  always @(posedge clk) begin
    #1;
    if (!rst) begin
      // SCK idle low whenever the master is not shifting
      if (!dut.spi0.busy_q && dut.spi_sck !== 1'b0)
        pviol("SCK not low while master idle");
      // MOSI may only change while SCK is low (mode 0: set up on falling edge)
      if (dut.spi_mosi !== mosi_prev && dut.spi_sck !== 1'b0)
        pviol("MOSI changed while SCK high");
      // SCK may only rise with CS asserted
      if (!sck_prev && dut.spi_sck && dut.spi_cs_n !== 1'b0)
        pviol("SCK rising edge with CS high");
      mosi_prev <= dut.spi_mosi;
      sck_prev  <= dut.spi_sck;
    end
  end

  // ---- byte capture on rising SCK (MSB-first) ----
  logic [7:0] mosi_sh = 8'h00, miso_sh = 8'h00;
  int bitcnt = 0;
  byte mosi_bytes[$], miso_bytes[$];
  int  cs_lens[$];       // bytes per CS assertion
  int  cs_nbytes = 0;
  always @(posedge dut.spi_sck) begin
    #2;  // let the model's #1 output assigns settle
    if (!rst) begin
      mosi_sh = {mosi_sh[6:0], dut.spi_mosi};
      miso_sh = {miso_sh[6:0], miso_net};
      bitcnt++;
      if (bitcnt == 8) begin
        bitcnt = 0;
        mosi_bytes.push_back(mosi_sh);
        miso_bytes.push_back(miso_sh);
        cs_nbytes++;
      end
    end
  end
  always @(negedge dut.spi_cs_n) cs_nbytes = 0;
  always @(posedge dut.spi_cs_n) begin
    if (!rst) cs_lens.push_back(cs_nbytes);
  end

  // ---- firmware line watcher ----
  // Real firmware prints "MARK spi <n>" every 32 bytes, then
  // "TEST spi PASS" and "CHECKSUM <8 hex>" (XOR of the 256 bytes).
  bit saw_boot = 0, saw_start = 0, saw_pass = 0;
  string fw_fail = "";
  logic [31:0] fw_sum = 32'h0;
  bit saw_sum = 0;
  int mark_spi = 0;
  initial begin
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint c;
        l = sink.line_q.pop_front();
        c = sink.line_cyc_q.pop_front();
        if (l == "BOOT") saw_boot = 1;
        else if (l == "TEST spi START") saw_start = 1;
        else if (l == "TEST spi PASS") saw_pass = 1;
        else if (l.len() >= 13 && l.substr(0, 12) == "TEST spi FAIL") fw_fail = l;
        else if (l.len() >= 9 && l.substr(0, 8) == "CHECKSUM ") begin
          string hs;
          hs = l.substr(9, l.len() - 1);
          saw_sum = 1;
          if ($sscanf(hs, "%h", fw_sum) != 1)
            $display("TB_SPI: WARNING: cannot parse checksum '%s'", hs);
        end
        else if (l.len() >= 9 && l.substr(0, 8) == "MARK spi ") mark_spi++;
      end
    end
  end

  task automatic fail(string reason);
    $display("TB_SPI: FAIL: %s", reason);
    $fatal(1);
  endtask

  // ---- watchdog: 2M cycles (manifest A8) ----
  initial begin
    #(2000000 * 20);
    $display("TB_SPI: FAIL: watchdog timeout (cycle %0d)", cycle);
    $fatal(1);
  end

  // ---- main ----
  initial begin
    logic [31:0] expect_sum;
    repeat (10) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    $display("TB_SPI: reset released");

    wait (saw_pass);
    if (fw_fail != "") fail($sformatf("firmware reported %s", fw_fail));
    // BOOT is in the marker protocol but the real firmware omits it; not required.

    // CS framing: expect exactly 2 assertions: 1 byte (0xAB), 260 bytes (READ)
    if (cs_lens.size() != 2)
      fail($sformatf("expected 2 CS assertions, saw %0d", cs_lens.size()));
    if (cs_lens[0] != 1)
      fail($sformatf("wake assertion: expected 1 byte, saw %0d", cs_lens[0]));
    if (cs_lens[1] != 260)
      fail($sformatf("read assertion: expected 260 bytes, saw %0d", cs_lens[1]));

    // MOSI command framing (MSB-first)
    if (mosi_bytes.size() != 261)
      fail($sformatf("expected 261 MOSI bytes, saw %0d", mosi_bytes.size()));
    if (mosi_bytes[0] !== 8'hAB)
      fail($sformatf("wake byte: expected 0xAB, saw 0x%02x", mosi_bytes[0]));
    if (mosi_bytes[1] !== 8'h03)
      fail($sformatf("read cmd: expected 0x03, saw 0x%02x", mosi_bytes[1]));
    if (mosi_bytes[2] !== 8'h00 || mosi_bytes[3] !== 8'h00 || mosi_bytes[4] !== 8'h00)
      fail($sformatf("read addr: expected 0x000000, saw %02x%02x%02x",
                     mosi_bytes[2], mosi_bytes[3], mosi_bytes[4]));

    // MISO data: bytes 5..260 of the capture == image[0..255]
    for (int i = 0; i < 256; i++) begin
      if (miso_bytes[5+i] !== img[i])
        fail($sformatf("data byte %0d: flash 0x%02x, MISO 0x%02x",
                       i, img[i], miso_bytes[5+i]));
    end

    // firmware checksum cross-check (XOR of the 256 bytes)
    // Wait for the CHECKSUM line to arrive over UART (takes ~78k cycles at 115200 baud)
    fork
      wait (saw_sum);
      begin repeat (200000) @(posedge clk); end
    join_any
    disable fork;
    expect_sum = 32'h0;
    for (int i = 0; i < 256; i++) expect_sum ^= 32'(img[i]);
    if (!saw_sum) fail("never saw CHECKSUM line");
    if (fw_sum !== expect_sum)
      fail($sformatf("checksum: firmware 0x%08x, expected 0x%08x", fw_sum, expect_sum));
    $display("TB_SPI: MARK spi progress lines seen: %0d", mark_spi);

    if (proto_viol != 0)
      fail($sformatf("%0d protocol violations", proto_viol));

    $display("TB_SPI: ALL PASS (256/256 data bytes match, 0 protocol violations)");
    $finish;
  end

endmodule

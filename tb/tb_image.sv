// tb_image: visual demo (spec v1.0) testbench.
//
// Drives image_demo firmware on the real pins:
//   - SPI flash model preloaded with the MIMG flash image (+firmware=).
//   - UART TX pin decoded by tb/uart_sink; every byte is captured raw
//     to <outdir>/uart_capture.bin (the packet) and counted.
//   - Every committed SRAM write (posedge clk with d_wstrb != 0) is
//     logged to <outdir>/writes.csv: cycle, byte addr, data, strobes.
//   - GPIO debug-scratch trace changes logged to <outdir>/events.csv.
//   - Optional testbench-only fault (+fault=1): flip bit 7 of the
//     output framebuffer byte at +out_base+2080 on its writeback-phase
//     write, once, at the SRAM write boundary (see fault.json).
//   - End check: after the +pkt_bytes-th byte, a 50,000-cycle
//     observation window must contain no further byte.
//   - Watchdog: 100,000,000 cycles from reset release.
//   - Stage VCD windows (sequential, one dumpfile at a time):
//       stage02_load_overview.vcd  reset -> load-done trace
//       stage05_rtos.vcd           load-done -> combine stripe 2
//       stage06_writeback.vcd      stripe 7 done -> stripe 8 done
//       stage07_uart.vcd           UART bytes 2000..2010
//     (stage03's detail window is sliced from stage02's file by the
//     host tools using the anchors this tb prints.)
//
// The tb judges PROTOCOL completeness only (packet length, boundary,
// watchdog). Image correctness is the host checker's job; this tb
// never reads +fault or any expected image data.

`timescale 1ns/1ps

module tb_image;

  localparam int PKT_DEFAULT = 4148; // 20 hdr + 4096 px + 32 digest

  logic clk = 1'b0;
  always #10 clk = ~clk;  // 50 MHz
  logic rst = 1'b1;
  logic [63:0] cycle = 64'd0;

  tri1 miso_net;
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

  // ---------------- plusargs ----------------
  string hex_path, outdir;
  int fault_en, pkt_bytes;
  int in_base, gx_base, gy_base, out_base;
  int target_addr;

  // ---------------- files ----------------
  integer uartfd, wfd, efd;
  int byte_total = 0;
  longint pkt_last_cycle = -1;
  int extra_bytes = 0;

  // ---------------- fault state ----------------
  bit fault_armed = 0, fault_fired = 0;
  longint fault_cycle = -1;
  int fault_intended = -1, fault_committed = -1;
  int fault_be = 0;

  // ---------------- trace / window state ----------------
  logic [31:0] last_scratch = 32'hdeadbeef;
  int cs_count = 0;
  longint cs35_start = -1, cs35_end = -1;
  int win_state = 0; // 0 none, 1 W02, 2 W05, 3 W06, 4 W07
  longint win_close_cycle = -1;

  task automatic dump_on(input string path);
    begin
      $dumpfile(path);
      $dumpvars(0, clk, rst, dut.spi_cs_n, dut.spi_sck, dut.spi_mosi,
                dut.spi_miso, dut.uart_tx, dut.ram.d_wstrb,
                dut.ram.d_waddr, dut.ram.d_wdata, dut.gpio0.scratch_q,
                dut.dbg_pc, dut.dbg_trap_taken, dut.dbg_mcause);
      $dumpon;
    end
  endtask

  // cycle counter
  always @(posedge clk) if (!rst) cycle <= cycle + 1;

  // ---------------- UART capture ----------------
  // Poll the sink queue per clock (tb_app's lesson: byte_ev events do
  // not persist and must not be waited on).
  bit files_open = 0;
  initial begin
    wait (files_open);
    forever begin
      @(posedge clk);
      while (sink.byte_q.size() > 0) begin
        byte b;
        b = sink.byte_q.pop_front();
        $fwrite(uartfd, "%c", b);
        byte_total++;
        if (byte_total == pkt_bytes) pkt_last_cycle = cycle;
        if (pkt_last_cycle >= 0 && byte_total > pkt_bytes) extra_bytes++;
        if (byte_total == 2000 && win_state == 0) begin
          dump_on({outdir, "/stage07_uart.vcd"});
          win_state = 4;
        end
        if (byte_total == 2010 && win_state == 4) begin
          $dumpoff;
          win_state = 0;
        end
      end
    end
  end

  // ---------------- SRAM committed writes ----------------
  int wcount = 0;
  always @(posedge clk) begin
    if (!rst && dut.ram.d_wstrb !== 4'b0000) begin
      // Address from the CPU's full 32-bit d_addr (top-level net in
      // mcu_top). The SRAM port's own d_waddr is only 15 bits and
      // drops address bit 17, which aliases the buffer ranges.
      $fwrite(wfd, "%0d,0x%08x,0x%08x,0x%01x\n", cycle,
              dut.d_addr & 32'hFFFFFFFC,
              dut.ram.d_wdata, dut.ram.d_wstrb);
      wcount++;
      if (wcount % 20000 == 0) $fflush(wfd);
    end
  end

  // ---------------- trace events + window control ----------------
  always @(posedge clk) begin
    if (!rst && dut.gpio0.scratch_q !== last_scratch) begin
      logic [31:0] v;
      v = dut.gpio0.scratch_q;
      last_scratch = v;
      $fwrite(efd, "%0d,0x%08x\n", cycle, v);
      $fflush(efd);
      if (v >= 32'h4000 && v <= 32'h400f) fault_armed = 1;
      // window transitions
      if (v == 32'h1001 && win_state == 1) begin
        $dumpoff;
        dump_on({outdir, "/stage05_rtos.vcd"});
        win_state = 2;
      end
      if (v == 32'h4002 && win_state == 2) begin
        win_close_cycle = cycle + 200;
      end
      if (v == 32'h4007 && (win_state == 0 || win_state == 2)) begin
        if (win_state == 2) begin
          $dumpoff;
          win_close_cycle = -1;
        end
        dump_on({outdir, "/stage06_writeback.vcd"});
        win_state = 3;
      end
      if (v == 32'h4008 && win_state == 3) begin
        win_close_cycle = cycle + 300;
      end
    end
    if (win_close_cycle >= 0 && cycle >= win_close_cycle) begin
      $dumpoff;
      win_state = 0;
      win_close_cycle = -1;
    end
  end

  // SPI chip-select transaction counter (stage03 anchors)
  always @(negedge dut.spi_cs_n) begin
    if (!rst) begin
      cs_count++;
      if (cs_count == 35) cs35_start = cycle;
    end
  end
  always @(posedge dut.spi_cs_n) begin
    if (!rst && cs_count == 35 && cs35_end < 0) cs35_end = cycle;
  end

  // ---------------- fault injection ----------------
  // Detect the target write mid-cycle (negedge), force the SRAM data
  // input lane for the committing posedge, release next negedge.
  always @(negedge clk) begin
    if (!rst && fault_en == 1 && fault_armed && !fault_fired) begin
      int baddr;
      baddr = dut.d_addr & 32'hFFFFFFFC;
      if (dut.ram.d_wstrb !== 4'b0000 && baddr == target_addr &&
          dut.ram.d_wstrb[0]) begin
        fault_intended = dut.ram.d_wdata[7:0];
        fault_committed = fault_intended ^ 32'h80;
        fault_be = dut.ram.d_wstrb;
        force dut.ram.d_wdata = {dut.ram.d_wdata[31:8],
                                  fault_committed[7:0]};
        fault_fired = 1;
        fault_cycle = cycle + 1; // commits at the next posedge
      end
    end else if (fault_fired && fault_cycle == cycle) begin
      release dut.ram.d_wdata;
    end
  end

  // ---------------- watchdog ----------------
  initial begin
    wait (!rst);
    repeat (100_000_000) @(posedge clk);
    $display("TB_IMAGE: FAIL: watchdog timeout at cycle %0d (bytes %0d/%0d)",
             cycle, byte_total, pkt_bytes);
    write_result(0, "watchdog");
    $fatal(1);
  end

  task automatic write_result(input int proto_pass, input string why);
    integer jfd;
    begin
      jfd = $fopen({outdir, "/tb_result.json"}, "w");
      $fwrite(jfd, "{\n \"protocol_pass\": %0d,\n \"reason\": \"%s\",\n",
              proto_pass, why);
      $fwrite(jfd, " \"packet_bytes_expected\": %0d,\n \"packet_bytes_seen\": %0d,\n",
              pkt_bytes, byte_total);
      $fwrite(jfd, " \"last_byte_cycle\": %0d,\n \"extra_bytes_in_observation\": %0d,\n",
              pkt_last_cycle, extra_bytes);
      $fwrite(jfd, " \"cs35_start_cycle\": %0d,\n \"cs35_end_cycle\": %0d,\n",
              cs35_start, cs35_end);
      $fwrite(jfd, " \"fault_enabled\": %0d,\n \"fault_fired\": %0d",
              fault_en, fault_fired ? 1 : 0);
      if (fault_fired) begin
        int word;
        // Array index is d_addr[16:2] (bus_interconnect.sv: the SRAM
        // write address is the raw address field, no base offset).
        word = dut.ram.mem[(target_addr >> 2) & 32'h00007FFF];
        $fwrite(jfd,
          ",\n \"fault\": {\"cycle\": %0d, \"addr\": \"0x%08x\", \"be\": \"0x%01x\", \"intended\": \"0x%02x\", \"committed\": \"0x%02x\", \"readback_byte\": \"0x%02x\"}",
          fault_cycle, target_addr, fault_be, fault_intended,
          fault_committed, word[7:0]);
      end
      $fwrite(jfd, "\n");
      $fwrite(jfd, "}\n");
      $fclose(jfd);
    end
  endtask

  // ---------------- main ----------------
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_IMAGE: FAIL: +hex missing"); $fatal(1);
    end
    if (!$value$plusargs("outdir=%s", outdir)) begin
      $display("TB_IMAGE: FAIL: +outdir missing"); $fatal(1);
    end
    if (!$value$plusargs("fault=%d", fault_en)) fault_en = 0;
    if (!$value$plusargs("pkt_bytes=%d", pkt_bytes)) pkt_bytes = PKT_DEFAULT;
    if (!$value$plusargs("in_base=%h", in_base)) in_base = 0;
    if (!$value$plusargs("gx_base=%h", gx_base)) gx_base = 0;
    if (!$value$plusargs("gy_base=%h", gy_base)) gy_base = 0;
    if (!$value$plusargs("out_base=%h", out_base)) begin
      $display("TB_IMAGE: FAIL: +out_base missing"); $fatal(1);
    end
    target_addr = out_base + 2080;

    uartfd = $fopen({outdir, "/uart_capture.bin"}, "wb");
    wfd = $fopen({outdir, "/writes.csv"}, "w");
    efd = $fopen({outdir, "/events.csv"}, "w");
    files_open = 1;
    $fwrite(wfd, "cycle,addr,data,strb\n");
    $fwrite(efd, "cycle,code\n");

    $readmemh(hex_path, dut.rom.mem);  // firmware into boot ROM model
    repeat (10) @(posedge clk);
    rst = 1'b0;
    $display("TB_IMAGE: reset released, fault=%0d, target=0x%08x",
             fault_en, target_addr);
    dump_on({outdir, "/stage02_load_overview.vcd"});
    win_state = 1;

    // completion: packet complete + 50,000 quiet cycles
    wait (pkt_last_cycle >= 0);
    begin
      longint deadline;
      deadline = pkt_last_cycle + 50_000;
      while (cycle < deadline && extra_bytes == 0) @(posedge clk);
    end
    if (extra_bytes == 0) begin
      $display("TB_IMAGE: PROTOCOL PASS (%0d bytes, last at cycle %0d, +50000 quiet)",
               byte_total, pkt_last_cycle);
      write_result(1, "complete");
    end else begin
      $display("TB_IMAGE: FAIL: %0d extra bytes in observation window", extra_bytes);
      write_result(0, "extra-bytes");
    end
    $fclose(uartfd); $fclose(wfd); $fclose(efd);
    $finish;
  end

endmodule

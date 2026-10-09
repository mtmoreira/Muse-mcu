// tb_app: D1 + DEMO1 — SPI -> queue -> SHA-256 -> UART end-to-end.
// Fresh code for the Muse-mcu project (Phase 3b).
//
// Loads app_demo.hex; spiflash model preloaded via +firmware=<flash.hex>.
// The tb parses the same flash image and, live:
//   * on "MARK spi_read <id> <len>"  -> prints "DEMO: SPI read msg <id> len <len>"
//   * on "MARK queue <id>"           -> prints "DEMO: queue handoff <id>"
//   * on "PKT 9E55AA01 <id> <len> <digest>"
//        -> prints "DEMO: SHA-256(<id>) = <digest>", verifies id/len against
//           the flash image and the digest with an in-tb SHA-256, then prints
//           "DEMO: UART pkt <id> verified".
// All UART bytes are captured to +uartlog (default results/raw/demo_uart.log).
// A bounded VCD window (+vcd, +vcdwin) captures clk/rst/SPI/UART/dbg signals.
// On "TEST app_demo PASS" the tb checks:
//   (a) every packet received, in order, digest-verified (live);
//   (b) queue watermark (GPIO dbg_scratch) >= 4;
//   (c) >= 10 "MARK bg" lines AND >= 5 dbg_pc entries into the bg task range
//       (+bg_lo/+bg_hi from ELF symbols).
// Icarus has no $system, so tools/check_app.py runs from run_app.sh as the
// final host gate; the tb prints TB_APP: SIM PASS and the script upgrades to
// TB_APP: ALL PASS only if the host checker also exits 0.

`timescale 1ns/1ps

module tb_app;

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

  always @(posedge clk) begin
    if (rst) cycle <= 64'd0;
    else     cycle <= cycle + 64'd1;
  end

  // ---------------- plusargs ----------------
  string hex_path, img_path, uartlog_path, vcd_path;
  logic [31:0] bg_lo, bg_hi;
  int expect_nmsg, vcd_win;
  int min_watermark, min_bg, min_bg_entries;
  bit have_bg_range;
  initial begin
    if (!$value$plusargs("hex=%s", hex_path)) begin
      $display("TB_APP: FAIL: +hex=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("firmware=%s", img_path)) begin
      $display("TB_APP: FAIL: +firmware=<file> plusarg missing"); $fatal(1);
    end
    if (!$value$plusargs("uartlog=%s", uartlog_path))
      uartlog_path = "results/raw/demo_uart.log";
    if (!$value$plusargs("vcd=%s", vcd_path))
      vcd_path = "results/raw/demo_trace.vcd";
    if (!$value$plusargs("expect_nmsg=%d", expect_nmsg)) expect_nmsg = 24;
    if (!$value$plusargs("vcdwin=%d", vcd_win)) vcd_win = 1000000;
    // D1 acceptance thresholds; the F2 gate subset overrides these via
    // plusargs (fewer messages => less queue pressure / fewer bg marks).
    // The packet checks (count, order, digests) are NOT relaxable.
    if (!$value$plusargs("min_watermark=%d", min_watermark)) min_watermark = 4;
    if (!$value$plusargs("min_bg=%d", min_bg)) min_bg = 10;
    if (!$value$plusargs("min_bg_entries=%d", min_bg_entries)) min_bg_entries = 5;
    have_bg_range = $value$plusargs("bg_lo=%h", bg_lo) &&
                    $value$plusargs("bg_hi=%h", bg_hi);
    $readmemh(hex_path, dut.rom.mem);
    $display("TB_APP: loaded %s", hex_path);
    $display("TB_APP: flash image %s", img_path);
    if (have_bg_range)
      $display("TB_APP: bg range [0x%08x, 0x%08x)", bg_lo, bg_hi);
    else
      $display("TB_APP: WARNING: no bg range (+bg_lo/+bg_hi); preemption check degraded");
  end

  // ---------------- flash image parse ----------------
  byte fbytes[0:65535];
  int msg_id[0:63], msg_len[0:63], msg_off[0:63];
  int nmsg = 0;
  function automatic int le32(int o);
    return {fbytes[o+3], fbytes[o+2], fbytes[o+1], fbytes[o]};
  endfunction
  initial begin
    int off;
    wait (img_path != "");
    $readmemh(img_path, fbytes);
    if (le32(0) != 32'h46534C41) begin
      $display("TB_APP: FAIL: flash magic mismatch"); $fatal(1);
    end
    if (le32(4) != 1) begin
      $display("TB_APP: FAIL: flash version != 1"); $fatal(1);
    end
    nmsg = le32(12);
    $display("TB_APP: flash header: seed=%0d nmsg=%0d", le32(8), nmsg);
    if (nmsg != expect_nmsg) begin
      $display("TB_APP: FAIL: flash has %0d messages, expected %0d", nmsg, expect_nmsg);
      $fatal(1);
    end
    off = 16;
    for (int i = 0; i < nmsg; i++) begin
      msg_id[i]  = le32(off);
      msg_len[i] = le32(off + 4);
      msg_off[i] = off + 8;
      off += 8 + msg_len[i];
    end
    $display("TB_APP: parsed %0d messages", nmsg);
  end

  // ---------------- in-tb SHA-256 (validated vs hashlib, see /tmp/sha256_sv_test) ----------------
  function automatic logic [31:0] Kc(int i);
    case (i)
      0: Kc=32'h428a2f98; 1: Kc=32'h71374491; 2: Kc=32'hb5c0fbcf; 3: Kc=32'he9b5dba5;
      4: Kc=32'h3956c25b; 5: Kc=32'h59f111f1; 6: Kc=32'h923f82a4; 7: Kc=32'hab1c5ed5;
      8: Kc=32'hd807aa98; 9: Kc=32'h12835b01; 10: Kc=32'h243185be; 11: Kc=32'h550c7dc3;
      12: Kc=32'h72be5d74; 13: Kc=32'h80deb1fe; 14: Kc=32'h9bdc06a7; 15: Kc=32'hc19bf174;
      16: Kc=32'he49b69c1; 17: Kc=32'hefbe4786; 18: Kc=32'h0fc19dc6; 19: Kc=32'h240ca1cc;
      20: Kc=32'h2de92c6f; 21: Kc=32'h4a7484aa; 22: Kc=32'h5cb0a9dc; 23: Kc=32'h76f988da;
      24: Kc=32'h983e5152; 25: Kc=32'ha831c66d; 26: Kc=32'hb00327c8; 27: Kc=32'hbf597fc7;
      28: Kc=32'hc6e00bf3; 29: Kc=32'hd5a79147; 30: Kc=32'h06ca6351; 31: Kc=32'h14292967;
      32: Kc=32'h27b70a85; 33: Kc=32'h2e1b2138; 34: Kc=32'h4d2c6dfc; 35: Kc=32'h53380d13;
      36: Kc=32'h650a7354; 37: Kc=32'h766a0abb; 38: Kc=32'h81c2c92e; 39: Kc=32'h92722c85;
      40: Kc=32'ha2bfe8a1; 41: Kc=32'ha81a664b; 42: Kc=32'hc24b8b70; 43: Kc=32'hc76c51a3;
      44: Kc=32'hd192e819; 45: Kc=32'hd6990624; 46: Kc=32'hf40e3585; 47: Kc=32'h106aa070;
      48: Kc=32'h19a4c116; 49: Kc=32'h1e376c08; 50: Kc=32'h2748774c; 51: Kc=32'h34b0bcb5;
      52: Kc=32'h391c0cb3; 53: Kc=32'h4ed8aa4a; 54: Kc=32'h5b9cca4f; 55: Kc=32'h682e6ff3;
      56: Kc=32'h748f82ee; 57: Kc=32'h78a5636f; 58: Kc=32'h84c87814; 59: Kc=32'h8cc70208;
      60: Kc=32'h90befffa; 61: Kc=32'ha4506ceb; 62: Kc=32'hbef9a3f7; 63: Kc=32'hc67178f2;
      default: Kc = 32'h0;
    endcase
  endfunction
  function automatic logic [31:0] ror32(logic [31:0] x, int n);
    return (x >> n) | (x << (32 - n));
  endfunction
  function automatic logic [7:0] padbyte(int off, int len, int padded, int p);
    logic [63:0] bitlen;
    if (p < len) return fbytes[off + p];
    if (p == len) return 8'h80;
    if (p < padded - 8) return 8'h00;
    bitlen = 64'(len) * 8;
    return 8'((bitlen >> (8 * (padded - 1 - p))) & 64'hff);
  endfunction
  function automatic string sha256_hex(int off, int len);
    logic [31:0] h[8];
    logic [31:0] w[64];
    logic [31:0] a,b,c,d,e,f,g,hh,t1,t2,s0,s1,S0,S1,ch,mj;
    int padded, nblocks, bl;
    string s;
    h[0]=32'h6a09e667; h[1]=32'hbb67ae85; h[2]=32'h3c6ef372; h[3]=32'ha54ff53a;
    h[4]=32'h510e527f; h[5]=32'h9b05688c; h[6]=32'h1f83d9ab; h[7]=32'h5be0cd19;
    padded = len + 1;
    while ((padded % 64) != 56) padded++;
    padded += 8;
    nblocks = padded / 64;
    for (bl = 0; bl < nblocks; bl++) begin
      for (int i = 0; i < 16; i++)
        w[i] = {padbyte(off,len,padded,bl*64+4*i), padbyte(off,len,padded,bl*64+4*i+1),
                padbyte(off,len,padded,bl*64+4*i+2), padbyte(off,len,padded,bl*64+4*i+3)};
      for (int i = 16; i < 64; i++) begin
        s0 = ror32(w[i-15],7) ^ ror32(w[i-15],18) ^ (w[i-15] >> 3);
        s1 = ror32(w[i-2],17) ^ ror32(w[i-2],19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
      end
      a=h[0]; b=h[1]; c=h[2]; d=h[3]; e=h[4]; f=h[5]; g=h[6]; hh=h[7];
      for (int i = 0; i < 64; i++) begin
        S1 = ror32(e,6) ^ ror32(e,11) ^ ror32(e,25);
        ch = (e & f) ^ (~e & g);
        t1 = hh + S1 + ch + Kc(i) + w[i];
        S0 = ror32(a,2) ^ ror32(a,13) ^ ror32(a,22);
        mj = (a & b) ^ (a & c) ^ (b & c);
        t2 = S0 + mj;
        hh=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
      end
      h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
    end
    s = "";
    for (int i = 0; i < 8; i++) s = $sformatf("%s%08x", s, h[i]);
    return s;
  endfunction

  // ---------------- UART log capture ----------------
  int uartlog_fd;
  initial begin
    wait (uartlog_path != "");
    uartlog_fd = $fopen(uartlog_path, "w");
    if (uartlog_fd == 0) begin
      $display("TB_APP: FAIL: cannot open uart log %s", uartlog_path); $fatal(1);
    end
  end
  initial begin
    wait (uartlog_fd != 0);
    forever begin
      // Poll the queue; do NOT wait on sink.byte_ev (events don't persist;
      // a trigger that fires before the waiter starts is missed forever).
      while (sink.byte_q.size() == 0) @(posedge clk);
      $fwrite(uartlog_fd, "%c", sink.byte_q.pop_front());
    end
  end

  // ---------------- VCD bounded window ----------------
  bit vcd_started = 0, vcd_stopped = 0;
  longint vcd_start_cyc = 0;
  initial begin
    wait (vcd_path != "");
    $dumpfile(vcd_path);
    $dumpvars(0, dut.clk, dut.rst, dut.spi_sck, dut.spi_mosi, dut.spi_miso,
                 dut.spi_cs_n, dut.uart_tx, dut.dbg_pc, dut.dbg_trap_taken);
    $dumpoff;
    $display("TB_APP: VCD %s armed (window %0d cycles from first CS)", vcd_path, vcd_win);
  end
  always @(negedge dut.spi_cs_n) begin
    if (!rst && !vcd_started) begin
      vcd_started = 1;
      vcd_start_cyc = cycle;
      $dumpon;
    end
  end
  always @(posedge clk) begin
    if (vcd_started && !vcd_stopped && (cycle - vcd_start_cyc) > longint'(vcd_win)) begin
      vcd_stopped = 1;
      $dumpoff;
      $display("TB_APP: VCD window closed at cycle %0d", cycle);
    end
  end

  // ---------------- bg task preemption tracking ----------------
  int bg_entries = 0;
  bit was_in_bg = 0;
  always @(posedge clk) begin
    #1;
    if (!rst && have_bg_range) begin
      bit in_bg;
      in_bg = dut.dbg_instr_valid && (dut.dbg_pc >= bg_lo) && (dut.dbg_pc < bg_hi);
      if (in_bg && !was_in_bg) bg_entries++;
      was_in_bg = in_bg;
    end
  end

  // ---------------- line processor + DEMO narration ----------------
  bit saw_boot = 0, saw_start = 0, saw_pass = 0;
  string fw_fail = "";
  int pkt_count = 0, mark_bg = 0;
  int pkt_verified = 0;

  task automatic fail(string reason);
    $display("TB_APP: FAIL: %s", reason);
    if (uartlog_fd != 0) $fclose(uartlog_fd);
    $fatal(1);
  endtask

  function automatic string tolower64(string s);
    string r;
    r = "";
    for (int i = 0; i < s.len(); i++) begin
      byte ch;
      ch = s[i];
      if (ch >= "A" && ch <= "F") ch = ch + 32;
      r = $sformatf("%s%c", r, ch);
    end
    return r;
  endfunction

  initial begin
    wait (nmsg > 0);
    forever begin
      @(sink.line_ev);
      while (sink.line_q.size() > 0) begin
        string l;
        longint lc;
        l = sink.line_q.pop_front();
        lc = sink.line_cyc_q.pop_front();
        if (l == "BOOT") saw_boot = 1;
        else if (l == "TEST app_demo START") saw_start = 1;
        else if (l == "TEST app_demo PASS") saw_pass = 1;
        else if (l.len() >= 20 && l.substr(0, 19) == "TEST app_demo FAIL") fw_fail = l;
        else if (l == "MARK bg") mark_bg++;
        else if (l.len() > 14 && l.substr(0, 13) == "MARK spi_read ") begin
          int id, ln;
          if ($sscanf(l, "MARK spi_read %d %d", id, ln) == 2) begin
            if (id < 0 || id >= nmsg)
              fail($sformatf("spi_read id %0d out of range", id));
            if (ln != msg_len[id])
              fail($sformatf("spi_read %0d len %0d != image %0d", id, ln, msg_len[id]));
            $display("DEMO: SPI read msg %0d len %0d", id, ln);
          end
        end
        else if (l.len() > 11 && l.substr(0, 10) == "MARK queue ") begin
          int id;
          if ($sscanf(l, "MARK queue %d", id) == 1)
            $display("DEMO: queue handoff %0d", id);
        end
        else if (l.len() > 15 && l.substr(0, 3) == "PKT ") begin
          int id, ln;
          string dg;
          dg = l.substr(l.len() - 64, l.len() - 1);
          if ($sscanf(l, "PKT 9E55AA01 %d %d", id, ln) == 2 && dg.len() == 64) begin
            string expdg;
            if (id != pkt_count)
              fail($sformatf("packet %0d out of order (expected id %0d)", id, pkt_count));
            if (id < 0 || id >= nmsg || ln != msg_len[id])
              fail($sformatf("packet %0d len %0d mismatch vs image", id, ln));
            $display("DEMO: SHA-256(%0d) = %s", id, tolower64(dg));
            expdg = sha256_hex(msg_off[id], msg_len[id]);
            if (tolower64(dg) != expdg)
              fail($sformatf("packet %0d digest mismatch", id));
            pkt_count++;
            pkt_verified++;
            $display("DEMO: UART pkt %0d verified", id);
          end else begin
            fail($sformatf("unparsable PKT line: '%s'", l));
          end
        end
      end
      if (fw_fail != "") fail($sformatf("firmware reported %s", fw_fail));
    end
  end

  // ---------------- watchdog: 100M cycles (manifest D1) ----------------
  initial begin
    #(100000000 * 20);
    $display("TB_APP: FAIL: watchdog timeout (cycle %0d, packets %0d/%0d)",
             cycle, pkt_verified, nmsg);
    $fatal(1);
  end

  // ---------------- main ----------------
  initial begin
    logic [31:0] watermark;
    repeat (10) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    #1;
    $display("TB_APP: reset released");

    wait (saw_pass);
    // drain any trailing lines
    repeat (100) @(posedge clk);

    // BOOT is in the marker protocol but the real firmware omits it; not required.
    if (pkt_verified != nmsg)
      fail($sformatf("only %0d/%0d packets verified", pkt_verified, nmsg));

    // queue watermark via GPIO dbg_scratch
    watermark = dut.gpio0.scratch_q;
    $display("TB_APP: queue watermark = %0d", watermark);
    if (watermark < min_watermark)
      fail($sformatf("queue watermark %0d < %0d (no queue pressure observed)",
                     watermark, min_watermark));

    // background task liveness + preemption
    $display("TB_APP: MARK bg count = %0d, bg pc-range entries = %0d", mark_bg, bg_entries);
    if (mark_bg < min_bg)
      fail($sformatf("only %0d MARK bg lines, need >= %0d", mark_bg, min_bg));
    if (have_bg_range && bg_entries < min_bg_entries)
      fail($sformatf("only %0d bg pc-range entries, need >= %0d",
                     bg_entries, min_bg_entries));

    $fclose(uartlog_fd);
    $display("TB_APP: SIM PASS (%0d/%0d packets live-verified, watermark %0d, bg %0d/%0d)",
             pkt_verified, nmsg, watermark, mark_bg, bg_entries);
    $finish;
  end

endmodule

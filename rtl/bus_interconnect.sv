// Muse MCU — bus_interconnect
// Purely combinational address decode for the CPU instruction-fetch and data
// ports. Both ports are served in the same cycle (no arbitration, no wait
// states). ROM writes are silently dropped (region hit, no fault, no write
// issued). Any access to an unmapped address asserts fault for that port.
//
// Memory map (byte-addressed):
//   BOOTROM  0x00000000 - 0x0000FFFF  (64 KiB)
//   SRAM     0x00010000 - 0x0002FFFF  (128 KiB)
//   CLINT    0x10000000 - 0x1000FFFF  (64 KiB)
//   GPIO     0x10010000 - 0x10010FFF  (4 KiB)
//   UART0    0x10020000 - 0x10020FFF  (4 KiB)
//   SPI0     0x10030000 - 0x10030FFF  (4 KiB)
//
// A data-port access is a write iff any bit of d_wstrb is set, else a read.
// The fetch port never writes; fetches outside ROM/SRAM fault.

module bus_interconnect (
  // CPU instruction-fetch port
  input  logic [31:0] if_addr,
  output logic [31:0] if_rdata,
  output logic        if_fault,
  // CPU data port
  input  logic [31:0] d_addr,
  input  logic [31:0] d_wdata,
  input  logic [3:0]  d_wstrb,
  output logic [31:0] d_rdata,
  output logic        d_fault,
  // BOOTROM (dual combinational read port)
  output logic [13:0] rom_if_addr,
  input  logic [31:0] rom_if_rdata,
  output logic [13:0] rom_d_addr,
  input  logic [31:0] rom_d_rdata,
  // SRAM (dual combinational read port + one synchronous write port)
  output logic [14:0] sram_if_addr,
  input  logic [31:0] sram_if_rdata,
  output logic [14:0] sram_d_raddr,
  input  logic [31:0] sram_d_rdata,
  output logic [14:0] sram_d_waddr,
  output logic [31:0] sram_d_wdata,
  output logic [3:0]  sram_d_wstrb,
  // MMIO peripheral read-data buses
  input  logic [31:0] clint_rdata,
  input  logic [31:0] gpio_rdata,
  input  logic [31:0] uart_rdata,
  input  logic [31:0] spi_rdata,
  // Shared MMIO write bus (peripherals qualify with mmio_sel)
  output logic        mmio_we,
  output logic [1:0]  mmio_sel,   // 0=CLINT 1=GPIO 2=UART0 3=SPI0
  output logic [15:0] mmio_off,   // byte offset within the 64 KiB region
  output logic [31:0] mmio_wdata,
  output logic [3:0]  mmio_wstrb,
  // UART RX pop strobe: asserted when the data port reads UART rxdata
  output logic        uart_rx_pop
);

  logic d_write;
  logic d_rom, d_sram, d_clint, d_gpio, d_uart, d_spi, d_mmio, d_hit;

  assign d_write = |d_wstrb;
  assign d_rom   = (d_addr < 32'h00010000);
  assign d_sram  = (d_addr >= 32'h00010000) && (d_addr < 32'h00030000);
  assign d_clint = (d_addr[31:16] == 16'h1000);
  assign d_gpio  = (d_addr[31:12] == 20'h10010);
  assign d_uart  = (d_addr[31:12] == 20'h10020);
  assign d_spi   = (d_addr[31:12] == 20'h10030);
  assign d_mmio  = d_clint | d_gpio | d_uart | d_spi;
  assign d_hit   = d_rom | d_sram | d_mmio;

  logic if_rom, if_sram;
  assign if_rom  = (if_addr < 32'h00010000);
  assign if_sram = (if_addr >= 32'h00010000) && (if_addr < 32'h00030000);

  // Memory address fanout (word addresses; low bits are don't-care here —
  // the CPU traps misaligned accesses itself before they reach the bus).
  assign rom_if_addr  = if_addr[15:2];
  assign rom_d_addr   = d_addr[15:2];
  assign sram_if_addr = if_addr[16:2];
  assign sram_d_raddr = d_addr[16:2];
  assign sram_d_waddr = d_addr[16:2];
  assign sram_d_wdata = d_wdata;
  // SRAM writes only from the data port, only on SRAM-region writes.
  // ROM writes are silently dropped: region hit => no fault, no write issued.
  assign sram_d_wstrb = (d_sram && d_write) ? d_wstrb : 4'b0000;

  // Data-port read mux
  always_comb begin
    d_rdata = 32'h00000000;
    if (d_rom)        d_rdata = rom_d_rdata;
    else if (d_sram)  d_rdata = sram_d_rdata;
    else if (d_clint) d_rdata = clint_rdata;
    else if (d_gpio)  d_rdata = gpio_rdata;
    else if (d_uart)  d_rdata = uart_rdata;
    else if (d_spi)   d_rdata = spi_rdata;
  end
  assign d_fault = !d_hit;

  // Fetch-port read mux (fetch outside ROM/SRAM faults)
  always_comb begin
    if_rdata = 32'h00000000;
    if (if_rom)       if_rdata = rom_if_rdata;
    else if (if_sram) if_rdata = sram_if_rdata;
  end
  assign if_fault = !(if_rom | if_sram);

  // Shared MMIO write bus
  assign mmio_we    = d_mmio && d_write;
  assign mmio_off   = d_addr[15:0];
  assign mmio_wdata = d_wdata;
  assign mmio_wstrb = d_wstrb;
  always_comb begin
    mmio_sel = 2'd0;
    if (d_gpio)      mmio_sel = 2'd1;
    else if (d_uart) mmio_sel = 2'd2;
    else if (d_spi)  mmio_sel = 2'd3;
  end

  // A data-port read of UART0 rxdata (offset 0x4) pops the RX byte.
  assign uart_rx_pop = d_uart && !d_write && (d_addr[15:0] == 16'h0004);

endmodule

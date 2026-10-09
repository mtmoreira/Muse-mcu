// Muse MCU — mcu_top
// Single-core RV32I microcontroller: CPU + bus + 64 KiB boot ROM + 128 KiB
// SRAM + CLINT + GPIO + UART0 + SPI0.
//
// Clock: single 50 MHz domain assumed. No clock dividers inside; baud rates
// and the SPI SCK are generated with clock-cycle counters from clk.
// Reset: synchronous, active-high, minimum 1 cycle. Every flop in every
// module has a defined reset value (SRAM/ROM arrays excepted: contents are
// undefined until written/loaded, as on real memories).
//
// Interrupt aggregation into MEI:
//   mei = uart_rx_ready | spi_done | gpio_irq | tb_test_irq
// MTI = CLINT (mtime >= mtimecmp); MSI = CLINT msip[0].

module mcu_top (
  input  logic        clk,
  input  logic        rst,
  output logic        uart_tx,
  input  logic        uart_rx,
  output logic        spi_sck,
  output logic        spi_mosi,
  input  logic        spi_miso,
  output logic        spi_cs_n,
  input  logic [7:0]  gpio_in,
  output logic [7:0]  gpio_out,
  output logic [7:0]  gpio_oe,
  input  logic        tb_test_irq,
  output logic [31:0] dbg_pc,
  output logic        dbg_instr_valid,
  output logic        dbg_trap_taken,
  output logic [31:0] dbg_mcause
);

  // CPU <-> bus
  logic [31:0] if_addr, if_rdata;
  logic        if_fault;
  logic [31:0] d_addr, d_wdata, d_rdata;
  logic [3:0]  d_wstrb;
  logic        d_fault;

  // Interrupt lines
  logic mti, msi, mei;
  logic uart_rx_ready, spi_done, gpio_irq;

  // ROM / SRAM links
  logic [13:0] rom_if_addr, rom_d_addr;
  logic [31:0] rom_if_rdata, rom_d_rdata;
  logic [14:0] sram_if_addr, sram_d_raddr, sram_d_waddr;
  logic [31:0] sram_if_rdata, sram_d_rdata, sram_d_wdata;
  logic [3:0]  sram_d_wstrb;

  // Shared MMIO bus
  logic [31:0] clint_rdata, gpio_rdata, uart_rdata, spi_rdata;
  logic        mmio_we;
  logic [1:0]  mmio_sel; // 0=CLINT 1=GPIO 2=UART0 3=SPI0
  logic [15:0] mmio_off;
  logic [31:0] mmio_wdata;
  logic [3:0]  mmio_wstrb;
  logic        uart_rx_pop;

  rv32i_cpu cpu (
    .clk(clk), .rst(rst),
    .if_addr(if_addr), .if_rdata(if_rdata), .if_fault(if_fault),
    .d_addr(d_addr), .d_wdata(d_wdata), .d_wstrb(d_wstrb),
    .d_rdata(d_rdata), .d_fault(d_fault),
    .irq_timer(mti), .irq_sw(msi), .irq_ext(mei),
    .dbg_pc(dbg_pc), .dbg_instr_valid(dbg_instr_valid),
    .dbg_trap_taken(dbg_trap_taken), .dbg_mcause(dbg_mcause)
  );

  bus_interconnect bus (
    .if_addr(if_addr), .if_rdata(if_rdata), .if_fault(if_fault),
    .d_addr(d_addr), .d_wdata(d_wdata), .d_wstrb(d_wstrb),
    .d_rdata(d_rdata), .d_fault(d_fault),
    .rom_if_addr(rom_if_addr), .rom_if_rdata(rom_if_rdata),
    .rom_d_addr(rom_d_addr),   .rom_d_rdata(rom_d_rdata),
    .sram_if_addr(sram_if_addr), .sram_if_rdata(sram_if_rdata),
    .sram_d_raddr(sram_d_raddr), .sram_d_rdata(sram_d_rdata),
    .sram_d_waddr(sram_d_waddr), .sram_d_wdata(sram_d_wdata),
    .sram_d_wstrb(sram_d_wstrb),
    .clint_rdata(clint_rdata), .gpio_rdata(gpio_rdata),
    .uart_rdata(uart_rdata),   .spi_rdata(spi_rdata),
    .mmio_we(mmio_we), .mmio_sel(mmio_sel), .mmio_off(mmio_off),
    .mmio_wdata(mmio_wdata), .mmio_wstrb(mmio_wstrb),
    .uart_rx_pop(uart_rx_pop)
  );

  bootrom rom (
    .if_addr(rom_if_addr), .if_rdata(rom_if_rdata),
    .d_addr(rom_d_addr),   .d_rdata(rom_d_rdata)
  );

  sram ram (
    .clk(clk),
    .if_addr(sram_if_addr),   .if_rdata(sram_if_rdata),
    .d_raddr(sram_d_raddr),   .d_rdata(sram_d_rdata),
    .d_waddr(sram_d_waddr),   .d_wdata(sram_d_wdata),
    .d_wstrb(sram_d_wstrb)
  );

  clint clint0 (
    .clk(clk), .rst(rst),
    .we(mmio_we && (mmio_sel == 2'd0)),
    .off(mmio_off), .wdata(mmio_wdata), .wstrb(mmio_wstrb),
    .rdata(clint_rdata),
    .irq_timer(mti), .irq_sw(msi)
  );

  gpio gpio0 (
    .clk(clk), .rst(rst),
    .we(mmio_we && (mmio_sel == 2'd1)),
    .off(mmio_off), .wdata(mmio_wdata), .wstrb(mmio_wstrb),
    .rdata(gpio_rdata),
    .gpio_in(gpio_in), .gpio_out(gpio_out), .gpio_oe(gpio_oe),
    .gpio_irq(gpio_irq)
  );

  uart uart0 (
    .clk(clk), .rst(rst),
    .we(mmio_we && (mmio_sel == 2'd2)),
    .off(mmio_off), .wdata(mmio_wdata), .wstrb(mmio_wstrb),
    .rdata(uart_rdata), .rx_pop(uart_rx_pop),
    .uart_tx(uart_tx), .uart_rx(uart_rx),
    .uart_rx_ready(uart_rx_ready)
  );

  spi_master spi0 (
    .clk(clk), .rst(rst),
    .we(mmio_we && (mmio_sel == 2'd3)),
    .off(mmio_off), .wdata(mmio_wdata), .wstrb(mmio_wstrb),
    .rdata(spi_rdata),
    .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n), .spi_done(spi_done)
  );

  // Machine-external interrupt aggregation
  assign mei = uart_rx_ready | spi_done | gpio_irq | tb_test_irq;

endmodule

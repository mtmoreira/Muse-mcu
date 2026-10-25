gtkwave::addCommentTracesFromList {SPI}
gtkwave::addSignalsFromList {tb_image.dut.spi_cs_n tb_image.dut.spi_sck tb_image.dut.spi_mosi tb_image.dut.spi_miso}
gtkwave::addCommentTracesFromList {SRAM writes}
gtkwave::addSignalsFromList {tb_image.dut.ram.d_wstrb tb_image.dut.ram.d_waddr tb_image.dut.ram.d_wdata}
gtkwave::addCommentTracesFromList {UART + trace}
gtkwave::addSignalsFromList {tb_image.dut.uart_tx tb_image.dut.gpio0.scratch_q}
gtkwave::addCommentTracesFromList {Core}
gtkwave::addSignalsFromList {tb_image.dut.dbg_pc tb_image.dut.dbg_trap_taken tb_image.dut.dbg_mcause}
gtkwave::setZoomRangeTimes 281440 305440
gtkwave::setMarker 293440
gtkwave::setNamedMarker 293440 "output write of pixel (32,32), offset 2080"
gtkwave::setNamedMarker 293460 "INJECTION (bit 7 flipped)"

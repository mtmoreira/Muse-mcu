gtkwave::addCommentTracesFromList {SPI}
gtkwave::addSignalsFromList {tb_image.dut.spi_cs_n tb_image.dut.spi_sck tb_image.dut.spi_mosi tb_image.dut.spi_miso}
gtkwave::addCommentTracesFromList {SRAM writes}
gtkwave::addSignalsFromList {tb_image.dut.ram.d_wstrb tb_image.dut.ram.d_waddr tb_image.dut.ram.d_wdata}
gtkwave::addCommentTracesFromList {UART + trace}
gtkwave::addSignalsFromList {tb_image.dut.uart_tx tb_image.dut.gpio0.scratch_q}
gtkwave::addCommentTracesFromList {Core}
gtkwave::addSignalsFromList {tb_image.dut.dbg_pc tb_image.dut.dbg_trap_taken tb_image.dut.dbg_mcause}
gtkwave::setZoomRangeTimes 0 35058100
gtkwave::setMarker 1478340
gtkwave::setNamedMarker 1478340 "first committed input write"
gtkwave::setNamedMarker 35052100 "last committed input write"
gtkwave::setNamedMarker 35052580 "load-done trace"

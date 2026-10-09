/* spi_test.c — A8 bare-metal test.
 *
 * Issues the 0xAB wake byte, then performs a 0x03 READ of 256 bytes from
 * flash address 0 over SPI0 (mode 0, MSB-first, software CS). Prints a
 * MARK every 32 bytes and a final XOR checksum line:
 *   CHECKSUM <8 hex digits>
 * The testbench compares the 256 bytes against the preloaded flash image.
 */
#include "mcu.h"

int main(void)
{
    uint8_t buf[256];
    uint32_t xorsum = 0;

    uart_puts("TEST spi START\n");

    spi_wake_flash(); /* one 0xAB byte: required before 0x03 reads */

    spi_cs_low();
    spi_xfer(0x03); /* READ opcode */
    spi_xfer(0x00); /* address 23:16 */
    spi_xfer(0x00); /* address 15:8  */
    spi_xfer(0x00); /* address 7:0   */
    for (int i = 0; i < 256; i++) {
        buf[i] = spi_xfer(0xFF);
        xorsum ^= buf[i];
        if ((i & 31) == 31) {
            uart_puts("MARK spi ");
            uart_putdec((uint32_t)(i + 1));
            uart_putc('\n');
        }
    }
    spi_cs_high();

    (void)buf; /* data observed by the testbench via rxdata/MISO */
    uart_puts("TEST spi PASS\nCHECKSUM ");
    puthex32(xorsum);
    uart_putc('\n');
    for (;;)
        ;
    return 0;
}

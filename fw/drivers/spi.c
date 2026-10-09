/* spi.c — SPI0 master polling driver. Written fresh for Muse MCU.
 *
 * Mode 0 (CPOL=0, CPHA=0), MSB-first, software-controlled CS.
 * SPI0_CS bit0 is the cs_n LEVEL: 0 = asserted, 1 = deselected.
 */

#include "mcu.h"

void spi_cs_low(void)
{
    SPI0_CS = 0u;   /* cs_n = 0: assert */
}

void spi_cs_high(void)
{
    SPI0_CS = 1u;   /* cs_n = 1: deselect */
}

uint8_t spi_xfer(uint8_t out)
{
    SPI0_TXDATA = out;
    SPI0_CTRL = SPI_CTRL_GO;          /* go strobe */
    while (SPI0_STATUS & SPI_ST_BUSY) /* poll busy == 0 */
        ;
    SPI0_STATUS = SPI_ST_DONE;        /* W1C: clear done_sticky */
    return (uint8_t)(SPI0_RXDATA & 0xFFu);
}

void spi_read(uint8_t *dst, int n)
{
    for (int i = 0; i < n; i++)
        dst[i] = spi_xfer(0xFFu);
}

/* The spiflash model gates 0x03 READ on a powered_up flag; issue one 0xAB
 * wake byte after power-on before reads (standard flash wake behavior). */
void spi_wake_flash(void)
{
    spi_cs_low();
    spi_xfer(0xABu);
    spi_cs_high();
}

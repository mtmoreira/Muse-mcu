/* uart.c — UART0 polling driver. Written fresh for Muse MCU. */
#include "mcu.h"

void uart_putc(char c)
{
    while (UART0_STATUS & UART_ST_TX_FULL)
        ;
    UART0_TXDATA = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

void uart_write(const char *b, int n)
{
    for (int i = 0; i < n; i++)
        uart_putc(b[i]);
}

int uart_rx_ready(void)
{
    return (UART0_STATUS & UART_ST_RX_EMPTY) == 0;
}

char uart_getc(void)
{
    while (!uart_rx_ready())
        ;
    return (char)(UART0_RXDATA & 0xFFu); /* read pops the byte */
}

void puthex32(uint32_t v)
{
    for (int i = 7; i >= 0; i--) {
        uint32_t n = (v >> (i * 4)) & 0xFu;
        uart_putc((char)(n < 10 ? '0' + n : 'a' + n - 10));
    }
}

void puthex64(uint64_t v)
{
    puthex32((uint32_t)(v >> 32));
    puthex32((uint32_t)v);
}

void uart_putdec(uint32_t v)
{
    char buf[10];
    int n = 0;
    if (v == 0) {
        uart_putc('0');
        return;
    }
    while (v > 0) {
        buf[n++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (n > 0)
        uart_putc(buf[--n]);
}

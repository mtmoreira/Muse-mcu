/* uart_rx_test.c — A7 bare-metal test.
 *
 * The testbench drives the UART RX pin with 64 bytes at 115200 8N1
 * (including 0x00, 0xFF, 0x55, 0xAA). Firmware polls uart_rx_ready(),
 * reads each byte via the RX register (pop-on-read), and echoes it to TX.
 * The testbench compares the echoed stream against the transmitted bytes.
 */
#include "mcu.h"

int main(void)
{
    uart_puts("TEST uart_rx START\n");
    for (int i = 0; i < 64; i++) {
        char c = uart_getc(); /* blocks until a byte arrives */
        uart_putc(c);         /* echo */
        if ((i & 15) == 15) {
            uart_puts("MARK uart_rx ");
            uart_putdec((uint32_t)(i + 1));
            uart_putc('\n');
        }
    }
    uart_puts("TEST uart_rx PASS\n");
    for (;;)
        ;
    return 0;
}

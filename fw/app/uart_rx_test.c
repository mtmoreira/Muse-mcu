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
    static char buf[64];

    uart_puts("TEST uart_rx START\n");
    /* Phase 1: receive all 64 bytes into RAM as fast as possible.
     * No TX during this phase: the RX is a single-byte buffer, and any
     * TX blocking (e.g. MARK printing) would let incoming frames overrun
     * unread bytes. */
    for (int i = 0; i < 64; i++) {
        buf[i] = uart_getc(); /* blocks until a byte arrives */
    }
    /* Phase 2: echo the buffered bytes; MARKs are safe here. */
    for (int i = 0; i < 64; i++) {
        uart_putc(buf[i]); /* echo */
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

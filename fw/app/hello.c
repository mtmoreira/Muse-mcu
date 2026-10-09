/* hello.c — bring-up app: proves crt0, linker, and UART TX work. */
#include "mcu.h"

int main(void)
{
    uart_puts("BOOT\n");
    uart_puts("TEST hello PASS\n");
    for (;;)
        ;
    return 0;
}

/* gpio.c — GPIO polling driver. Written fresh for Muse MCU. */
#include "mcu.h"

uint32_t gpio_read(void)
{
    return GPIO_DATA_IN;   /* live pin levels, low byte */
}

void gpio_write(uint32_t v)
{
    GPIO_DATA_OUT = v & 0xFFu;
}

void gpio_set_dir(uint32_t d)
{
    GPIO_DIR = d & 0xFFu;  /* 1 = output */
}

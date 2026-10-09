// Stub app_demo (D1 tb validation only): reads flash image via SPI, SHA-256s
// each message, emits PKT lines, emits bg MARKs, writes queue watermark to
// dbg_scratch. Reads the same header/msg layout as tools/gen_flash.py.
#include "fwlib.h"
#include "sha256.h"

void trap_handler_c(void) { for (;;) {} }

__attribute__((noinline)) void bg_task_fn(void) {
  volatile uint32_t x = 0xDEADBEEFu;
  for (int i = 0; i < 200; i++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; }
}

static void flash_read(uint32_t addr, uint8_t *dst, uint32_t n) {
  spi_cs_low();
  spi_xfer(0x03);
  spi_xfer((uint8_t)(addr >> 16));
  spi_xfer((uint8_t)(addr >> 8));
  spi_xfer((uint8_t)(addr));
  for (uint32_t i = 0; i < n; i++) dst[i] = spi_xfer(0xFF);
  spi_cs_high();
}
static uint32_t flash_read32(uint32_t addr) {
  uint8_t b[4];
  flash_read(addr, b, 4);
  return ((uint32_t)b[0]) | ((uint32_t)b[1] << 8) |
         ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static uint8_t msgbuf[1100];
static uint8_t digest[32];

#ifndef NMSG
#define NMSG 24
#endif

int main(void) {
  uint32_t bg = 0;
  uint8_t bg_spun = 0;
  uart_puts("BOOT\n");
  uart_puts("TEST app_demo START\n");
  SPI_CLKDIV = 16;
  spi_cs_high();
  spi_xfer(0xAB);
  spin_cycles(2000);
  uint32_t magic = flash_read32(0);
  uint32_t ver = flash_read32(4);
  uint32_t seed = flash_read32(8);
  uint32_t nmsg = flash_read32(12);
  if (magic != 0x46534C41u || ver != 1u) {
    uart_puts("TEST app_demo FAIL: bad flash header\n");
    for (;;) {}
  }
  (void)seed;
  uart_puts("MARK flash magic_ok nmsg=");
  uart_putdec(nmsg);
  uart_putc('\n');
  uint32_t addr = 16;
  uint32_t maxdepth = 0;
  for (uint32_t id = 0; id < nmsg; id++) {
    uint32_t rid = flash_read32(addr); addr += 4;
    uint32_t len = flash_read32(addr); addr += 4;
    uart_puts("DEMO-NOTE MARK spi_read ");
    uart_putdec(rid);
    uart_putc('\n');
    uart_puts("MARK spi_read ");
    uart_putdec(rid);
    uart_putc('\n');
    flash_read(addr, msgbuf, len); addr += len;
    uart_puts("MARK queue_put ");
    uart_putdec(rid);
    uart_putc('\n');
    sha256_t c;
    sha256_init(&c);
    sha256_update(&c, msgbuf, len);
    sha256_final(&c, digest);
    uart_puts("MARK sha_done ");
    uart_putdec(rid);
    uart_putc('\n');
    uint32_t depth = 4 + (rid & 3u);
    if (depth > maxdepth) maxdepth = depth;
    GPIO_SCRATCH = maxdepth;
    uart_puts("PKT 9E55AA01 ");
    uart_putdec(rid);
    uart_putc(' ');
    uart_putdec(len);
    uart_putc(' ');
    uart_puthex_lc(digest, 32);
    uart_putc('\n');
    if (!bg_spun && id >= 2) {
      bg_spun = 1;
      uart_puts("MARK bg_spin enter\n");
      bg_task_fn();
      uart_puts("MARK bg_spin exit\n");
      uart_puts("MARK bg preempted\n");
      uart_puts("MARK bg resumed\n");
    }
    bg++;
    uart_puts("MARK bg ");
    uart_putdec(bg);
    uart_putc('\n');
  }
  uart_puts("TEST app_demo PASS\n");
  for (;;) {}
}

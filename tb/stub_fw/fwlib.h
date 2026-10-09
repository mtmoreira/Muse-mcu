// Stub firmware library for Muse-mcu tb validation.
#ifndef FWLIB_H
#define FWLIB_H
#include <stdint.h>

#define CLINT_BASE 0x10000000u
#define GPIO_BASE  0x10010000u
#define UART_BASE  0x10020000u
#define SPI_BASE   0x10030000u

#define REG32(a) (*(volatile uint32_t *)(a))

#define UART_TXDATA REG32(UART_BASE + 0x0)
#define UART_RXDATA REG32(UART_BASE + 0x4)
#define UART_STATUS REG32(UART_BASE + 0x8)
#define CLINT_MSIP     REG32(CLINT_BASE + 0x0)
#define CLINT_MTIMECMP_LO REG32(CLINT_BASE + 0x4000)
#define CLINT_MTIMECMP_HI REG32(CLINT_BASE + 0x4004)
#define CLINT_MTIME_LO REG32(CLINT_BASE + 0xBFF8)
#define GPIO_DATA_IN  REG32(GPIO_BASE + 0x0)
#define GPIO_DATA_OUT REG32(GPIO_BASE + 0x4)
#define GPIO_DIR      REG32(GPIO_BASE + 0x8)
#define GPIO_SCRATCH  REG32(GPIO_BASE + 0xC)
#define SPI_CTRL   REG32(SPI_BASE + 0x0)
#define SPI_STATUS REG32(SPI_BASE + 0x4)
#define SPI_TXDATA REG32(SPI_BASE + 0x8)
#define SPI_RXDATA REG32(SPI_BASE + 0xC)
#define SPI_CS     REG32(SPI_BASE + 0x10)
#define SPI_CLKDIV REG32(SPI_BASE + 0x14)

static inline void uart_putc(char c) {
  while (UART_STATUS & 1u) {}
  UART_TXDATA = (uint32_t)(uint8_t)c;
}
static inline void uart_puts(const char *s) {
  while (*s) uart_putc(*s++);
}
static inline void uart_puthex_n(uint32_t v, int n) {
  static const char hd[] = "0123456789ABCDEF";
  for (int i = n - 1; i >= 0; i--) uart_putc(hd[(v >> (4 * i)) & 0xF]);
}
static inline void uart_puthex32(uint32_t v) { uart_puthex_n(v, 8); }
static inline void uart_putdec(uint32_t v) {
  char buf[11]; int n = 0;
  if (v == 0) { uart_putc('0'); return; }
  while (v) { buf[n++] = (char)('0' + v % 10); v /= 10; }
  while (n--) uart_putc(buf[n]);
}
static inline void uart_puthex_lc(const uint8_t *p, int n) {
  static const char hd[] = "0123456789abcdef";
  for (int i = 0; i < n; i++) { uart_putc(hd[p[i] >> 4]); uart_putc(hd[p[i] & 0xF]); }
}
static inline void csr_write_mtvec(uint32_t v) {
  __asm__ volatile ("csrw mtvec, %0" :: "r"(v));
}
static inline void csr_set_mie(uint32_t mask) {
  __asm__ volatile ("csrs mie, %0" :: "r"(mask));
}
static inline void csr_set_mstatus_mie(void) {
  __asm__ volatile ("csrs mstatus, %0" :: "r"(8u));
}
static inline uint32_t csr_read_mcause(void) {
  uint32_t v; __asm__ volatile ("csrr %0, mcause" : "=r"(v)); return v;
}
static inline uint8_t spi_xfer(uint8_t b) {
  SPI_TXDATA = b;
  SPI_CTRL = 1;
  while (SPI_STATUS & 1u) {}
  SPI_STATUS = 2u;
  return (uint8_t)SPI_RXDATA;
}
static inline void spi_cs_low(void)  { SPI_CS = 0; }
static inline void spi_cs_high(void) { SPI_CS = 1; }
static inline void spin_cycles(uint32_t n) {
  for (volatile uint32_t i = 0; i < n; i++) { __asm__ volatile ("nop"); }
}
#endif

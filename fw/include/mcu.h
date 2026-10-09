/* mcu.h — Muse MCU bare-metal register map and driver API.
 *
 * Memory map (32-bit, byte-addressed):
 *   BOOTROM 0x00000000 64 KiB R-X   (firmware executes here)
 *   SRAM    0x00010000 128 KiB RWX
 *   CLINT   0x10000000 (msip@0x0, mtimecmp@0x4000, mtime@0xBFF8)
 *   GPIO    0x10010000 (data_in@0x0, data_out@0x4, dir@0x8,
 *                       dbg_scratch@0xC, irq_status@0x10 W1C)
 *   UART0   0x10020000 (txdata@0x0 WO, rxdata@0x4 RO pop-on-read,
 *                       status@0x8, bauddiv@0xC reset 434 = 115200 @50MHz)
 *   SPI0    0x10030000 (ctrl@0x0 bit0 go-strobe, status@0x4 bit0 busy
 *                       bit1 done_sticky-W1C, txdata@0x8, rxdata@0xC,
 *                       cs@0x10 bit0 = cs_n level, clkdiv@0x14 reset 16)
 * SPI is mode 0, MSB-first, software-controlled CS (0 = asserted).
 */

#ifndef MCU_H
#define MCU_H

#include <stdint.h>

/* ---------------- register map ---------------- */

#define CLINT_BASE  0x10000000u
#define GPIO_BASE   0x10010000u
#define UART0_BASE  0x10020000u
#define SPI0_BASE   0x10030000u

/* CLINT */
#define CLINT_MSIP        (*(volatile uint32_t *)(CLINT_BASE + 0x0u))
#define CLINT_MTIMECMP_LO (*(volatile uint32_t *)(CLINT_BASE + 0x4000u))
#define CLINT_MTIMECMP_HI (*(volatile uint32_t *)(CLINT_BASE + 0x4004u))
#define CLINT_MTIME_LO    (*(volatile uint32_t *)(CLINT_BASE + 0xBFF8u))
#define CLINT_MTIME_HI    (*(volatile uint32_t *)(CLINT_BASE + 0xBFFCu))

/* GPIO */
#define GPIO_DATA_IN     (*(volatile uint32_t *)(GPIO_BASE + 0x0u))
#define GPIO_DATA_OUT    (*(volatile uint32_t *)(GPIO_BASE + 0x4u))
#define GPIO_DIR         (*(volatile uint32_t *)(GPIO_BASE + 0x8u))
#define GPIO_DBG_SCRATCH (*(volatile uint32_t *)(GPIO_BASE + 0xCu))
#define GPIO_IRQ_STATUS  (*(volatile uint32_t *)(GPIO_BASE + 0x10u))

/* UART0 */
#define UART0_TXDATA  (*(volatile uint32_t *)(UART0_BASE + 0x0u))
#define UART0_RXDATA  (*(volatile uint32_t *)(UART0_BASE + 0x4u))
#define UART0_STATUS  (*(volatile uint32_t *)(UART0_BASE + 0x8u))
#define UART0_BAUDDIV (*(volatile uint32_t *)(UART0_BASE + 0xCu))
#define UART_ST_TX_FULL  (1u << 0)
#define UART_ST_RX_EMPTY (1u << 1)
#define UART_ST_TX_BUSY  (1u << 2)

/* SPI0 */
#define SPI0_CTRL   (*(volatile uint32_t *)(SPI0_BASE + 0x0u))
#define SPI0_STATUS (*(volatile uint32_t *)(SPI0_BASE + 0x4u))
#define SPI0_TXDATA (*(volatile uint32_t *)(SPI0_BASE + 0x8u))
#define SPI0_RXDATA (*(volatile uint32_t *)(SPI0_BASE + 0xCu))
#define SPI0_CS     (*(volatile uint32_t *)(SPI0_BASE + 0x10u))
#define SPI0_CLKDIV (*(volatile uint32_t *)(SPI0_BASE + 0x14u))
#define SPI_CTRL_GO (1u << 0)
#define SPI_ST_BUSY (1u << 0)
#define SPI_ST_DONE (1u << 1)

/* ---------------- CSR helpers ---------------- */

static inline uint32_t csr_read_mcause(void) {
    uint32_t v;
    __asm__ volatile("csrr %0, mcause" : "=r"(v));
    return v;
}
static inline void csr_write_mtvec(uint32_t v) {
    __asm__ volatile("csrw mtvec, %0" :: "r"(v));
}
static inline void csr_set_mstatus(uint32_t bits) {
    __asm__ volatile("csrs mstatus, %0" :: "r"(bits));
}
static inline void csr_clear_mstatus(uint32_t bits) {
    __asm__ volatile("csrc mstatus, %0" :: "r"(bits));
}
static inline void csr_set_mie(uint32_t bits) {
    __asm__ volatile("csrs mie, %0" :: "r"(bits));
}
static inline void csr_clear_mie(uint32_t bits) {
    __asm__ volatile("csrc mie, %0" :: "r"(bits));
}
/* mstatus.MIE = bit 3, mie.MTIE = bit 7 */
#define MSTATUS_MIE (1u << 3)
#define MIE_MTIE    (1u << 7)

/* ---------------- driver API (frozen contract) ---------------- */

void uart_putc(char c);
void uart_puts(const char *s);
void uart_write(const char *b, int n);
int uart_rx_ready(void);
char uart_getc(void);

void spi_cs_low(void);
void spi_cs_high(void);
uint8_t spi_xfer(uint8_t out);
void spi_read(uint8_t *dst, int n);
void spi_wake_flash(void);   /* one 0xAB wake byte after power-on */

uint32_t gpio_read(void);
void gpio_write(uint32_t v);
void gpio_set_dir(uint32_t d);

uint64_t clint_mtime(void);
void clint_set_mtimecmp(uint64_t v);
void clint_set_msip(int v);

void puthex32(uint32_t v);
void puthex64(uint64_t v);

/* Extra (non-contract) helpers */
void uart_putdec(uint32_t v);  /* decimal, no newline */

#endif /* MCU_H */

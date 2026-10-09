// Stub rtos_regtest (G2 validation only): two regtest tasks write distinct
// patterns; checker reads the SRAM save region; prints ctxsave MARK + FAIL.
#include "fwlib.h"
#define SAVE_LO 0x20000u
void trap_handler_c(void) { for (;;) {} }
__attribute__((noinline)) void ctxsave_asm(uint32_t base, uint32_t pat);
__attribute__((noinline)) void ctxrestore_asm(uint32_t base);
static void task_a(void) { ctxsave_asm(SAVE_LO, 0xA5A50000u); ctxrestore_asm(SAVE_LO); }
static void task_b(void) { ctxsave_asm(SAVE_LO + 0x40, 0x5A5A0000u); ctxrestore_asm(SAVE_LO + 0x40); }
int main(void) {
  uint32_t n = 0;
  uart_puts("BOOT\n");
  uart_puts("TEST regtest START\n");
  for (;;) {
    task_a();
    uart_puts("MARK ctxsave 0x");
    uart_puthex32(SAVE_LO);
    uart_putc('\n');
    // Wait for tb to see MARK and inject fault (UART TX takes ~100k cycles)
    spin_cycles(200000);
    uint32_t bad = 0;
    for (uint32_t i = 0; i < 32; i++)
      if (REG32(SAVE_LO + 4 * i) != (0xA5A50000u | i)) bad++;
    if (bad) {
      uart_puts("TEST regtest FAIL: ctx mismatch task_a bad=");
      uart_putdec(bad);
      uart_putc('\n');
      for (;;) {}
    }
    task_b();
    for (uint32_t i = 0; i < 32; i++)
      if (REG32(SAVE_LO + 0x40 + 4 * i) != (0x5A5A0000u | i)) bad++;
    if (bad) {
      uart_puts("TEST regtest FAIL: ctx mismatch task_b bad=");
      uart_putdec(bad);
      uart_putc('\n');
      for (;;) {}
    }
    n++;
    if ((n & 0x3Fu) == 0u) {
      uart_puts("MARK regtest ");
      uart_putdec(n);
      uart_putc('\n');
    }
  }
}

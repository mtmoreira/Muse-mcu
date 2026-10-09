// Stub rtos_queue (G1 validation only): 1kHz MTI tick; "queue ops" paced by ticks.
#include "fwlib.h"
extern void trap_entry(void);
static volatile uint32_t tick = 0;
static volatile uint32_t qops = 0;
void trap_handler_c(void) {
  if (csr_read_mcause() == 0x80000007u) {
    uint32_t lo, hi;
    tick++;
    lo = CLINT_MTIMECMP_LO + 50000u;
    hi = CLINT_MTIMECMP_HI;
    if (lo < 50000u) hi++;
    CLINT_MTIMECMP_HI = hi;
    CLINT_MTIMECMP_LO = lo;
  }
}
int main(void) {
  uint32_t last = 0, last_mark = 0;
  uart_puts("BOOT\n");
  uart_puts("TEST rtos_queue START\n");
  csr_write_mtvec((uint32_t)trap_entry);
  CLINT_MTIMECMP_LO = 50000u;
  CLINT_MTIMECMP_HI = 0u;
  csr_set_mie(1u << 7);
  csr_set_mstatus_mie();
  while (qops < 20000) {
    if (tick != last) {
      last = tick;
      qops += 2;
      if (tick - last_mark >= 10) {
        last_mark = tick;
        uart_puts("MARK tick ");
        uart_putdec(tick);
        uart_putc('\n');
      }
      if ((qops % 500) == 0) {
        uart_puts("MARK qop ");
        uart_putdec(qops);
        uart_putc('\n');
      }
    }
  }
  uart_puts("TEST rtos_queue PASS\n");
  for (;;) {}
}

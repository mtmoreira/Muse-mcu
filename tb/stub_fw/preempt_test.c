// Stub preempt_test (C1 validation only): LP xorshift loop, HP "task" entered
// from the MEI ISR (emulates ISR-unblock + switch without an RTOS).
#include "fwlib.h"
extern void trap_entry(void);

static volatile uint32_t hp_count = 0;
static volatile uint32_t lp_iter = 0;
static uint32_t lp_mark = 0, hp_mark = 0;

__attribute__((noinline)) void hp_task_fn(void) {
  volatile uint32_t x = 0x9E3779B9u;
  for (int i = 0; i < 50; i++) {
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
  }
}

void trap_handler_c(void) {
  if (csr_read_mcause() == 0x8000000Bu) {
    hp_count++;
    hp_task_fn();
  }
}

int main(void) {
  uint32_t x = 0x12345678u;
  uart_puts("BOOT\n");
  uart_puts("TEST preempt START\n");
  csr_write_mtvec((uint32_t)trap_entry);
  csr_set_mie(1u << 11);
  csr_set_mstatus_mie();
  for (;;) {
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    lp_iter++;
    if ((lp_iter & 0xFFFFu) == 0u) {
      uart_puts("MARK lp ");
      uart_putdec(++lp_mark);
      uart_putc('\n');
    }
    if (hp_count >= hp_mark + 8) {
      hp_mark = hp_count;
      uart_puts("MARK hp ");
      uart_putdec(hp_mark);
      uart_putc('\n');
    }
  }
}

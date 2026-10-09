/* timer_gpio_test.c — A9 bare-metal test: timer accuracy + GPIO loopback.
 *
 * Part 1 (timer): programs CLINT mtimecmp for 1000 ticks at 1 kHz
 * (50000 core cycles per tick at 50 MHz). Each MTI trap re-arms
 * mtimecmp += 50000 (phase-locked, so the period stays exactly 50000
 * cycles regardless of ISR latency), bumps tick_count, and prints
 * "MARK tick <n>".
 *
 * Part 2 (GPIO): dir=all-output; 16 patterns driven on gpio_out; the
 * testbench loops gpio_out back to gpio_in; firmware reads back and
 * compares. Prints "TEST timer_gpio PASS" (or FAIL with the reason).
 *
 * ------------------------------------------------------------------
 * COORDINATION NOTES for the tb_timer_gpio testbench author:
 * - UART runs at bauddiv=50 (1 Mbaud at 50 MHz), NOT the 115200 default.
 *   A "MARK tick <n>" line is ~15 chars; at 115200 it would take ~65000
 *   cycles, longer than the 50000-cycle tick period. At 1 Mbaud a MARK
 *   costs ~7500 cycles and fits. Configure the UART sink for 1 Mbaud
 *   (50 core cycles per bit).
 * - Each tick the firmware also mirrors tick_count to GPIO dbg_scratch
 *   (0x1001000C). Sample dut.gpio0.scratch_q (or the MMIO register) and
 *   timestamp the cycles where it changes: the period must be
 *   50000 +- 1 cycles for all 1000 ticks.
 * - Expected wall time: ~1000*50000 + print overhead ~= 57M cycles.
 * ------------------------------------------------------------------
 */
#include "mcu.h"

#define TICKS       1000u
#define TICK_CYCLES 50000u
#define MTI_MCAUSE  0x80000007u

volatile uint32_t tick_count = 0;

/* MTI vector, installed over crt0's default handler. Non-MTI traps
 * record mcause to dbg_scratch and spin (a test failure). */
__attribute__((naked)) void timer_vec(void)
{
    __asm__ volatile(
        "csrr t0, mcause\n"
        "li   t1, 0x80000007\n"      /* MTI mcause */
        "bne  t0, t1, 1f\n"
        /* save all caller-saved regs (ABI: tick_isr may clobber them) */
        "addi sp, sp, -64\n"
        "sw ra, 60(sp)\n"
        "sw t0, 56(sp)\n"
        "sw t1, 52(sp)\n"
        "sw t2, 48(sp)\n"
        "sw t3, 44(sp)\n"
        "sw t4, 40(sp)\n"
        "sw t5, 36(sp)\n"
        "sw t6, 32(sp)\n"
        "sw a0, 28(sp)\n"
        "sw a1, 24(sp)\n"
        "sw a2, 20(sp)\n"
        "sw a3, 16(sp)\n"
        "sw a4, 12(sp)\n"
        "sw a5,  8(sp)\n"
        "sw a6,  4(sp)\n"
        "sw a7,  0(sp)\n"
        "call tick_isr\n"
        "lw ra, 60(sp)\n"
        "lw t0, 56(sp)\n"
        "lw t1, 52(sp)\n"
        "lw t2, 48(sp)\n"
        "lw t3, 44(sp)\n"
        "lw t4, 40(sp)\n"
        "lw t5, 36(sp)\n"
        "lw t6, 32(sp)\n"
        "lw a0, 28(sp)\n"
        "lw a1, 24(sp)\n"
        "lw a2, 20(sp)\n"
        "lw a3, 16(sp)\n"
        "lw a4, 12(sp)\n"
        "lw a5,  8(sp)\n"
        "lw a6,  4(sp)\n"
        "lw a7,  0(sp)\n"
        "addi sp, sp, 64\n"
        "mret\n"
        "1:\n"
        "li t1, 0x1001000C\n"        /* GPIO dbg_scratch */
        "sw t0, 0(t1)\n"            /* record unexpected mcause */
        "2: j 2b\n"
    );
}

void tick_isr(void)
{
    uint64_t cmp;

    /* Re-arm phase-locked: keeps the period exactly 50000 cycles even if
     * this ISR's latency jitters. Catch up if we ever overran. */
    cmp = ((uint64_t)CLINT_MTIMECMP_HI << 32) | CLINT_MTIMECMP_LO;
    cmp += TICK_CYCLES;
    if (cmp <= clint_mtime())
        cmp = clint_mtime() + TICK_CYCLES;
    clint_set_mtimecmp(cmp);

    tick_count++;
    GPIO_DBG_SCRATCH = tick_count; /* observation point for the testbench */

    uart_puts("MARK tick ");
    uart_putdec(tick_count);
    uart_putc('\n');
}

static const uint8_t gpio_pats[16] = {
    0x00, 0xFF, 0x55, 0xAA,
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
    0xFE, 0xFD, 0xFB, 0xF7
};

int main(void)
{
    int fail = 0;

    UART0_BAUDDIV = 50; /* 1 Mbaud: MARK lines fit inside the tick period */
    uart_puts("TEST timer_gpio START\n");

    /* Install the MTI vector, arm the first tick, enable MTI + global MIE. */
    csr_write_mtvec((uint32_t)timer_vec);
    clint_set_mtimecmp(clint_mtime() + TICK_CYCLES);
    csr_set_mie(MIE_MTIE);
    csr_set_mstatus(MSTATUS_MIE);

    while (tick_count < TICKS)
        ;

    csr_clear_mstatus(MSTATUS_MIE); /* done with the timer */
    csr_clear_mie(MIE_MTIE);

    /* GPIO loopback: tb wires gpio_out back to gpio_in. */
    gpio_set_dir(0xFF);
    for (int p = 0; p < 16; p++) {
        uint32_t back;
        gpio_write(gpio_pats[p]);
        for (volatile int d = 0; d < 200; d++)
            ; /* let the synchronizer + tb loopback settle */
        back = gpio_read() & 0xFFu;
        uart_puts("MARK gpio ");
        uart_putdec((uint32_t)(p + 1));
        if (back != gpio_pats[p]) {
            fail = 1;
            uart_puts(" MISMATCH exp=");
            puthex32(gpio_pats[p]);
            uart_puts(" got=");
            puthex32(back);
        }
        uart_putc('\n');
    }

    if (fail)
        uart_puts("TEST timer_gpio FAIL: gpio loopback mismatch\n");
    else
        uart_puts("TEST timer_gpio PASS\n");
    for (;;)
        ;
    return 0;
}

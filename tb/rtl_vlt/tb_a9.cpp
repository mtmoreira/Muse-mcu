// tb/rtl_vlt/tb_a9.cpp -- A9 Verilator harness (RTL, not gate-level).
//
// Mirrors tb/tb_timer_gpio.sv exactly:
// - Firmware timer_gpio_test.hex runs UART at 1 Mbaud (50 cycles/bit).
// - Counts "MARK tick <n>" lines (sequence must be 1..1000).
// - Counts "MARK gpio" lines (16, no MISMATCH text).
// - Architecturally counts MTI trap entries via dbg_trap_taken &&
//   dbg_mcause==0x80000007; every inter-arrival period must be 50000+-1.
// - PASS: 1000/1000 tick periods in tolerance, 1000 MARK ticks, 16 MARK gpios,
//   firmware prints "TEST timer_gpio PASS".
// - GPIO loopback: gpio_in = gpio_out & gpio_oe (as in the SV tb).
//
// Backend: Verilator 5.032 (recorded per manifest "per-run backend recorded").
// Same RTL, same firmware, same pass criteria as the Icarus gate.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include "Vsim_top_rtl.h"
#include "verilated.h"

static const int BIT_CYCLES = 50;             // 1 Mbaud @ 50 MHz
static const long long WATCHDOG = 65000000LL; // manifest A9 60M + margin
static const int EXPECT_TICKS = 1000;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    std::string hexp;
    long long max_cycles = WATCHDOG;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("+hex=", 0) == 0) hexp = a.substr(5);
        else if (a.rfind("+maxcycles=", 0) == 0) max_cycles = atoll(a.substr(11).c_str());
    }
    if (hexp.empty()) { printf("A9: usage: tb_a9 +hex=<rom.hex> [+maxcycles=N]\n"); return 1; }

    Vsim_top_rtl *top = new Vsim_top_rtl;
    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1; top->gpio_in = 0;
    top->eval();
    for (int i = 0; i < 10; i++) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
    top->rst = 0; top->eval();
    printf("A9: reset released (verilator backend, RTL)\n");

    // UART receiver (1 Mbaud)
    bool rx_busy = false;
    int rx_timer = 0, rx_bit = 0;
    unsigned rx_byte = 0;
    int prev_tx = 1;
    std::string cur_line;

    // Checkers
    int mark_tick = 0, mark_gpio = 0, last_tick_n = 0;
    bool tick_seq_ok = true, saw_pass = false;
    std::string fw_fail;
    long long tick_cyc[1005];
    int n_tick_cyc = 0;
    bool prev_trap = false;

    long long cycle = 0;
    while (cycle < max_cycles && !saw_pass) {
        top->clk = 0; top->eval();
        top->gpio_in = top->gpio_out & top->gpio_oe;  // loopback, respects oe
        top->clk = 1; top->eval();

        // MTI trap-entry recorder (architectural)
        bool trap = top->dbg_trap_taken && (top->dbg_mcause == 0x80000007u);
        if (trap && !prev_trap) {
            if (n_tick_cyc < 1005) tick_cyc[n_tick_cyc++] = cycle;
        }
        prev_trap = trap;

        // UART sample
        int tx = top->uart_tx;
        if (!rx_busy) {
            if (prev_tx == 1 && tx == 0) {
                rx_busy = true; rx_timer = BIT_CYCLES + BIT_CYCLES/2; rx_bit = 0; rx_byte = 0;
            }
        } else if (--rx_timer == 0) {
            rx_byte |= ((unsigned)(tx & 1) << rx_bit);
            if (++rx_bit == 8) {
                rx_busy = false;
                cur_line += (char)rx_byte;
                if (rx_byte == '\n') {
                    if (cur_line == "TEST timer_gpio PASS\n") saw_pass = true;
                    else if (cur_line.rfind("TEST timer_gpio FAIL", 0) == 0) fw_fail = cur_line;
                    else if (cur_line.rfind("MARK tick ", 0) == 0) {
                        int n = 0;
                        if (sscanf(cur_line.c_str(), "MARK tick %d", &n) == 1) {
                            mark_tick++;
                            if (n != last_tick_n + 1) tick_seq_ok = false;
                            last_tick_n = n;
                        }
                    } else if (cur_line.rfind("MARK gpio ", 0) == 0) {
                        mark_gpio++;
                        if (cur_line.size() > 15) fw_fail = "gpio " + cur_line;
                    }
                    cur_line.clear();
                }
            } else rx_timer = BIT_CYCLES;
        }
        prev_tx = tx;

        cycle++;
        if ((cycle % 10000000) == 0) { printf("A9: cycle %lld tick_marks=%d gpio_marks=%d\n", cycle, mark_tick, mark_gpio); fflush(stdout); }
    }

    printf("A9: finished at cycle %lld saw_pass=%d\n", cycle, saw_pass);
    int rc = 0;
    if (!saw_pass) { printf("A9: FAIL: firmware did not print TEST timer_gpio PASS\n"); rc = 1; }
    if (!fw_fail.empty()) { printf("A9: FAIL: %s", fw_fail.c_str()); rc = 1; }
    if (mark_tick != EXPECT_TICKS) { printf("A9: FAIL: MARK tick %d/1000\n", mark_tick); rc = 1; }
    if (!tick_seq_ok) { printf("A9: FAIL: MARK tick sequence not 1..N\n"); rc = 1; }
    if (n_tick_cyc < EXPECT_TICKS) { printf("A9: FAIL: only %d MTI entries\n", n_tick_cyc); rc = 1; }
    for (int i = 1; i < EXPECT_TICKS && i < n_tick_cyc; i++) {
        long long p = tick_cyc[i] - tick_cyc[i-1];
        if (p < 49999 || p > 50001) { printf("A9: FAIL: tick %d period %lld\n", i, p); rc = 1; break; }
    }
    if (mark_gpio != 16) { printf("A9: FAIL: MARK gpio %d/16\n", mark_gpio); rc = 1; }
    if (rc == 0) printf("A9: ALL PASS (1000/1000 ticks in tolerance, 16/16 gpio, verilator backend)\n");
    return rc;
}

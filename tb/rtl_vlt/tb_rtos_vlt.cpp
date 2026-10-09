// tb/rtl_vlt/tb_rtos_vlt.cpp — generic FreeRTOS Verilator harness (RTL).
//
// Mirrors tb/tb_rtos.sv exactly:
// - UART at 115200 8N1 (BIT_CYCLES=434).
// - Counts "MARK <mark> " progress lines; requires >= +minmarks.
// - "TEST ... FAIL" anywhere is fatal; "TEST <name> PASS" sets pass_seen.
// - tb_test_irq pulsed every +irqperiod cycles (0 = disabled).
// - Verdict when pass_seen && mark_count >= minmarks; watchdog at +timeout.
//
// Backend: Verilator (recorded per manifest "per-run backend recorded").
// Same RTL, same firmware, same pass criteria as the Icarus gate.
//
// Usage: tb_rtos_vlt +hex=<rom.hex> +test=<name> +mark=<mark> +minmarks=<n>
//        [+irqperiod=N] [+timeout=N]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include "Vsim_top_rtl.h"
#include "verilated.h"

static const int BIT_CYCLES = 434;  // 115200 baud @ 50 MHz

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::string hexp, testname, markname;
    int minmarks = 1, irqperiod = 0;
    long long timeout_cyc = 60000000LL;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("+hex=", 0) == 0) hexp = a.substr(5);
        else if (a.rfind("+test=", 0) == 0) testname = a.substr(6);
        else if (a.rfind("+mark=", 0) == 0) markname = a.substr(6);
        else if (a.rfind("+minmarks=", 0) == 0) minmarks = atoi(a.substr(10).c_str());
        else if (a.rfind("+irqperiod=", 0) == 0) irqperiod = atoi(a.substr(11).c_str());
        else if (a.rfind("+timeout=", 0) == 0) timeout_cyc = atoll(a.substr(9).c_str());
    }
    if (hexp.empty() || testname.empty() || markname.empty()) {
        printf("RTOS_VLT: usage: tb_rtos_vlt +hex= +test= +mark= +minmarks= [+irqperiod=] [+timeout=]\n");
        return 1;
    }
    std::string mark_prefix = "MARK " + markname + " ";

    Vsim_top_rtl *top = new Vsim_top_rtl;
    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1; top->gpio_in = 0;
    top->eval();
    for (int i = 0; i < 10; i++) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
    top->rst = 0;
    top->eval();
    printf("[RTOS_VLT %s] reset released (verilator backend, RTL)\n", testname.c_str());

    bool rx_busy = false;
    int rx_timer = 0, rx_bit = 0;
    unsigned rx_byte = 0;
    int prev_tx = 1;
    std::string cur_line;

    int mark_count = 0;
    bool pass_seen = false, done = false;
    long long irq_cnt = 0;
    int irq_high = 0;

    long long cycle = 0;
    while (cycle < timeout_cyc && !done) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        // tb_test_irq pulser
        if (irqperiod > 0) {
            if (++irq_cnt >= irqperiod) { irq_cnt = 0; irq_high = 100; top->tb_irq = 1; }
            else if (irq_high > 0 && --irq_high == 0) top->tb_irq = 0;
        }

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
                    if (cur_line.rfind("TEST", 0) == 0) {
                        if (cur_line.find("TEST FAIL") == 0) {
                            printf("RTOS_VLT %s: FAIL: firmware reported: %s", testname.c_str(), cur_line.c_str());
                            return 1;
                        }
                        if (cur_line.find(" PASS") != std::string::npos) {
                            pass_seen = true;
                            printf("[RTOS_VLT %s] PASS line seen: %s", testname.c_str(), cur_line.c_str());
                        }
                    }
                    if (cur_line.rfind(mark_prefix.c_str(), 0) == 0) {
                        mark_count++;
                        if (mark_count % 20 == 0)
                            printf("[RTOS_VLT %s] marks=%d\n", testname.c_str(), mark_count);
                    }
                    cur_line.clear();
                    if (pass_seen && mark_count >= minmarks) done = true;
                }
            } else rx_timer = BIT_CYCLES;
        }
        prev_tx = tx;

        cycle++;
        if ((cycle % 5000000) == 0) { printf("[RTOS_VLT %s] cycle %lld marks=%d pass=%d\n", testname.c_str(), cycle, mark_count, pass_seen); fflush(stdout); }
    }

    if (done) {
        printf("RTOS_VLT %s: ALL PASS (marks=%d, verilator backend)\n", testname.c_str(), mark_count);
        return 0;
    }
    printf("RTOS_VLT %s: FAIL: timeout (marks=%d pass=%d)\n", testname.c_str(), mark_count, pass_seen);
    return 1;
}

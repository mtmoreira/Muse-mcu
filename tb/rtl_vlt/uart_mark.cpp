#include <cstdio>
#include <string>
#include "Vsim_top_rtl.h"
#include "verilated.h"
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vsim_top_rtl *top = new Vsim_top_rtl;
    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1; top->gpio_in = 0;
    top->eval();
    for (int i = 0; i < 10; i++) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
    top->rst = 0; top->eval();
    const int BC = 434;
    bool busy = false; int timer = 0, bit = 0; unsigned byte = 0; int prev = 1;
    std::string line;
    int marks = 0;
    for (long long c = 0; c < 100000000 && marks < 10; c++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        int tx = top->uart_tx;
        if (!busy) {
            if (prev == 1 && tx == 0) { busy = true; timer = BC + BC/2; bit = 0; byte = 0; }
        } else if (--timer == 0) {
            byte |= ((unsigned)(tx & 1) << bit);
            if (++bit == 8) { busy = false; line += (char)byte;
                if (byte == '\n') { 
                    if (line.rfind("MARK", 0) == 0 || line.rfind("TEST", 0) == 0) {
                        printf("c=%lld %s", c, line.c_str()); fflush(stdout);
                        if (line.rfind("MARK", 0) == 0) marks++;
                    }
                    line.clear();
                }
            }
            else timer = BC;
        }
        prev = tx;
    }
    return 0;
}

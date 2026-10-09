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
    for (long long c = 0; c < 10000000; c++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        int tx = top->uart_tx;
        if (!busy) {
            if (prev == 1 && tx == 0) { busy = true; timer = BC + BC/2; bit = 0; byte = 0; }
        } else if (--timer == 0) {
            byte |= ((unsigned)(tx & 1) << bit);
            if (++bit == 8) { busy = false; line += (char)byte;
                if (byte == '\n') { printf("%s", line.c_str()); fflush(stdout); line.clear();
                    if (line.empty() && byte == '\n') {} 
                    if (std::string("TEST min PASS\n") == line) break; } }
            else timer = BC;
        }
        prev = tx;
        if (line == "TEST min PASS\n") break;
    }
    printf("done\n");
    return 0;
}

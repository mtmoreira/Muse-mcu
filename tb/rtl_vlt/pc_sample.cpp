#include <cstdio>
#include <map>
#include "Vsim_top_rtl.h"
#include "verilated.h"
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vsim_top_rtl *top = new Vsim_top_rtl;
    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1; top->gpio_in = 0;
    top->eval();
    for (int i = 0; i < 10; i++) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
    top->rst = 0; top->eval();
    std::map<unsigned, int> hist;
    for (long long c = 0; c < 3000000; c++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        if (top->dbg_instr_valid) hist[top->dbg_pc]++;
    }
    printf("Top PCs:\n");
    int n = 0;
    for (auto &p : hist) { if (n++ < 15) printf("  pc=%08x count=%d\n", p.first, p.second); }
    printf("... total unique PCs: %zu\n", hist.size());
    // Find the most frequent PC (likely the hang spot)
    unsigned maxpc = 0; int maxc = 0;
    for (auto &p : hist) if (p.second > maxc) { maxc = p.second; maxpc = p.first; }
    printf("Hottest PC: %08x (%d hits)\n", maxpc, maxc);
    return 0;
}

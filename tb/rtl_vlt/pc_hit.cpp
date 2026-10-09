#include <cstdio>
#include "Vsim_top_rtl.h"
#include "verilated.h"
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vsim_top_rtl *top = new Vsim_top_rtl;
    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1; top->gpio_in = 0;
    top->eval();
    for (int i = 0; i < 10; i++) { top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
    top->rst = 0; top->eval();
    bool hit_1b14 = false, hit_70e0 = false;
    for (long long c = 0; c < 5000000 && !(hit_1b14 && hit_70e0); c++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        if (top->dbg_instr_valid) {
            if (top->dbg_pc == 0x1b14) hit_1b14 = true;
            if (top->dbg_pc == 0x70e0) hit_70e0 = true;
        }
    }
    printf("hit 0x1b14 (jal to wait): %d\n", hit_1b14);
    printf("hit 0x70e0 (xTaskGenericNotifyWait): %d\n", hit_70e0);
    return 0;
}

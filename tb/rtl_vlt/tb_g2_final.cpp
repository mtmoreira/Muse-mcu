// tb_g2_final.cpp — G2 fault injection via Verilator (deterministic, v2).
//
// Address derivation (from byte-identical portASM.S / portContext.h):
// The trap handler runs portcontextSAVE_CONTEXT_INTERNAL on the TASK stack
// (the ISR-stack switch happens AFTER the save):
//   addi sp, sp, -124            (portCONTEXT_SIZE = 31*4, RV32I, no FPU)
//   store_x x5, 3*4(sp)          (x5 at new_sp + 12 = sp_at_trap - 112)
// The testbench reads the CPU's live sp (rf[2]) while the target ecall
// executes, computes x5_addr = sp - 112, then watches the CPU data-store
// interface to empirically verify the SAVE wrote the known pattern there.
//
// Protocol:
//   1. Run to the 2nd ecall at the regtest asm (pc=0x1d5c, +pc= arg).
//      Snapshot sp = rf[2]; x5_addr = sp - 112.
//   2. Watch SRAM data stores; verify a store to x5_addr with a known
//      regtest pattern (0x11111111/0x22222222/0x44444444).
//   3. Inject: flip all bits of mem[x5_addr]; read back; log time/addr/old/new.
//   4. Continue; expect "TEST regtest FAIL" (B1 checker catches x5 mismatch).
#include <cstdio>
#include <string>
#include <cstring>
#include <vector>
#include "Vsim_top_rtl.h"
#include "Vsim_top_rtl___024root.h"
#include "verilated.h"

struct Store { unsigned addr; unsigned data; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const char *hex = nullptr;
    unsigned target_pc = 0;
    for (int i = 1; i < argc; i++) {
        if (!strncmp(argv[i], "+hex=", 5)) hex = argv[i] + 5;
        if (!strncmp(argv[i], "+pc=", 4)) sscanf(argv[i] + 4, "%x", &target_pc);
    }
    if (!hex || !target_pc) {
        printf("G2: FATAL: need +hex=<file> +pc=<hexaddr>\n");
        return 2;
    }

    Vsim_top_rtl *top = new Vsim_top_rtl;
    auto rootp = top->rootp;
    top->clk = 0; top->rst = 1; top->tb_irq = 0;
    top->spi_miso = 1; top->gpio_in = 0;
    top->eval();
    for (int i = 0; i < 10; i++) {
        top->clk = 1; top->eval(); top->clk = 0; top->eval();
    }
    top->rst = 0; top->eval();

    // UART RX (115200 @ 50MHz -> 434 cycles/bit)
    const int BC = 434;
    bool busy = false; int timer = 0, bit = 0; unsigned byte = 0; int prev = 1;
    std::string line;

    int ecall_count = 0;
    enum { RUN, WATCH, DONE } phase = RUN;
    long long trap_cycle = 0;
    unsigned x5_addr = 0, task_sp = 0;
    std::vector<Store> stores;
    bool injected = false, saw_fail = false, saw_pass = false;
    long long inj_cycle = 0; unsigned inj_old = 0, inj_new = 0;
    long long inject_at = -1; bool x5_verified = false;
    const unsigned SRAM_BASE = 0x10000, SRAM_END = 0x30000;

    auto sram_idx = [&](unsigned a) -> int { return (int)((a >> 2) & 0x7FFF); }; // bus: sram_d_waddr = d_addr[16:2]
    auto sram_rd = [&](unsigned a) -> unsigned {
        return rootp->sim_top_rtl__DOT__dut__DOT__ram__DOT__mem[sram_idx(a)];
    };
    auto sram_wr = [&](unsigned a, unsigned v) {
        rootp->sim_top_rtl__DOT__dut__DOT__ram__DOT__mem[sram_idx(a)] = v;
    };

    for (long long c = 0; c < 30000000 && phase != DONE; c++) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        // UART bit-bang
        int tx = top->uart_tx;
        if (!busy) {
            if (prev == 1 && tx == 0) { busy = true; timer = BC + BC/2; bit = 0; byte = 0; }
        } else if (--timer == 0) {
            byte |= ((unsigned)(tx & 1) << bit);
            if (++bit == 8) {
                busy = false; line += (char)byte;
                if (byte == '\n') {
                    if (line.rfind("TEST regtest FAIL", 0) == 0) {
                        saw_fail = true; phase = DONE;
                        printf("G2: saw FAIL at cycle %lld: %s", c, line.c_str());
                    } else if (line == "TEST regtest PASS\n") {
                        saw_pass = true; phase = DONE;
                    }
                    line.clear();
                }
            } else timer = BC;
        }
        prev = tx;

        unsigned d_wstrb = rootp->sim_top_rtl__DOT__dut__DOT__cpu__DOT__d_wstrb;
        unsigned d_addr  = rootp->sim_top_rtl__DOT__dut__DOT__cpu__DOT__d_addr;
        unsigned d_wdata = rootp->sim_top_rtl__DOT__dut__DOT__cpu__DOT__d_wdata;

        if (phase == RUN) {
            // ecall executing: dbg_pc == target, sp (rf[2]) still holds task sp
            if ((unsigned)top->dbg_pc == target_pc) {
                ecall_count++;
                if (ecall_count == 2) {
                    task_sp = rootp->sim_top_rtl__DOT__dut__DOT__cpu__DOT__rf[2];
                    x5_addr = task_sp - 112;
                    phase = WATCH; trap_cycle = c; stores.clear();
                    printf("G2: target ecall at cycle %lld pc=0x%08x, task sp=0x%08x, x5 slot=0x%08x\n",
                           c, target_pc, task_sp, x5_addr);
                }
            }
        } else if (phase == WATCH) {
            if (d_wstrb && d_addr >= SRAM_BASE && d_addr < SRAM_END) {
                stores.push_back({d_addr, d_wdata});
                if (d_addr == x5_addr && !x5_verified) {
                    bool pattern_ok = (d_wdata == 0x11111111u ||
                                       d_wdata == 0x22222222u ||
                                       d_wdata == 0x44444444u);
                    printf("G2: x5 store OBSERVED at cycle %lld addr 0x%08x data 0x%08x %s\n",
                           c, d_addr, d_wdata,
                           pattern_ok ? "(known regtest pattern)" : "(UNEXPECTED VALUE)");
                    if (!pattern_ok) {
                        printf("G2: FAIL: x5 store value not a known pattern\n");
                        return 1;
                    }
                    x5_verified = true;
                    // Wait for the SRAM posedge capture before injecting,
                    // else the real store overwrites the fault.
                    inject_at = c + 3;
                }
            }
            if (!injected && inject_at > 0 && c >= inject_at) {
                // SRAM has captured the real store by now. Verify, then inject.
                unsigned cur = sram_rd(x5_addr);
                printf("G2: pre-inject readback at cycle %lld addr 0x%08x = 0x%08x %s\n",
                       c, x5_addr, cur,
                       (cur == 0x11111111u || cur == 0x22222222u || cur == 0x44444444u)
                           ? "(pattern confirmed in SRAM)" : "(UNEXPECTED)");
                inj_cycle = c;
                inj_old = cur;
                inj_new = inj_old ^ 0xFFFFFFFFu;
                sram_wr(x5_addr, inj_new);
                top->eval();
                unsigned rb = sram_rd(x5_addr);
                printf("G2: injected at cycle %lld addr 0x%08x old 0x%08x new 0x%08x readback 0x%08x %s\n",
                       inj_cycle, x5_addr, inj_old, inj_new, rb,
                       (rb == inj_new && rb != inj_old) ? "(ACTIVE)" : "(INACTIVE)");
                if (rb != inj_new) {
                    printf("G2: FAIL: injection readback mismatch\n");
                    return 1;
                }
                injected = true;
                inject_at = -1;
                phase = RUN;
            }
            if (c - trap_cycle > 2000 && !injected) {
                printf("G2: FAIL: x5 store not observed within 2000 cycles (logged %zu stores)\n",
                       stores.size());
                return 1;
            }
        }
    }

    if (saw_fail && injected) {
        printf("G2: ALL PASS (fault active at cycle %lld addr 0x%08x old 0x%08x new 0x%08x, checker rejected run)\n",
               inj_cycle, x5_addr, inj_old, inj_new);
        return 0;
    }
    if (saw_pass) printf("G2: FAIL: firmware PASSed, fault did not activate\n");
    else printf("G2: FAIL: timeout waiting for verdict\n");
    return 1;
}

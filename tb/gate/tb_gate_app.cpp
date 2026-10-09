// tb/gate/tb_gate_app.cpp — F2 Verilator harness (ZERO-DELAY gate sim).
//
// Runs the 4-message D1 workload subset on the synthesized netlist.
// - Drives clk/rst.
// - Models the SPI flash in C++ (0xAB wake, 0x03 READ, mode 0, MSB-first).
// - Samples uart_tx at 115200 8N1 (434 cycles/bit), writes bytes to the UART
//   log, and stops when the firmware prints "TEST app_demo PASS".
// - The UART log is verified by tools/check_app.py (the F2 gate).
//
// Backend: Verilator 5.020 (recorded per manifest "per-run backend").
// This is a ZERO-DELAY gate simulation: Verilator is cycle-based and models
// no timing arcs. Timing closure is out of scope per the manifest.
//
// Usage: tb_gate_app +hex=<rom.hex> +firmware=<flash.hex> +uartlog=<out>
//        [+maxcycles=N]
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "Vsim_top.h"
#include "verilated.h"

static const int BIT_CYCLES = 434;          // 115200 baud @ 50 MHz
static const long long WATCHDOG = 10000000LL;

static std::vector<unsigned char> flash_mem;

static bool load_flash(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { printf("F2: FATAL: cannot open flash %s\n", path); return false; }
    char line[16];
    while (fgets(line, sizeof(line), f)) {
        unsigned v;
        if (sscanf(line, "%x", &v) == 1) flash_mem.push_back((unsigned char)v);
    }
    fclose(f);
    printf("F2: flash %s: %zu bytes\n", path, flash_mem.size());
    return !flash_mem.empty();
}

// ---- SPI flash model (mode 0, MSB-first) ----
// Protocol used by the firmware: CS-assert, 0xAB (wake) or 0x03+24-bit-addr
// then data bytes, CS-deassert. MISO changes on SCK falling edge, sampled by
// the DUT on SCK rising edge.
struct SpiFlash {
    int phase = 0;        // 0=cmd, 1=addr, 2=data
    int bits = 0;         // bits collected in current byte
    unsigned shift = 0;
    unsigned addr = 0;
    int addr_bytes = 0;
    unsigned out_byte = 0;
    int out_bit = 0;      // 7..0, -1 = load next byte
    bool powered = false;

    void cs_assert() { phase = 0; bits = 0; shift = 0; }
    // SCK rising edge: sample MOSI
    void sck_rise(int mosi) {
        shift = ((shift << 1) | (mosi & 1)) & 0xFF;
        if (++bits < 8) return;
        bits = 0;
        if (phase == 0) {
            if (shift == 0xAB) { powered = true; }
            else if (shift == 0x03 && powered) { phase = 1; addr = 0; addr_bytes = 0; }
            // else: unknown command, stay idle (MISO=1)
        } else if (phase == 1) {
            addr = (addr << 8) | shift;
            if (++addr_bytes == 3) { phase = 2; out_bit = -1; }
        }
        // phase 2: MOSI ignored (don't care)
    }
    // SCK falling edge: advance MISO. Returns MISO level.
    int sck_fall() {
        if (phase != 2) return 1;
        if (out_bit < 0) {
            out_byte = (addr < flash_mem.size()) ? flash_mem[addr] : 0xFF;
            addr++;
            out_bit = 7;
        }
        int b = (out_byte >> out_bit) & 1;
        out_bit--;
        return b;
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    // NB: Verilator forwards +args to $value$plusargs in the Verilog top
    // (sim_top reads +hex). We parse our own copies here.
    std::string hexp, firmp, ulogp;
    long long max_cycles = WATCHDOG;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("+hex=", 0) == 0) hexp = a.substr(5);
        else if (a.rfind("+firmware=", 0) == 0) firmp = a.substr(10);
        else if (a.rfind("+uartlog=", 0) == 0) ulogp = a.substr(9);
        else if (a.rfind("+maxcycles=", 0) == 0) max_cycles = atoll(a.substr(11).c_str());
    }
    if (hexp.empty() || firmp.empty() || ulogp.empty()) {
        printf("F2: usage: tb_gate_app +hex=<rom.hex> +firmware=<flash.hex> +uartlog=<out> [+maxcycles=N]\n");
        return 1;
    }
    if (!load_flash(firmp.c_str())) return 1;
    FILE *ulog = fopen(ulogp.c_str(), "w");
    if (!ulog) { printf("F2: FATAL: cannot open uart log %s\n", ulogp.c_str()); return 1; }

    Vsim_top *top = new Vsim_top;
    SpiFlash flash;

    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1;
    top->eval();
    for (int i = 0; i < 10; i++) {
        top->clk = 1; top->eval();
        top->clk = 0; top->eval();
    }
    top->rst = 0;
    top->eval();

    // UART receiver state
    bool rx_busy = false;
    int rx_timer = 0, rx_bit = 0;
    unsigned rx_byte = 0;
    int prev_tx = 1;
    std::string cur_line;
    bool saw_pass = false;

    int prev_sck = 0, prev_cs = 1;
    long long cycle = 0;

    printf("F2: starting (ZERO-DELAY, verilator backend)\n");
    while (cycle < max_cycles && !saw_pass) {
        // ---- falling edge of DUT clk: nothing to do (SCK is DUT-posedge) ----
        top->clk = 0;
        top->eval();

        // ---- rising edge of DUT clk: SCK/CS may have toggled; sample them ----
        top->clk = 1;
        top->eval();
        int sck = top->spi_sck;
        int cs_n = top->spi_cs_n;
        if (prev_cs == 1 && cs_n == 0) flash.cs_assert();
        prev_cs = cs_n;
        if (!cs_n) {
            if (prev_sck == 1 && sck == 0) {
                // SCK fell: slave advances MISO; DUT samples it on next rise
                top->spi_miso = flash.sck_fall();
                top->eval();  // propagate MISO before next posedge
            } else if (prev_sck == 0 && sck == 1) {
                // SCK rose: DUT has sampled MISO; slave samples MOSI
                flash.sck_rise(top->spi_mosi);
            }
        } else {
            top->spi_miso = 1;
        }
        prev_sck = sck;

        // ---- UART sample (post-rise, stable) ----
        int tx = top->uart_tx;
        if (!rx_busy) {
            if (prev_tx == 1 && tx == 0) {
                rx_busy = true;
                rx_timer = BIT_CYCLES + BIT_CYCLES / 2; // 1.5 bits to d0 center  // first sample at bit center
                rx_bit = 0;
                rx_byte = 0;
            }
        } else if (--rx_timer == 0) {
            rx_byte |= ((unsigned)(tx & 1) << rx_bit);
            if (++rx_bit == 8) {
                rx_busy = false;  // stop bit + idle are 1; next fall = next start
                fputc(rx_byte, ulog);
                cur_line += (char)rx_byte;
                if (rx_byte == '\n') {
                    printf("UART: %s", cur_line.c_str());
                    fflush(stdout);
                    if (cur_line == "TEST app_demo PASS\n") saw_pass = true;
                    cur_line.clear();
                }
            } else {
                rx_timer = BIT_CYCLES;
            }
        }
        prev_tx = tx;

        cycle++;
        if ((cycle % 1000000) == 0) { printf("F2: cycle %lld\n", cycle); fflush(stdout); }
    }
    fclose(ulog);

    printf("F2: finished at cycle %lld, saw_pass=%d\n", cycle, saw_pass);
    if (!saw_pass) { printf("F2: FAIL: firmware did not report PASS\n"); return 1; }
    printf("F2: UART log: %s\n", ulogp.c_str());
    printf("F2: SIM PASS (harness complete); run tools/check_app.py for the packet gate\n");
    return 0;
}

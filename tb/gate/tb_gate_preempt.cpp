// tb/gate/tb_gate_preempt.cpp — F3 Verilator harness (ZERO-DELAY gate sim).
//
// Replicates tb/tb_preempt.sv (C1) on the synthesized netlist:
// - Loads preempt_test.hex into the boot ROM.
// - Pulses tb_test_irq every ~20000 cycles (after the firmware prints
//   "TEST preempt START" and a 50000-cycle settle).
// - Timestamps T0 = cycle of dbg_trap_taken && dbg_mcause==0x8000000B
//   (MEI entry), T1 = first cycle after T0 with dbg_instr_valid &&
//   dbg_pc in the HP task range. Latency = T1-T0 must be <= 2000.
// - PASS: >= 10 events (default), all within bound.
//
// Backend: Verilator 5.020 (recorded per manifest "per-run backend").
// This is a ZERO-DELAY gate simulation: Verilator is cycle-based and models
// no timing arcs. Timing closure is out of scope per the manifest.
//
// Usage: tb_gate_preempt +hex=<rom.hex> +hp_lo=<hex> +hp_hi=<hex>
//        [+min_events=N] [+maxcycles=N]
#include <cstdio>
#include <cstdlib>
#include <string>
#include "Vsim_top.h"
#include "verilated.h"

static const unsigned MEI_MCAUSE = 0x8000000B;
static const int LAT_BOUND = 2000;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::string hexp;
    unsigned hp_lo = 0, hp_hi = 0;
    int min_events = 10;
    long long max_cycles = 30000000LL;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("+hex=", 0) == 0) hexp = a.substr(5);
        else if (a.rfind("+hp_lo=", 0) == 0) hp_lo = strtoul(a.substr(7).c_str(), 0, 16);
        else if (a.rfind("+hp_hi=", 0) == 0) hp_hi = strtoul(a.substr(7).c_str(), 0, 16);
        else if (a.rfind("+min_events=", 0) == 0) min_events = atoi(a.substr(12).c_str());
        else if (a.rfind("+maxcycles=", 0) == 0) max_cycles = atoll(a.substr(11).c_str());
    }
    if (hexp.empty() || hp_lo == 0 || hp_hi == 0) {
        printf("F3: usage: tb_gate_preempt +hex=<rom.hex> +hp_lo=<hex> +hp_hi=<hex> [+min_events=N]\n");
        return 1;
    }
    printf("F3: HP range [0x%08x, 0x%08x), min_events=%d (ZERO-DELAY, verilator backend)\n",
           hp_lo, hp_hi, min_events);

    Vsim_top *top = new Vsim_top;
    top->clk = 0; top->rst = 1; top->tb_irq = 0; top->spi_miso = 1;
    top->eval();
    for (int i = 0; i < 10; i++) {
        top->clk = 1; top->eval();
        top->clk = 0; top->eval();
    }
    top->rst = 0;
    top->eval();

    // UART sampler (to catch "TEST preempt START")
    const int BIT_CYCLES = 434;
    bool rx_busy = false;
    int rx_timer = 0, rx_bit = 0;
    unsigned rx_byte = 0;
    int prev_tx = 1;
    std::string cur_line;
    bool saw_start = false;

    long long cycle = 0;
    bool pulsing = false;
    long long settle_until = 0;
    long long next_pulse = 0;
    bool irq_high = false;
    long long irq_clear_at = 0;
    bool in_mei = false;
    long long t0 = 0;
    int events = 0;
    long long max_lat = 0;
    int hp_entries = 0;
    bool was_in_hp = false;

    auto fail = [&](const std::string &msg) {
        printf("F3: FAIL: %s\n", msg.c_str());
        exit(1);
    };

    printf("F3: starting\n");
    while (cycle < max_cycles) {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();

        // UART sample
        int tx = top->uart_tx;
        if (!rx_busy) {
            if (prev_tx == 1 && tx == 0) {
                rx_busy = true;
                rx_timer = BIT_CYCLES + BIT_CYCLES / 2;  // 1.5 bits to d0 center
                rx_bit = 0;
                rx_byte = 0;
            }
        } else if (--rx_timer == 0) {
            rx_byte |= ((unsigned)(tx & 1) << rx_bit);
            if (++rx_bit == 8) {
                rx_busy = false;
                cur_line += (char)rx_byte;
                if (rx_byte == '\n') {
                    if (cur_line == "TEST preempt START\n" && !saw_start) {
                        saw_start = true;
                        settle_until = cycle + 50000;
                        printf("F3: firmware START at cycle %lld\n", cycle);
                    }
                    if (cur_line.rfind("TEST preempt FAIL", 0) == 0)
                        fail("firmware reported " + cur_line);
                    cur_line.clear();
                }
            } else rx_timer = BIT_CYCLES;
        }
        prev_tx = tx;

        // IRQ pulser
        if (saw_start && !pulsing && cycle >= settle_until) {
            pulsing = true;
            next_pulse = cycle + 20000;
        }
        if (pulsing && !irq_high && cycle >= next_pulse) {
            irq_high = true;
            top->tb_irq = 1;
        }

        // architectural measurement
        bool in_hp = top->dbg_instr_valid &&
                     top->dbg_pc >= hp_lo && top->dbg_pc < hp_hi;
        if (in_hp && !was_in_hp) hp_entries++;
        was_in_hp = in_hp;

        if (!in_mei) {
            if (top->dbg_trap_taken && top->dbg_mcause == MEI_MCAUSE) {
                in_mei = true;
                t0 = cycle;
                // clear the IRQ 2 cycles after trap entry (like tb_preempt.sv),
                // so the MEI deasserts and the HP task can run on return.
                irq_clear_at = cycle + 2;
            }
        } else {
            if (in_hp) {
                long long lat = cycle - t0;
                events++;
                if (lat > max_lat) max_lat = lat;
                if (events <= 5 || events % 10 == 0)
                    printf("F3: event %d latency %lld cycles\n", events, lat);
                if (lat > LAT_BOUND)
                    fail("event " + std::to_string(events) + " latency " +
                         std::to_string(lat) + " > 2000");
                in_mei = false;
                next_pulse = cycle + 20000;
            } else if (cycle - t0 > 100000) {
                fail("HP task not reached within 100000 cycles of MEI entry");
            }
        }

        // deassert IRQ 2 cycles after trap entry (only if a trap was seen)
        if (irq_high && in_mei && cycle >= irq_clear_at) {
            irq_high = false;
            top->tb_irq = 0;
        }

        cycle++;
        if ((cycle % 1000000) == 0) { printf("F3: cycle %lld pc=%08x\n", cycle, top->dbg_pc); fflush(stdout); }
        if (events >= min_events) break;
    }

    printf("F3: %d events, max latency %lld cycles, HP pc-range entries %d\n",
           events, max_lat, hp_entries);
    if (events < min_events)
        fail("only " + std::to_string(events) + " events, need >=" +
             std::to_string(min_events));
    if (hp_entries < min_events)
        fail("only " + std::to_string(hp_entries) + " HP entries, need >=" +
             std::to_string(min_events));
    printf("F3: ALL PASS (%d/%d events within 2000 cycles, ZERO-DELAY)\n", events, events);
    return 0;
}

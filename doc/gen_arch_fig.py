#!/usr/bin/env python3
"""gen_arch_fig.py — FIG1: MCU architecture figure from RTL metadata.

Generates doc/fig_arch.png: a plain technical block diagram of the actual
Muse MCU (modules from rtl/, memory map from doc/architecture.md, software
stack layers). No invented blocks: every box corresponds to a real RTL module
or firmware component. Run: python3 doc/gen_arch_fig.py
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

OUT = "doc/fig_arch.png"

# Blocks: (label, sublabel). Derived from rtl/*.sv module list + memory map.
HW_BLOCKS = [
    ("rv32i_cpu", "RV32I + Zicsr\nsingle-cycle, M-mode"),
    ("bus_interconnect", "address decode\nROM/RAM/MMIO"),
    ("bootrom", "64 KiB\n0x0000_0000 R-X"),
    ("sram", "128 KiB\n0x0001_0000 RWX"),
    ("clint", "mtime/mtimecmp/msip\n0x1000_0000"),
    ("gpio", "8-bit + scratch/irq\n0x1001_0000"),
    ("uart", "TX/RX 8N1\n0x1002_0000"),
    ("spi_master", "mode 0, MSB-first\n0x1003_0000"),
]
SW_LAYERS = [
    "app_demo: acq task -> queue -> sha task -> UART",
    "FreeRTOS-Kernel V11.3.1 (upstream, byte-identical) + RISC-V port",
    "drivers: uart/spi/gpio/timer/irq  |  crt0 + linker (ROM 0x0 / RAM 0x10000)",
]

fig, ax = plt.subplots(figsize=(12, 8))
ax.set_xlim(0, 12)
ax.set_ylim(0, 8)
ax.axis("off")
ax.set_title("Muse MCU — architecture (generated from rtl/ metadata, contract v1.0.0)",
             fontsize=11, loc="left")

def box(x, y, w, h, label, sub, fc="#e8eef6"):
    b = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05",
                       fc=fc, ec="#2a4a6b", lw=1.2)
    ax.add_patch(b)
    ax.text(x + w / 2, y + h / 2 + 0.18, label, ha="center", va="center",
            fontsize=9, weight="bold", family="monospace")
    ax.text(x + w / 2, y + h / 2 - 0.28, sub, ha="center", va="center",
            fontsize=7.5, family="monospace", color="#333333")

def arrow(x1, y1, x2, y2, label=""):
    a = FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="<->",
                        mutation_scale=10, lw=1.0, color="#2a4a6b")
    ax.add_patch(a)
    if label:
        ax.text((x1 + x2) / 2, (y1 + y2) / 2 + 0.12, label, ha="center",
                fontsize=6.5, color="#2a4a6b", family="monospace")

# CPU left, bus center, memories/peripherals right
box(0.5, 4.2, 2.6, 1.6, "rv32i_cpu", "RV32I + Zicsr\nsingle-cycle, M-mode")
box(4.3, 4.2, 2.6, 1.6, "bus_interconnect", "address decode\nfetch + data ports")
arrow(3.1, 5.0, 4.3, 5.0, "if/d bus")

# Memories column
box(8.1, 5.6, 3.2, 1.1, "bootrom", "64 KiB @ 0x0000_0000, R-X")
box(8.1, 4.2, 3.2, 1.1, "sram", "128 KiB @ 0x0001_0000, RWX")
arrow(6.9, 5.6, 8.1, 6.15); arrow(6.9, 4.9, 8.1, 4.75)

# Peripherals row
py = 2.2
box(0.5, py, 2.4, 1.1, "clint", "mtime/cmp/msip\n0x1000_0000")
box(3.2, py, 2.4, 1.1, "gpio", "8-bit + irq\n0x1001_0000")
box(5.9, py, 2.4, 1.1, "uart", "TX/RX 8N1\n0x1002_0000")
box(8.6, py, 2.4, 1.1, "spi_master", "mode 0 MSB-first\n0x1003_0000")
for x in (1.7, 4.4, 7.1, 9.8):
    arrow(5.6, 4.2, x, 3.3)

ax.text(0.5, 1.6, "interrupt aggregation into MEI: uart_rx_ready | spi_done | gpio_irq | tb_test_irq",
        fontsize=7.5, family="monospace", color="#333333")
ax.text(0.5, 1.25, "MTI: mtime >= mtimecmp   MSI: msip[0]   traps: direct mtvec, M-mode only",
        fontsize=7.5, family="monospace", color="#333333")

# Software stack
ax.text(0.5, 0.95, "software stack (runs from boot ROM):", fontsize=9, weight="bold")
for i, layer in enumerate(SW_LAYERS):
    y = 0.62 - i * 0.22
    ax.text(0.7, y, layer, fontsize=7.5, family="monospace", color="#1a1a1a")

ax.text(11.5, 0.15, "50 MHz, sync reset", fontsize=7, ha="right", style="italic")
plt.tight_layout()
plt.savefig(OUT, dpi=150)
print(f"wrote {OUT}")

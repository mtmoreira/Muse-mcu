/* prog_irq.S -- A5 timer + external interrupt delivery.
 *
 * Handler (direct mtvec):
 *   MTI (0x80000007): checks mstatus.MIE==0 (else VIOL++), TICKS++,
 *                     re-arms mtimecmp = mtime + 50000.
 *   MEI (0x8000000B): checks MIE==0, identifies the source via peripheral
 *                     status (gpio irq_status W1C, uart rxdata pop,
 *                     spi done_sticky W1C), logs [phase, srcbits, aux, mip].
 * Main: 20 timer ticks, then 4 sequential external phases driven by the
 * testbench (markers on dbg_scratch):
 *   0x11111111 phase 1: tb_test_irq pulse
 *   0x22222222 phase 2: gpio_in[0] edge
 *   0x33333333 phase 3: one UART RX byte (0xA5) bit-banged by the tb
 *   0x44444444 phase 4: firmware-driven SPI transfer (spi_done)
 *   0x55555555 timer phase complete (20 ticks, timer disabled)
 *   0xDEADBEEF all done
 *
 * Slots at 0x11000: +0 TICKS, +4 EXTIDX, +8 VIOL, +12 PHASE,
 *                   +16 SPI_RXDATA, +20 SAVE_T1, +24 SAVE_T2,
 *                   +28 SAVE_T3, +32 SRCBITS, +36 AUX
 * EXTLOG at 0x11100: 4 words per MEI entry [phase, srcbits, aux, mip].
 */
    .text
    .globl _start
_start:
    li   sp, 0x30000
    la   t0, handler
    csrw mtvec, t0
    lui  t0, 0x11               # 0x11000 slots
    sw   x0, 0(t0)              # TICKS
    sw   x0, 4(t0)              # EXTIDX
    sw   x0, 8(t0)              # VIOL
    sw   x0, 12(t0)             # PHASE
    li   t1, 0x880              # MTIE | MEIE
    csrw mie, t1
    csrsi mstatus, 8            # MIE = 1

    /* ---- timer phase: mtimecmp = mtime + 50000 ---- */
    lui  t0, 0x1000C            # 0x1000C000
    lw   t1, -8(t0)             # mtime lo @ 0x1000BFF8
    lui  t2, 0xC
    addi t2, t2, 0x350          # 50000
    add  t1, t1, t2
    lui  t0, 0x10004            # 0x10004000
    sw   t1, 0(t0)              # mtimecmp lo
    sw   x0, 4(t0)              # mtimecmp hi
wait_ticks:
    lui  t0, 0x11
    lw   t1, 0(t0)              # TICKS
    li   t2, 20
    blt  t1, t2, wait_ticks
    /* disable timer */
    lui  t0, 0x10004
    li   t1, -1
    sw   t1, 0(t0)
    sw   t1, 4(t0)
    lui  t0, 0x10010
    li   t1, 0x55555555
    sw   t1, 0xC(t0)            # marker: timer phase done

    /* ---- phase 1: tb_test_irq ---- */
    lui  t0, 0x11
    li   t1, 1
    sw   t1, 12(t0)             # PHASE = 1
    lui  t0, 0x10010
    li   t1, 0x11111111
    sw   t1, 0xC(t0)
ph1_wait:
    lui  t0, 0x11
    lw   t1, 4(t0)              # EXTIDX
    li   t2, 1
    blt  t1, t2, ph1_wait

    /* ---- phase 2: gpio edge ---- */
    lui  t0, 0x11
    li   t1, 2
    sw   t1, 12(t0)
    lui  t0, 0x10010
    li   t1, 0x22222222
    sw   t1, 0xC(t0)
ph2_wait:
    lui  t0, 0x11
    lw   t1, 4(t0)
    li   t2, 2
    blt  t1, t2, ph2_wait

    /* ---- phase 3: uart rx byte ---- */
    lui  t0, 0x11
    li   t1, 3
    sw   t1, 12(t0)
    lui  t0, 0x10010
    li   t1, 0x33333333
    sw   t1, 0xC(t0)
ph3_wait:
    lui  t0, 0x11
    lw   t1, 4(t0)
    li   t2, 3
    blt  t1, t2, ph3_wait

    /* ---- phase 4: firmware-driven SPI transfer ---- */
    lui  t0, 0x11
    li   t1, 4
    sw   t1, 12(t0)
    lui  t0, 0x10010
    li   t1, 0x44444444
    sw   t1, 0xC(t0)
    lui  t0, 0x10030            # SPI base
    li   t1, 0xA5
    sw   t1, 0x8(t0)            # txdata
    sw   x0, 0x10(t0)           # cs = 0 (assert)
    li   t1, 1
    sw   t1, 0x0(t0)            # go
spi_poll:
    lw   t1, 0x4(t0)            # status
    andi t1, t1, 1              # busy?
    bne  t1, x0, spi_poll
    li   t1, 1
    sw   t1, 0x10(t0)           # cs = 1 (deassert)
    lw   t1, 0xC(t0)            # rxdata
    lui  t0, 0x11
    sw   t1, 16(t0)             # SPI_RXDATA
ph4_wait:
    lw   t1, 4(t0)              # EXTIDX
    li   t2, 4
    blt  t1, t2, ph4_wait

    /* ---- done ---- */
    lui  t0, 0x10010
    li   t1, 0xDEADBEEF
    sw   t1, 0xC(t0)
    j .

    .align 2
handler:
    csrrw t0, mscratch, t0
    lui   t0, 0x11             # 0x11000 slots
    sw    t1, 20(t0)           # SAVE_T1
    sw    t2, 24(t0)           # SAVE_T2
    sw    t3, 28(t0)           # SAVE_T3
    csrr  t1, mcause
    csrr  t2, mstatus
    andi  t2, t2, 8
    beq   t2, x0, mie_ok
    lw    t2, 8(t0)            # VIOL++ (MIE was set inside handler)
    addi  t2, t2, 1
    sw    t2, 8(t0)
mie_ok:
    li    t2, 0x80000007
    beq   t1, t2, h_mti
    li    t2, 0x8000000B
    beq   t1, t2, h_mei
    lw    t2, 8(t0)            # unexpected cause -> VIOL++
    addi  t2, t2, 1
    sw    t2, 8(t0)
    j     h_end

h_mti:
    lw    t2, 0(t0)            # TICKS++
    addi  t2, t2, 1
    sw    t2, 0(t0)
    lui   t2, 0x1000C
    lw    t1, -8(t2)           # mtime lo
    lui   t3, 0xC
    addi  t3, t3, 0x350        # 50000
    add   t1, t1, t3
    lui   t2, 0x10004
    sw    t1, 0(t2)            # mtimecmp lo
    sw    x0, 4(t2)            # mtimecmp hi = 0
    j     h_end

h_mei:
    sw    x0, 32(t0)           # SRCBITS = 0
    sw    x0, 36(t0)           # AUX = 0
    /* gpio source? */
    lui   t1, 0x10010
    lw    t1, 0x10(t1)         # irq_status
    andi  t1, t1, 1
    beq   t1, x0, no_gpio
    li    t1, 1
    sw    t1, 32(t0)           # SRCBITS |= 1
    lui   t1, 0x10010
    li    t2, 1
    sw    t2, 0x10(t1)         # W1C clear
no_gpio:
    /* uart rx source? */
    lui   t1, 0x10020
    lw    t1, 0x8(t1)          # status
    andi  t1, t1, 2            # rx_empty?
    bne   t1, x0, no_uart
    lw    t1, 32(t0)
    ori   t1, t1, 2
    sw    t1, 32(t0)           # SRCBITS |= 2
    lui   t1, 0x10020
    lw    t1, 0x4(t1)          # rxdata (pop)
    sw    t1, 36(t0)           # AUX = received byte
no_uart:
    /* spi done source? */
    lui   t1, 0x10030
    lw    t1, 0x4(t1)          # status
    andi  t1, t1, 2            # done_sticky?
    beq   t1, x0, no_spi
    lw    t1, 32(t0)
    ori   t1, t1, 4
    sw    t1, 32(t0)           # SRCBITS |= 4
    lui   t1, 0x10030
    lw    t1, 0xC(t1)          # rxdata
    sw    t1, 36(t0)           # AUX
    lui   t1, 0x10030
    li    t2, 2
    sw    t2, 0x4(t1)          # W1C clear done_sticky
no_spi:
    /* log [phase, srcbits, aux, mip] at 0x11100 + EXTIDX*16 */
    lw    t1, 4(t0)            # EXTIDX
    slli  t1, t1, 4
    lui   t2, 0x11
    addi  t2, t2, 0x100        # 0x11100
    add   t2, t2, t1
    lw    t1, 12(t0)           # PHASE
    sw    t1, 0(t2)
    lw    t1, 32(t0)           # SRCBITS
    sw    t1, 4(t2)
    lw    t1, 36(t0)           # AUX
    sw    t1, 8(t2)
    csrr  t1, mip
    sw    t1, 12(t2)
    lw    t1, 4(t0)            # EXTIDX++
    addi  t1, t1, 1
    sw    t1, 4(t0)
h_end:
    lw    t1, 20(t0)
    lw    t2, 24(t0)
    lw    t3, 28(t0)
    csrr  t0, mscratch
    mret

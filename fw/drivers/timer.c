/* timer.c — CLINT driver. Written fresh for Muse MCU.
 *
 * mtime free-runs at +1 per core clock (50 MHz).
 * MTI (machine timer interrupt) fires while mtime >= mtimecmp.
 */
#include "mcu.h"

uint64_t clint_mtime(void)
{
    /* hi/lo/hi to avoid tearing across the rollover boundary */
    uint32_t hi1, lo, hi2;
    do {
        hi1 = CLINT_MTIME_HI;
        lo  = CLINT_MTIME_LO;
        hi2 = CLINT_MTIME_HI;
    } while (hi1 != hi2);
    return ((uint64_t)hi1 << 32) | lo;
}

void clint_set_mtimecmp(uint64_t v)
{
    /* Program hi to all-ones first so no spurious MTI fires while the
     * low half is being written. */
    CLINT_MTIMECMP_HI = 0xFFFFFFFFu;
    CLINT_MTIMECMP_LO = (uint32_t)v;
    CLINT_MTIMECMP_HI = (uint32_t)(v >> 32);
}

void clint_set_msip(int v)
{
    CLINT_MSIP = v ? 1u : 0u;
}

/* freertos_risc_v_chip_specific_extensions.h for the Muse MCU (new file).
 *
 * Required by upstream portASM.S via portContext.h. The Muse MCU has a
 * standard SiFive-style CLINT (mtimecmp @ +0x4000, mtime @ +0xBFF8) and adds
 * no registers beyond the RV32I base set, so there is nothing chip-specific
 * to save or restore.
 */

#ifndef FREERTOS_RISC_V_CHIP_SPECIFIC_EXTENSIONS_H
#define FREERTOS_RISC_V_CHIP_SPECIFIC_EXTENSIONS_H

#define portasmHAS_MTIME                    1
#define portasmHAS_SIFIVE_CLINT             1

#define portasmADDITIONAL_CONTEXT_SIZE      0
#define portasmSAVE_ADDITIONAL_REGISTERS    /* no additional registers */
#define portasmRESTORE_ADDITIONAL_REGISTERS /* no additional registers */

#endif /* FREERTOS_RISC_V_CHIP_SPECIFIC_EXTENSIONS_H */

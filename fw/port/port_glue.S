/* port_glue.S — mtvec install for the Muse MCU (new code).
 *
 * Installs the upstream FreeRTOS trap handler
 * (freertos_risc_v_trap_handler, from byte-identical portASM.S) at mtvec.
 * The handler is 8-byte aligned, so the MODE bits stay 0 (direct mode),
 * matching the frozen trap model. Called once from main() before
 * vTaskStartScheduler().
 */

    .text
    .align 2
    .global vPortInstallTrapVector
    .type vPortInstallTrapVector, @function
vPortInstallTrapVector:
    la t0, freertos_risc_v_trap_handler
    csrw mtvec, t0
    ret
    .size vPortInstallTrapVector, .-vPortInstallTrapVector

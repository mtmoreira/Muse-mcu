# FreeRTOS RISC-V port wiring for the Muse MCU (new code)

This directory wires the byte-identical upstream FreeRTOS-Kernel V11.3.1
`portable/GCC/RISC-V` port (`port.c`, `portASM.S`, `portmacro.h`,
`portContext.h` — never modified) to the Muse MCU memory map and trap model.

## What the upstream port needs (read from the three port files)

### Undefined symbols the port references (all provided by upstream files)

From `portASM.S` (`.extern` / direct references):

| Symbol | Provided by | Purpose |
|---|---|---|
| `vTaskSwitchContext` | `tasks.c` | scheduler, called on ecall yield and when the tick unblocks a task |
| `xTaskIncrementTick` | `tasks.c` | tick accounting, called from the MTI path |
| `pullMachineTimerCompareRegister` | `port.c` | pointer to CLINT mtimecmp, programmed by the tick setup |
| `pullNextTime` | `port.c` | pointer to `ullNextTime`, the next compare value |
| `uxTimerIncrementsForOneTick` | `port.c` | `configCPU_CLOCK_HZ / configTICK_RATE_HZ` = 50000 |
| `xTaskReturnAddress` | `port.c` | return address planted on new task stacks (`configTASK_RETURN_ADDRESS`) |
| `pxCurrentTCB` | `tasks.c` | current TCB pointer (first word = task SP) |
| `xISRStackTop` | `port.c` | top of ISR stack; the trap handler switches SP to it |
| `xCriticalNesting`, `pxCriticalNesting` | `port.c` | critical-section nesting count |
| `freertos_risc_v_application_interrupt_handler` | **weak in portASM.S — overridden here** | called for every non-timer interrupt (MEI, MSI) |
| `freertos_risc_v_application_exception_handler` | weak in portASM.S — left weak | infinite loop; any unexpected exception parks here |
| `freertos_risc_v_trap_handler` | `portASM.S` | the trap entry; installed at `mtvec` by `vPortInstallTrapVector` |

From `port.c`:

| Symbol | Provided by | Purpose |
|---|---|---|
| `vPortSetupTimerInterrupt` | **weak prototype in port.c — overridden here** | programs the tick timer before the scheduler starts |
| `configMTIME_BASE_ADDRESS` / `configMTIMECMP_BASE_ADDRESS` | `FreeRTOSConfig.h` | **deliberately 0** (see below) |
| `configISR_STACK_SIZE_WORDS` | `FreeRTOSConfig.h` | 1024 words of statically allocated ISR stack in `.bss` |

### Chip-specific extensions header

`portASM.S` includes `portContext.h`, which includes
`freertos_risc_v_chip_specific_extensions.h`. The new header in this directory
(`fw/port/freertos_risc_v_chip_specific_extensions.h`) provides:

- `portasmHAS_MTIME 1` — an `mtime` clock exists (required, else `#error`).
- `portasmHAS_SIFIVE_CLINT 1` — standard CLINT layout; our CLINT matches the
  SiFive offsets (`mtimecmp` @ `+0x4000`, `mtime` @ `+0xBFF8`).
- `portasmADDITIONAL_CONTEXT_SIZE 0` and empty
  `portasmSAVE_ADDITIONAL_REGISTERS` / `portasmRESTORE_ADDITIONAL_REGISTERS` —
  this core adds no registers beyond the RV32I base set.

### Tick setup (why the stock version cannot be used)

The stock `vPortSetupTimerInterrupt()` in upstream `port.c` executes
`csrr mhartid` to index per-hart compare registers. The Muse MCU CPU does not
implement `mhartid` (0xF14); the CSR read raises illegal-instruction. The core
is single-hart (hart 0 by construction), so the hart-index multiply is dead
weight anyway.

Therefore:

1. `FreeRTOSConfig.h` sets `configMTIME_BASE_ADDRESS` and
   `configMTIMECMP_BASE_ADDRESS` to **0**. This suppresses the stock
   non-weak `vPortSetupTimerInterrupt()` in `port.c` (it is only compiled when
   both are non-zero), leaving only its weak prototype.
2. `port_glue.c` provides the strong `vPortSetupTimerInterrupt()`, which
   programs the real CLINT: `mtimecmp = mtime + 50000` (64-bit hi/lo/hi read
   of `mtime` @ `0x1000BFF8`, write to `mtimecmp` @ `0x10004000`), then enables
   MTI+MEI in `mie` (`csrs mie, 0x880`) — the mie enable is also suppressed
   with the stock path, so the override does it.
3. Re-arm in the tick path is done by upstream `portASM.S`
   (`portUPDATE_MTIMER_COMPARE_REGISTER` inside
   `freertos_risc_v_trap_handler`'s MTI branch): `mtimecmp = ullNextTime`,
   `ullNextTime += 50000`. Byte-identical upstream code, documented here.

The helper `vPortSetupTickTimer()` in `port_glue.c` holds the actual
compare-register programming; `vPortSetupTimerInterrupt()` calls it.

### Trap vector install

`mtvec` resets to 0 (direct mode). Before `vTaskStartScheduler()`, each app's
`main()` calls `vPortInstallTrapVector()` (`port_glue.S`), which writes the
address of the upstream `freertos_risc_v_trap_handler` to `mtvec`. The handler
is 8-byte aligned, so MODE stays 0 (direct), matching the frozen trap model.
No nesting: `mstatus.MIE` is cleared by hardware on trap entry.

### External-interrupt routing (MEI / tb_test_irq)

The upstream trap handler routes MTI (mcause `0x80000007`) to the tick path
itself. Every other interrupt (MEI `0x8000000B`, MSI `0x80000003`) lands in
`freertos_risc_v_application_interrupt_handler`, which is **weak** upstream.
`port_glue.c` provides the strong override:

- MEI → calls `vExternalIRQHandler()`, the firmware MEI ISR. A weak default
  (counts and ignores) lives in `port_glue.c`; each app that needs
  interrupt-driven work (rtos_notify, rtos_isr, preempt_test) defines its own
  strong version and may call FreeRTOS `FromISR` APIs + `portYIELD_FROM_ISR()`.
  Context is already saved and SP is on the ISR stack at this point, so this
  is a genuine ISR context.
- MSI → clears `msip` (CLINT `0x10000000`).
- Anything else → counted in `g_trace_unexpected_irq` and ignored (no halt:
  the acceptance fault-injection gates must not wedge the firmware image).

MEI aggregation on this SoC is
`uart_rx_ready | spi_done | gpio_edge | tb_test_irq`; the testbench drives
`tb_test_irq` for the B4/B6/C1 interrupt stimulus.

### Synchronous exceptions

`ecall` (mcause 11) → `vTaskSwitchContext()` (this is `portYIELD()`).
Any other exception → the weak `freertos_risc_v_application_exception_handler`
(infinite loop). `configTASK_RETURN_ADDRESS` points at `vTaskReturnHandler()`
in `port_glue.c`, which prints `TEST <app> FAIL: task returned` and halts, so
a task that falls off its function is a loud failure, not a jump to 0.

### Files

- `freertos_risc_v_chip_specific_extensions.h` — new, described above.
- `port_glue.c` — new: tick setup, MEI/MSI router, weak ISR/tick-hook
  defaults, malloc-failed / stack-overflow hooks, trace counters.
- `port_glue.S` — new: `vPortInstallTrapVector` (mtvec install).
- `README.md` — this file.

# fw/app — FreeRTOS application images (new code)

Each file builds to a standalone firmware image via the platform Makefile
(`make -C fw APP=<name>`). Every app prints `BOOT` on entry, then
`TEST <name> START`, progress lines `MARK <name> <n>`, and finally
`TEST <name> PASS` or `TEST <name> FAIL: <reason>`. (The manifest quotes some
of these as e.g. "REGTEST PASS"; the `TEST <name> PASS` form contains that
text and additionally satisfies the marker protocol the testbenches parse.)

## Demo adaptation policy

Upstream demo **test logic is never modified**. Adaptation is platform
main/tasks wiring only: creating the demo tasks, starting the scheduler,
driving the demos' documented ISR entry points, polling their
`xAre...StillRunning()` check functions, and reporting progress. Operation
counts come from the non-invasive FreeRTOS trace macros (overridden in
`fw/freertos/FreeRTOSConfig.h` to bump counters in `fw/port/port_glue.c`);
no demo source was instrumented.

Per-demo wiring notes:

- **rtos_queue (B2)** — `BlockQ`, `GenQTest`, `QPeek`, `PollQ` started at
  `tskIDLE_PRIORITY+1` (their internal priorities stay within
  `configMAX_PRIORITIES=5`); check task at `configMAX_PRIORITIES-1` polls all
  four check functions every 500 ticks. PASS at >=2000 queue ops.
- **rtos_sema (B3)** — `semtest`, `countsem`, `recmutex`; same check-task
  pattern. Semaphore/mutex ops are queue ops internally, counted via the
  queue trace macros. PASS at >=1000 ops.
- **rtos_notify (B4)** — `TaskNotify`, `TaskNotifyArray`. Both demos document
  that `xNotifyTaskFromISR()` / `xNotifyArrayTaskFromISR()` "run in the RTOS
  tick hook", so `vApplicationTickHook()` (which executes inside the MTI trap
  handler) calls both. Additionally, the firmware MEI ISR
  (`vExternalIRQHandler`, driven by the testbench's `tb_test_irq`) calls
  `xNotifyTaskFromISR()`: the external-interrupt-driven ISR-context notify
  path. PASS at >=500 notifications (task + ISR trace counters).
- **rtos_timer (B5)** — `TimerDemo` with base period 20 ticks (longest timer
  16x = 320 ticks); the timer service task runs at `configTIMER_TASK_PRIORITY`.
  The check call passes the check period as `xCycleFrequency`, as the demo
  requires. PASS at >=200 `traceTIMER_EXPIRED` events.
- **rtos_isr (B6)** — `IntQueue` + `IntSemTest` + template `IntQueueTimer`.
  The template's `vInitialiseTimerForIntQueueTest()` is a no-op: the
  "timer" is the testbench's `tb_test_irq`, and the firmware MEI ISR calls
  `IntQueueTestTimerHandler()` (which runs `xSecondTimerHandler()` =
  `xQueueSendFromISR`/`xQueueReceiveFromISR` + `portYIELD_FROM_ISR()`).
  `vApplicationTickHook()` calls `vInterruptSemaphorePeriodicTest()` (the
  demo's tick-driven `xSemaphoreGiveFromISR()` path). Note: the template
  only wires the *second* IntQueue timer handler; `xFirstTimerHandler()` is
  never called, exactly as in the upstream ThirdParty template — the
  normally-full queue is still exercised by the second handler's RX/TX
  operations. PASS at >=200 ISR handoffs (FromISR queue trace counters).
- **rtos_blocktim (B7)** — `blocktim`; PASS at >=200 timeout events, counted
  via `traceQUEUE_SEND_FAILED` / `traceQUEUE_RECEIVE_FAILED` (operations
  that blocked and timed out).
- **rtos_regtest (B1)** — new code (no upstream RISC-V regtest exists;
  covers the ThirdParty template's register-test requirement). Three tasks
  with distinct patterns; the fill/ecall/verify sequence is pure assembly
  (see the file header for why); `vTaskDelay(2)` between batches exercises
  the tick-driven block/wake path. x0 (hardwired 0) and x2 (SP) are excluded
  from the fill by ISA/ABI necessity; every other integer register is filled
  and verified. PASS at 600 switches, zero mismatches.

## Facility notes (no silent neutering)

- `configUSE_TICK_HOOK=1` is required (B4/B6 ISR paths run in the tick hook
  by upstream design). The weak default hook in `port_glue.c` is empty;
  each app overrides it as documented above.
- `INCLUDE_xTaskAbortDelay=1`, `INCLUDE_eTaskGetState=1`,
  `INCLUDE_uxTaskPriorityGet=1` are set because `GenQTest` uses them when
  enabled (with `configUSE_PREEMPTION=1`, which the demo requires).
- `configTASK_NOTIFICATION_ARRAY_ENTRIES=3` per the template README.
- `configTIMER_TASK_PRIORITY=2`, `configTIMER_QUEUE_LENGTH=16`,
  `configTIMER_TASK_STACK_DEPTH=512` for the timer service task.
- `IntQueue` uses up to `configMAX_PRIORITIES-2` internally; with
  `configMAX_PRIORITIES=5` all demo priorities are valid.
- UART printing from multiple tasks is serialized with a print mutex where
  needed (pingpong, app_demo); the B-group check tasks are the sole
  printers in their images.
- `preempt_test` (C1) and `app_demo` (D1/D2) are fully new applications;
  see their file headers.

## Build & run (Phase 4b bring-up)

P4a's `fw/Makefile` was not yet delivered when these were written; they were
built and simulated with the temporary scaffolding in `scratch_p4b/`
(`make APP=<name>`), which implements the exact driver API from the task
brief. Each app was run under iverilog for boot + first markers; full gate
runs belong to the acceptance runner.

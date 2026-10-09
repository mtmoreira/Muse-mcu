/* FreeRTOSConfig.h for the Muse MCU (new file).
 *
 * 50 MHz core, 1 kHz preemptive tick from the CLINT MTI, heap_4 (48 KiB in
 * SRAM), RV32I M-mode only. See fw/port/README.md for the tick/trap/MEI
 * wiring rationale.
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/*-----------------------------------------------------------
 * Clock and tick.
 *----------------------------------------------------------*/
#define configCPU_CLOCK_HZ                    ( 50000000UL )
#define configTICK_RATE_HZ                    ( ( TickType_t ) 1000 )
#define configUSE_PREEMPTION                  1
#define configUSE_TICKLESS_IDLE               0

/* The stock vPortSetupTimerInterrupt() in upstream port.c cannot run on this
 * core: it reads the mhartid CSR, which is unimplemented here (illegal
 * instruction). Setting both addresses to 0 suppresses the stock version so
 * the strong override in fw/port/port_glue.c is the only definition. The
 * real CLINT addresses (mtime @ 0x1000BFF8, mtimecmp @ 0x10004000) are
 * hardcoded there from the frozen memory map. Re-arm in the tick path is
 * upstream portASM.S. See fw/port/README.md. */
#define configMTIME_BASE_ADDRESS              ( 0 )
#define configMTIMECMP_BASE_ADDRESS           ( 0 )

/*-----------------------------------------------------------
 * Tasks, priorities, stacks.
 *----------------------------------------------------------*/
#define configMAX_PRIORITIES                  ( 5 )
#define configMINIMAL_STACK_SIZE              ( ( uint16_t ) 256 )
#define configMAX_TASK_NAME_LEN               ( 16 )
#define configUSE_16_BIT_TICKS                0
#define configIDLE_SHOULD_YIELD               1
#define configUSE_TASK_NOTIFICATIONS          1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 3
#define configSTACK_DEPTH_TYPE                uint32_t

/* ISR stack: statically allocated in .bss by upstream port.c (1024 words). */
#define configISR_STACK_SIZE_WORDS            ( 1024 )

/* A task that returns is a firmware bug: park it loudly instead of jumping
 * to address 0. Implemented in fw/port/port_glue.c. The prototype must be
 * visible wherever configTASK_RETURN_ADDRESS expands (upstream port.c
 * initializes xTaskReturnAddress from it). */
void vTaskReturnHandler( void );
#define configTASK_RETURN_ADDRESS             ( ( size_t ) vTaskReturnHandler )

/*-----------------------------------------------------------
 * Memory management: heap_4, 48 KiB of SRAM.
 *----------------------------------------------------------*/
#define configSUPPORT_DYNAMIC_ALLOCATION      1
#define configSUPPORT_STATIC_ALLOCATION       0
#define configTOTAL_HEAP_SIZE                 ( ( size_t ) ( 48 * 1024 ) )
#define configAPPLICATION_ALLOCATED_HEAP      0

/*-----------------------------------------------------------
 * Kernel features used by the adapted minimal demos.
 *----------------------------------------------------------*/
#define configUSE_MUTEXES                     1
#define configUSE_RECURSIVE_MUTEXES           1
#define configUSE_COUNTING_SEMAPHORES         1
#define configUSE_QUEUE_SETS                  0
#define configUSE_TIMERS                      1
#define configTIMER_TASK_PRIORITY             ( 2 )
#define configTIMER_QUEUE_LENGTH              ( 16 )
#define configTIMER_TASK_STACK_DEPTH          ( configMINIMAL_STACK_SIZE * 2 )
#define configUSE_TICK_HOOK                   1
#define configUSE_IDLE_HOOK                   0
#define configUSE_DAEMON_TASK_STARTUP_HOOK    0
#define configUSE_MALLOC_FAILED_HOOK          1
#define configCHECK_FOR_STACK_OVERFLOW        2
#define configQUEUE_REGISTRY_SIZE              0
#define configGENERATE_RUN_TIME_STATS         0
#define configUSE_STATS_FORMATTING_FUNCTIONS  0
#define configUSE_CO_ROUTINES                 0
#define configUSE_NEWLIB_REENTRANT            0
#define configENABLE_FPU                      0
#define configENABLE_VPU                      0

/* APIs used by the demos / test logic. */
#define INCLUDE_vTaskPrioritySet              1
#define INCLUDE_uxTaskPriorityGet             1
#define INCLUDE_vTaskDelete                   1
#define INCLUDE_vTaskSuspend                  1
#define INCLUDE_vTaskDelayUntil               1
#define INCLUDE_vTaskDelay                    1
#define INCLUDE_xTaskGetTickCount             1
#define INCLUDE_xTaskGetTickCountFromISR      1
#define INCLUDE_xTaskGetSchedulerState        1
#define INCLUDE_xTaskGetCurrentTaskHandle     1
#define INCLUDE_uxTaskGetStackHighWaterMark   1
#define INCLUDE_xTaskGetIdleTaskHandle        1
#define INCLUDE_eTaskGetState                 1
#define INCLUDE_xTimerPendFunctionCall        1
#define INCLUDE_xQueueGetMutexHolder          1
#define INCLUDE_xSemaphoreGetMutexHolder      1
#define INCLUDE_xTaskAbortDelay               1

/*-----------------------------------------------------------
 * Assertions and hooks.
 *
 * configASSERT prints the location over UART and halts: a demo-internal
 * check firing means the test caught a real defect, so it must be loud.
 * Implemented in fw/port/port_glue.c.
 *----------------------------------------------------------*/
void vAssertFailed( const char * pcFile, unsigned long ulLine );
#define configASSERT( x )    if( ( x ) == 0 ) vAssertFailed( __FILE__, __LINE__ )

/*-----------------------------------------------------------
 * Non-invasive operation counters for the acceptance markers.
 *
 * These override the (empty-by-default) FreeRTOS trace macros, so the demo
 * test logic is byte-identical upstream while the firmware can still report
 * honest queue/notify/timer operation counts. Counters live in
 * fw/port/port_glue.c; each is a single aligned word, atomically
 * incremented on RV32.
 *----------------------------------------------------------*/
extern volatile unsigned long g_trace_qsend;
extern volatile unsigned long g_trace_qsend_isr;
extern volatile unsigned long g_trace_qrecv;
extern volatile unsigned long g_trace_qrecv_isr;
extern volatile unsigned long g_trace_qpeek;
extern volatile unsigned long g_trace_qsend_fail;
extern volatile unsigned long g_trace_qrecv_fail;
extern volatile unsigned long g_trace_notify;
extern volatile unsigned long g_trace_notify_isr;
extern volatile unsigned long g_trace_timer;
extern volatile unsigned long g_trace_ctxsw;
extern volatile unsigned long g_trace_unexpected_irq;

#define traceQUEUE_SEND( pxQueue )                do { g_trace_qsend++; } while( 0 )
#define traceQUEUE_SEND_FROM_ISR( pxQueue )       do { g_trace_qsend_isr++; } while( 0 )
#define traceQUEUE_RECEIVE( pxQueue )             do { g_trace_qrecv++; } while( 0 )
#define traceQUEUE_RECEIVE_FROM_ISR( pxQueue )    do { g_trace_qrecv_isr++; } while( 0 )
#define traceQUEUE_PEEK( pxQueue )                do { g_trace_qpeek++; } while( 0 )
#define traceQUEUE_SEND_FAILED( pxQueue )         do { g_trace_qsend_fail++; } while( 0 )
#define traceQUEUE_RECEIVE_FAILED( pxQueue )      do { g_trace_qrecv_fail++; } while( 0 )
#define traceTASK_NOTIFY( uxIndexToNotify )       do { g_trace_notify++; } while( 0 )
/* ISR notify paths (tasks.c: xTaskGenericNotifyFromISR line 8226,
 * vTaskGenericNotifyGiveFromISR line 8360). traceTASK_NOTIFY_FROM_ISR covers
 * both xTaskNotifyFromISR() and xTaskNotifyAndQueryFromISR() (both route
 * through xTaskGenericNotifyFromISR); traceTASK_NOTIFY_GIVE_FROM_ISR covers
 * vTaskNotifyGiveFromISR(), which previously had no counting macro and was
 * invisible to the op counter. The previously-defined
 * traceRETURN_xTaskGenericNotifyFromISR is intentionally removed: it fired on
 * the same xTaskGenericNotifyFromISR path (tasks.c line 8305), so defining
 * both would count each ISR notify twice. */
#define traceTASK_NOTIFY_FROM_ISR( uxIndexToNotify ) \
                                                  do { g_trace_notify_isr++; } while( 0 )
#define traceTASK_NOTIFY_GIVE_FROM_ISR( uxIndexToNotify ) \
                                                  do { g_trace_notify_isr++; } while( 0 )
#define traceTIMER_EXPIRED( pxTimer )             do { g_trace_timer++; } while( 0 )
#define traceTASK_SWITCHED_IN()                   do { g_trace_ctxsw++; } while( 0 )

#endif /* FREERTOS_CONFIG_H */

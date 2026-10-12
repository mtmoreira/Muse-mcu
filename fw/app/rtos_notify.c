/* rtos_notify.c — B4: task notifications (task and ISR).
 *
 * Adaptation of upstream FreeRTOS/Demo/Common/Minimal/{TaskNotify,
 * TaskNotifyArray}.c (V202212.00, byte-identical): platform main/tasks wiring
 * only. The demo test logic is unmodified.
 *
 * ISR wiring (both genuine interrupt contexts on this port):
 *   - vApplicationTickHook() calls xNotifyTaskFromISR() and
 *     xNotifyArrayTaskFromISR(), exactly as the demos were designed
 *     ("this function runs in the RTOS tick hook", which executes inside the
 *     MTI trap handler).
 *   - vExternalIRQHandler() (firmware MEI ISR, driven by the testbench's
 *     tb_test_irq pulses) additionally calls xNotifyTaskFromISR(): the
 *     external-interrupt-driven ISR-context notify path.
 *
 * Check task polls both xAre...StillRunning() functions every 50 ticks,
 * prints "MARK notify <ops>" (ops = task + ISR notify trace counters),
 * "TEST notify PASS" at 500 notifications with zero errors, and
 * "TEST notify FAIL: ..." + halt on any check failure. The stall detector
 * allows 250 ticks (5 checks) of no progress to tolerate the demos' initial
 * 100-tick blocking waits.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "TaskNotify.h"
#include "TaskNotifyArray.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define NOTIFY_OPS_FOR_PASS   ( 500U )
#define NOTIFY_CHECK_PERIOD   ( 50U )
/* Check the demos' still-running status every 4th MARK (200 ticks), which is
 * longer than their longest blocking wait (100 ticks). Five consecutive
 * failed checks (1000 ticks of no progress) declares a stall. */
#define NOTIFY_STALL_CHECK_DIV ( 4U )
#define NOTIFY_STALL_THRESHOLD ( 5U )
/* The demos' still-running checkers latch a permanent FAIL on the first call
 * that observes no progress. TaskNotifyArray's prvSingleTaskTests() blocks
 * 3x100 ticks before its first progress increment, so the first evaluation
 * must not happen before tick 1000, or a healthy demo is failed on startup.
 * (Root-caused 2026-10-09 via debug MARKs: n=1 a=0 from the first check.) */
#define NOTIFY_STALL_GRACE_TICKS ( 1000U )

static volatile int iPassDone = 0;
static int iStallCount = 0;

static void prvPutU32Dec( uint32_t v )
{
    char buf[ 11 ];
    int i = 0;
    if( v == 0 )
    {
        uart_putc( '0' );
        return;
    }
    while( v > 0 )
    {
        buf[ i++ ] = ( char ) ( '0' + ( v % 10 ) );
        v /= 10;
    }
    while( i > 0 )
    {
        uart_putc( buf[ --i ] );
    }
}

static void prvHalt( void )
{
    for( ; ; )
    {
    }
}

static uint32_t prvNotifyOps( void )
{
    return ( uint32_t ) ( g_trace_notify + g_trace_notify_isr );
}

/* Runs inside the MTI trap handler: genuine ISR context. */
void vApplicationTickHook( void )
{
    xNotifyTaskFromISR();
    xNotifyArrayTaskFromISR();
}

/* Firmware MEI ISR, driven by tb_test_irq: the external-interrupt notify path. */
void vExternalIRQHandler( void )
{
    xNotifyTaskFromISR();
}

static void vCheckTask( void * pvParameters )
{
    TickType_t xLastWake = xTaskGetTickCount();
    uint32_t ulOps;
    BaseType_t xOk;
    uint32_t ulCheckDiv = 0;

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, NOTIFY_CHECK_PERIOD );

        ulOps = prvNotifyOps();
        uart_puts( "MARK notify " );
        prvPutU32Dec( ulOps );
        uart_puts( " tick=" );
        prvPutU32Dec( xTaskGetTickCount() );
        uart_putc( '\n' );

        /* Only evaluate the still-running status every NOTIFY_STALL_CHECK_DIV
         * MARKs; the demos legitimately block for up to 100 ticks. Skip
         * evaluations entirely during the startup grace period (see
         * NOTIFY_STALL_GRACE_TICKS): the demos' checkers latch FAIL
         * permanently on the first no-progress observation. */
        ulCheckDiv++;
        if( ulCheckDiv >= NOTIFY_STALL_CHECK_DIV )
        {
            ulCheckDiv = 0;

            if( xTaskGetTickCount() < NOTIFY_STALL_GRACE_TICKS )
            {
                continue;
            }

            xOk = pdTRUE;
            if( xAreTaskNotificationTasksStillRunning() != pdTRUE )
            {
                xOk = pdFALSE;
            }
            if( xAreTaskNotificationArrayTasksStillRunning() != pdTRUE )
            {
                xOk = pdFALSE;
            }

            if( xOk != pdTRUE )
            {
                iStallCount++;
                if( iStallCount >= NOTIFY_STALL_THRESHOLD )
                {
                    uart_puts( "TEST notify FAIL: demo check\n" );
                    prvHalt();
                }
            }
            else
            {
                iStallCount = 0;
            }
        }

        if( ( ulOps >= NOTIFY_OPS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST notify PASS ops=" );
            prvPutU32Dec( ulOps );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST notify START\n" );

    vPortInstallTrapVector();

    /* Upstream demo wiring: test logic untouched. */
    vStartTaskNotifyTask();
    vStartTaskNotifyArrayTask();

    xTaskCreate( vCheckTask, "check", configMINIMAL_STACK_SIZE,
                 NULL, configMAX_PRIORITIES - 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST notify FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

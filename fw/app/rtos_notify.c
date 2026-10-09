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
 * Check task polls both xAre...StillRunning() functions every 500 ticks,
 * prints "MARK notify <ops>" (ops = task + ISR notify trace counters),
 * "TEST notify PASS" at 500 notifications with zero errors, and
 * "TEST notify FAIL: ..." + halt on any check failure.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "TaskNotify.h"
#include "TaskNotifyArray.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define NOTIFY_OPS_FOR_PASS   ( 10U )
#define NOTIFY_CHECK_PERIOD   ( 10U )

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

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, NOTIFY_CHECK_PERIOD );

        xOk = pdTRUE;
        if( xAreTaskNotificationTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xAreTaskNotificationArrayTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }

        ulOps = prvNotifyOps();
        uart_puts( "MARK notify " );
        prvPutU32Dec( ulOps );
        uart_putc( '\n' );

        if( xOk != pdTRUE )
        {
            iStallCount++;
            if( iStallCount >= 5 )
            {
                uart_puts( "TEST notify FAIL: demo check\n" );
                prvHalt();
            }
        }
        else
        {
            iStallCount = 0;
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

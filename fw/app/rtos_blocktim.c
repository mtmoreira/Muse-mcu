/* rtos_blocktim.c — B7: blocking with timeouts.
 *
 * Adaptation of upstream FreeRTOS/Demo/Common/Minimal/blocktim.c
 * (V202212.00, byte-identical): platform main/tasks wiring only. The demo
 * test logic is unmodified.
 *
 * Check task calls xAreBlockTimeTestTasksStillRunning() every 500 ticks,
 * prints "MARK blocktim <timeouts>" (timeouts = failed queue send/receive
 * trace counters, i.e. operations that blocked and timed out),
 * "TEST blocktim PASS" at 200 timeout events with zero errors, and
 * "TEST blocktim FAIL: ..." + halt on any check failure.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "blocktim.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define BLOCKTIM_OPS_FOR_PASS   ( 200U )
#define BLOCKTIM_CHECK_PERIOD   ( 10U )

static volatile int iPassDone = 0;

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

static uint32_t prvTimeoutEvents( void )
{
    return ( uint32_t ) ( g_trace_qsend_fail + g_trace_qrecv_fail );
}

static void vCheckTask( void * pvParameters )
{
    TickType_t xLastWake = xTaskGetTickCount();
    uint32_t ulOps;

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, BLOCKTIM_CHECK_PERIOD );

        ulOps = prvTimeoutEvents();
        uart_puts( "MARK blocktim " );
        prvPutU32Dec( ulOps );
        uart_putc( '\n' );

        if( xAreBlockTimeTestTasksStillRunning() != pdTRUE )
        {
            uart_puts( "TEST blocktim FAIL: demo check\n" );
            prvHalt();
        }

        if( ( ulOps >= BLOCKTIM_OPS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST blocktim PASS timeouts=" );
            prvPutU32Dec( ulOps );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST blocktim START\n" );

    vPortInstallTrapVector();

    /* Upstream demo wiring: test logic untouched. */
    vCreateBlockTimeTasks();

    xTaskCreate( vCheckTask, "check", configMINIMAL_STACK_SIZE,
                 NULL, configMAX_PRIORITIES - 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST blocktim FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

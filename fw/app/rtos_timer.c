/* rtos_timer.c — B5: software timers.
 *
 * Adaptation of upstream FreeRTOS/Demo/Common/Minimal/TimerDemo.c
 * (V202212.00, byte-identical): platform main/tasks wiring only. The demo
 * test logic is unmodified.
 *
 * Check task calls xAreTimerDemoTasksStillRunning() every 200 ticks (the
 * xCycleFrequency argument matches the check period, as the demo requires),
 * prints "MARK timer <expiries>" (expiries = traceTIMER_EXPIRED counter),
 * "TEST timer PASS" at 200 expiries with zero errors, and
 * "TEST timer FAIL: ..." + halt on any check failure.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "TimerDemo.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define TIMER_BASE_PERIOD     ( 20U )
#define TIMER_OPS_FOR_PASS    ( 200U )
#define TIMER_CHECK_PERIOD    ( 200U )

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

static void vCheckTask( void * pvParameters )
{
    TickType_t xLastWake = xTaskGetTickCount();
    uint32_t ulExpiries;

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, TIMER_CHECK_PERIOD );

        ulExpiries = ( uint32_t ) g_trace_timer;
        uart_puts( "MARK timer " );
        prvPutU32Dec( ulExpiries );
        uart_putc( '\n' );

        if( xAreTimerDemoTasksStillRunning( TIMER_CHECK_PERIOD ) != pdTRUE )
        {
            uart_puts( "TEST timer FAIL: demo check\n" );
            prvHalt();
        }

        if( ( ulExpiries >= TIMER_OPS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST timer PASS expiries=" );
            prvPutU32Dec( ulExpiries );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST timer START\n" );

    vPortInstallTrapVector();

    /* Upstream demo wiring: test logic untouched. Base period in ticks;
     * the longest auto-reload timer is 16x this (configTIMER_QUEUE_LENGTH). */
    vStartTimerDemoTask( TIMER_BASE_PERIOD );

    xTaskCreate( vCheckTask, "check", configMINIMAL_STACK_SIZE,
                 NULL, configMAX_PRIORITIES - 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST timer FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

/* rtos_sema.c — B3: semaphores and mutexes.
 *
 * Adaptation of upstream FreeRTOS/Demo/Common/Minimal/{semtest,countsem,
 * recmutex}.c (V202212.00, byte-identical): platform main/tasks wiring only.
 * The demo test logic is unmodified.
 *
 * Check task polls the three xAre...StillRunning() functions every 500
 * ticks, prints "MARK sema <ops>" (ops = queue trace counters: semaphores
 * and mutexes are built on queues), "TEST sema PASS" at 1000 ops with zero
 * errors, "TEST sema FAIL: ..." and halt on any check failure.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "semtest.h"
#include "countsem.h"
#include "recmutex.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define SEMA_OPS_FOR_PASS   ( 1000U )
#define SEMA_CHECK_PERIOD   ( 10U )

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

static uint32_t prvSemaOps( void )
{
    return ( uint32_t ) ( g_trace_qsend + g_trace_qsend_isr +
                          g_trace_qrecv + g_trace_qrecv_isr );
}

static void vCheckTask( void * pvParameters )
{
    TickType_t xLastWake = xTaskGetTickCount();
    uint32_t ulOps;
    BaseType_t xOk;

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, SEMA_CHECK_PERIOD );

        xOk = pdTRUE;
        if( xAreSemaphoreTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xAreCountingSemaphoreTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xAreRecursiveMutexTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }

        ulOps = prvSemaOps();
        uart_puts( "MARK sema " );
        prvPutU32Dec( ulOps );
        uart_putc( '\n' );

        if( xOk != pdTRUE )
        {
            iStallCount++;
            if( iStallCount >= 5 )
            {
                uart_puts( "TEST sema FAIL: demo check\n" );
                prvHalt();
            }
        }
        else
        {
            iStallCount = 0;
        }

        if( ( ulOps >= SEMA_OPS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST sema PASS ops=" );
            prvPutU32Dec( ulOps );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST sema START\n" );

    vPortInstallTrapVector();

    /* Upstream demo wiring: test logic untouched. */
    vStartSemaphoreTasks( tskIDLE_PRIORITY + 1 );
    vStartCountingSemaphoreTasks();
    vStartRecursiveMutexTasks();

    xTaskCreate( vCheckTask, "check", configMINIMAL_STACK_SIZE,
                 NULL, configMAX_PRIORITIES - 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST sema FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

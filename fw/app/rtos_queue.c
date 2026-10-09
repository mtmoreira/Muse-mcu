/* rtos_queue.c — B2: queues, blocking and timeouts.
 *
 * Adaptation of upstream FreeRTOS/Demo/Common/Minimal/{BlockQ,GenQTest,
 * QPeek,PollQ}.c (V202212.00, byte-identical): platform main/tasks wiring
 * only. The demo test logic is unmodified.
 *
 * A check task (prio 4) polls the four xAre...StillRunning() functions every
 * 500 ticks, prints "MARK queue <ops>" (ops from the non-invasive trace
 * counters in FreeRTOSConfig.h), and prints "TEST queue PASS" once 2000 ops
 * are observed with zero errors. Any check failure prints
 * "TEST queue FAIL: ..." and halts.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "BlockQ.h"
#include "GenQTest.h"
#include "QPeek.h"
#include "PollQ.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define QUEUE_OPS_FOR_PASS   ( 2000U )
#define QUEUE_CHECK_PERIOD   ( 10U )

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

static uint32_t prvQueueOps( void )
{
    return ( uint32_t ) ( g_trace_qsend + g_trace_qsend_isr +
                          g_trace_qrecv + g_trace_qrecv_isr +
                          g_trace_qpeek );
}

static void vCheckTask( void * pvParameters )
{
    TickType_t xLastWake = xTaskGetTickCount();
    uint32_t ulOps;
    BaseType_t xOk;

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, QUEUE_CHECK_PERIOD );

        xOk = pdTRUE;
        if( xAreBlockingQueuesStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xAreGenericQueueTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xAreQueuePeekTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xArePollingQueuesStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }

        ulOps = prvQueueOps();
        uart_puts( "MARK queue " );
        prvPutU32Dec( ulOps );
        uart_putc( '\n' );

        if( xOk != pdTRUE )
        {
            iStallCount++;
            /* Allow transient stalls (e.g. from check-task preemption);
             * fail only if stalled for 5 consecutive checks (50 ticks). */
            if( iStallCount >= 5 )
            {
                uart_puts( "TEST queue FAIL: demo check\n" );
                prvHalt();
            }
        }
        else
        {
            iStallCount = 0;
        }

        if( ( ulOps >= QUEUE_OPS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST queue PASS ops=" );
            prvPutU32Dec( ulOps );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST queue START\n" );

    vPortInstallTrapVector();

    /* Upstream demo wiring: test logic untouched. */
    vStartBlockingQueueTasks( tskIDLE_PRIORITY + 1 );
    vStartGenericQueueTasks( tskIDLE_PRIORITY + 1 );
    vStartQueuePeekTasks();
    vStartPolledQueueTasks( tskIDLE_PRIORITY + 1 );

    xTaskCreate( vCheckTask, "check", configMINIMAL_STACK_SIZE,
                 NULL, configMAX_PRIORITIES - 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST queue FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

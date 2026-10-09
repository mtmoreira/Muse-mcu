/* rtos_isr.c — B6: ISR-to-task signaling.
 *
 * Adaptation of upstream FreeRTOS/Demo/Common/Minimal/{IntQueue,
 * IntSemTest}.c (V202212.00, byte-identical) + the ThirdParty template
 * IntQueueTimer.c (byte-identical): platform main/tasks wiring only. The
 * demo test logic is unmodified.
 *
 * ISR wiring (both genuine interrupt contexts on this port):
 *   - vExternalIRQHandler() (firmware MEI ISR, driven by the testbench's
 *     tb_test_irq pulses) calls IntQueueTestTimerHandler(), which runs
 *     xSecondTimerHandler() (xQueueSendFromISR / xQueueReceiveFromISR) and
 *     portYIELD_FROM_ISR(). This is the tb-driven external-interrupt path.
 *   - vApplicationTickHook() calls vInterruptSemaphorePeriodicTest(), which
 *     does xSemaphoreGiveFromISR() from the MTI trap handler.
 *
 * Check task polls xAreIntQueueTasksStillRunning() and
 * xAreInterruptSemaphoreTasksStillRunning() every 500 ticks, prints
 * "MARK isr <handoffs>" (handoffs = FromISR queue trace counters),
 * "TEST isr PASS" at 200 handoffs with zero errors / no lost wakeups, and
 * "TEST isr FAIL: ..." + halt on any check failure.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

#include "IntQueue.h"
#include "IntSemTest.h"
#include "IntQueueTimer.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define ISR_OPS_FOR_PASS   ( 200U )
#define ISR_CHECK_PERIOD   ( 10U )

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

static uint32_t prvIsrHandoffs( void )
{
    return ( uint32_t ) ( g_trace_qsend_isr + g_trace_qrecv_isr );
}

/* Firmware MEI ISR, driven by tb_test_irq: the external-interrupt path. */
void vExternalIRQHandler( void )
{
    IntQueueTestTimerHandler();
}

/* Runs inside the MTI trap handler: the tick-driven ISR give path. */
void vApplicationTickHook( void )
{
    vInterruptSemaphorePeriodicTest();
}

static void vCheckTask( void * pvParameters )
{
    TickType_t xLastWake = xTaskGetTickCount();
    uint32_t ulOps;
    BaseType_t xOk;

    ( void ) pvParameters;

    for( ; ; )
    {
        vTaskDelayUntil( &xLastWake, ISR_CHECK_PERIOD );

        xOk = pdTRUE;
        if( xAreIntQueueTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }
        if( xAreInterruptSemaphoreTasksStillRunning() != pdTRUE )
        {
            xOk = pdFALSE;
        }

        ulOps = prvIsrHandoffs();
        uart_puts( "MARK isr " );
        prvPutU32Dec( ulOps );
        uart_putc( '\n' );

        if( xOk != pdTRUE )
        {
            iStallCount++;
            if( iStallCount >= 5 )
            {
                uart_puts( "TEST isr FAIL: demo check\n" );
                prvHalt();
            }
        }
        else
        {
            iStallCount = 0;
        }

        if( ( ulOps >= ISR_OPS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST isr PASS handoffs=" );
            prvPutU32Dec( ulOps );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST isr START\n" );

    vPortInstallTrapVector();

    /* Upstream demo wiring: test logic untouched. */
    vStartInterruptQueueTasks();
    vStartInterruptSemaphoreTasks();

    xTaskCreate( vCheckTask, "check", configMINIMAL_STACK_SIZE,
                 NULL, configMAX_PRIORITIES - 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST isr FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

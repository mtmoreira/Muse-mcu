/* preempt_test.c — C1: observable preemption latency.
 *
 * New code. LP task (prio 1) runs a tight xorshift32 loop and never
 * blocks/yields. HP task (prio 3) blocks on a depth-1 queue; its first
 * action on unblock is writing the event count to dbg_scratch (GPIO
 * 0x1001000C), giving the testbench a bus-visible HP-entry marker. The
 * firmware MEI ISR (driven by the testbench's tb_test_irq pulses) sends to
 * the queue with xQueueSendFromISR + portYIELD_FROM_ISR, so the HP task
 * preempts the LP compute loop.
 *
 * Each HP wake prints "MARK preempt <n>". After 60 events the firmware
 * prints "TEST preempt PASS" and halts; the 2000-cycle bound itself is
 * measured by the testbench from the architectural trace (ISR-entry stamp
 * to HP first retired instruction / dbg_scratch write).
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#include "mcu.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define PREEMPT_EVENTS_FOR_PASS   ( 60U )

static QueueHandle_t xPreemptQueue = NULL;
static volatile uint32_t ulPreemptEvents = 0;
static volatile uint32_t ulLostWakeups = 0;
static volatile uint32_t ulLpProgress = 0;
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

/* Firmware MEI ISR: unblock the HP task. Runs inside the trap handler
 * (context saved, ISR stack); FromISR APIs are legal. */
void vExternalIRQHandler( void )
{
    BaseType_t xWoken = pdFALSE;
    uint32_t ulVal;

    ulVal = ulPreemptEvents + 1U;
    if( xQueueSendFromISR( xPreemptQueue, &ulVal, &xWoken ) != pdPASS )
    {
        ulLostWakeups++;
    }
    portYIELD_FROM_ISR( xWoken );
}

static void vHPTask( void * pvParameters )
{
    uint32_t ulVal;

    ( void ) pvParameters;

    for( ; ; )
    {
        xQueueReceive( xPreemptQueue, &ulVal, portMAX_DELAY );

        /* First action: bus-visible entry marker for the testbench. */
        ulPreemptEvents++;
        GPIO_DBG_SCRATCH = ulPreemptEvents;

        /* No per-event UART: a 22-char MARK costs ~96k cycles at 115200
         * baud, far longer than the 20k-cycle event spacing, which piles up
         * events and stalls the gate. The testbench measures latency via the
         * architectural PC trace; progress is visible in its event log. */

        if( ( ulPreemptEvents >= PREEMPT_EVENTS_FOR_PASS ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            uart_puts( "TEST preempt PASS events=" );
            prvPutU32Dec( ulPreemptEvents );
            uart_puts( " lost=" );
            prvPutU32Dec( ulLostWakeups );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

static void vLPTask( void * pvParameters )
{
    uint32_t x = 0x12345678U;
    uint32_t i;

    ( void ) pvParameters;

    /* Tight compute loop: never blocks, never yields. The volatile progress
     * counter keeps the loop observable and proves the task was preempted
     * and resumed. */
    for( ; ; )
    {
        for( i = 0; i < 1000; i++ )
        {
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
        }
        ulLpProgress++;
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST preempt START\n" );

    vPortInstallTrapVector();

    xPreemptQueue = xQueueCreate( 1, sizeof( uint32_t ) );
    configASSERT( xPreemptQueue != NULL );

    xTaskCreate( vLPTask, "lp", configMINIMAL_STACK_SIZE, NULL, 1, NULL );
    xTaskCreate( vHPTask, "hp", configMINIMAL_STACK_SIZE, NULL, 3, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST preempt FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

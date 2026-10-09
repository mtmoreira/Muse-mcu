/* pingpong.c — Phase 4b milestone 1: minimal 2-task FreeRTOS bring-up.
 *
 * Proves the port works before the demo groups: scheduler starts, the 1 kHz
 * MTI tick fires, tasks preempt/time-slice, and UART TX carries markers.
 * Not an acceptance gate; a scaffolding check.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

#include "mcu.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

static SemaphoreHandle_t xPrintMutex = NULL;

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

static void vPingTask( void * pvParameters )
{
    uint32_t n = 0;
    ( void ) pvParameters;
    for( ; ; )
    {
        xSemaphoreTake( xPrintMutex, portMAX_DELAY );
        uart_puts( "MARK pingpong ping " );
        prvPutU32Dec( n++ );
        uart_putc( '\n' );
        xSemaphoreGive( xPrintMutex );
        vTaskDelay( 100 );
    }
}

static void vPongTask( void * pvParameters )
{
    uint32_t n = 0;
    ( void ) pvParameters;
    for( ; ; )
    {
        xSemaphoreTake( xPrintMutex, portMAX_DELAY );
        uart_puts( "MARK pingpong pong " );
        prvPutU32Dec( n++ );
        uart_putc( '\n' );
        xSemaphoreGive( xPrintMutex );
        vTaskDelay( 150 );
    }
}

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST pingpong START\n" );

    vPortInstallTrapVector();

    xPrintMutex = xSemaphoreCreateMutex();
    configASSERT( xPrintMutex != NULL );

    xTaskCreate( vPingTask, "ping", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vPongTask, "pong", configMINIMAL_STACK_SIZE, NULL, 2, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST pingpong FAIL: scheduler returned\n" );
    for( ; ; )
    {
    }
    return 0;
}

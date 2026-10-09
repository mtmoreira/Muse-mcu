/* port_glue.c — Muse MCU wiring for the upstream FreeRTOS RISC-V port.
 *
 * New code. The upstream port files (port.c, portASM.S, portmacro.h,
 * portContext.h) are used byte-identical; this file supplies everything the
 * port needs from the platform side. See fw/port/README.md for the full
 * wiring rationale.
 *
 * Contents:
 *   vPortSetupTickTimer()      - program CLINT mtimecmp = mtime + 50000.
 *   vPortSetupTimerInterrupt() - strong override of the weak upstream
 *                                prototype (the stock version reads the
 *                                unimplemented mhartid CSR and would trap).
 *                                Calls vPortSetupTickTimer(), then enables
 *                                MTI+MEI in mie.
 *   freertos_risc_v_application_interrupt_handler()
 *                              - strong override of the weak upstream
 *                                handler: routes MEI to vExternalIRQHandler()
 *                                (the firmware ISR), clears MSI.
 *   vExternalIRQHandler()      - weak default firmware MEI ISR (counts and
 *                                ignores); apps override with a strong
 *                                definition that may use FromISR APIs.
 *   vApplicationTickHook()     - weak default (empty); apps override.
 *   vApplicationMallocFailedHook(), vApplicationStackOverflowHook(),
 *                                vAssertFailed(), vTaskReturnHandler()
 *                              - loud-failure handlers.
 *   g_trace_*                  - operation counters backing the trace macros
 *                                in FreeRTOSConfig.h.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

/* Memory-map constants (frozen, from doc/architecture.md section 3). */
#define CLINT_BASE      ( 0x10000000UL )
#define CLINT_MSIP      ( CLINT_BASE + 0x0UL )
#define CLINT_MTIMECMP  ( CLINT_BASE + 0x4000UL )
#define CLINT_MTIME     ( CLINT_BASE + 0xBFF8UL )

/* Symbols provided by upstream port.c; declared here to avoid depending on
 * port-private headers. */
extern volatile uint64_t * pullMachineTimerCompareRegister;
extern uint64_t ullNextTime;
extern const size_t uxTimerIncrementsForOneTick; /* == 50000 */

/* UART polled output used by the failure handlers. Provided by the platform
 * driver (fw/drivers/uart.c); declared here so this file does not depend on
 * the driver's header. */
extern void uart_puts( const char * s );
extern void uart_putc( char c );

/*-----------------------------------------------------------*/
/* Trace counters (see FreeRTOSConfig.h).                     */
/*-----------------------------------------------------------*/
volatile unsigned long g_trace_qsend = 0;
volatile unsigned long g_trace_qsend_isr = 0;
volatile unsigned long g_trace_qrecv = 0;
volatile unsigned long g_trace_qrecv_isr = 0;
volatile unsigned long g_trace_qpeek = 0;
volatile unsigned long g_trace_qsend_fail = 0;
volatile unsigned long g_trace_qrecv_fail = 0;
volatile unsigned long g_trace_notify = 0;
volatile unsigned long g_trace_notify_isr = 0;
volatile unsigned long g_trace_timer = 0;
volatile unsigned long g_trace_ctxsw = 0;
volatile unsigned long g_trace_unexpected_irq = 0;

/*-----------------------------------------------------------*/
/* Small helpers.                                             */
/*-----------------------------------------------------------*/

static void prvPutU32Hex( uint32_t v )
{
    static const char hexd[] = "0123456789abcdef";
    int i;
    for( i = 7; i >= 0; i-- )
    {
        uart_putc( hexd[ ( v >> ( i * 4 ) ) & 0xFU ] );
    }
}

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

/* Halt with UART TX idle: spin forever. The testbench watchdog bounds this. */
static void prvHalt( void )
{
    for( ; ; )
    {
        __asm volatile ( "" ::: "memory" );
    }
}

/*-----------------------------------------------------------*/
/* Tick timer setup.                                          */
/*-----------------------------------------------------------*/

/* Program the CLINT compare register one tick ahead of the current time.
 * 64-bit mtime is read hi/lo/hi to tolerate a low-word rollover; mtimecmp
 * is written low/high in the order the CLINT expects (the trap-path re-arm
 * in upstream portASM.S uses the 0xFFFFFFFF-low-first sequence). */
void vPortSetupTickTimer( void )
{
    volatile uint32_t * const pulTimeHigh = ( volatile uint32_t * ) ( CLINT_MTIME + 4UL );
    volatile uint32_t * const pulTimeLow = ( volatile uint32_t * ) ( CLINT_MTIME );
    volatile uint64_t * const pulCompare = ( volatile uint64_t * ) CLINT_MTIMECMP;
    uint32_t ulHigh, ulLow;
    uint64_t ullNow;

    pullMachineTimerCompareRegister = pulCompare;

    do
    {
        ulHigh = *pulTimeHigh;
        ulLow = *pulTimeLow;
    } while( ulHigh != *pulTimeHigh );

    ullNow = ( ( uint64_t ) ulHigh << 32ULL ) | ( uint64_t ) ulLow;
    ullNextTime = ullNow + ( uint64_t ) uxTimerIncrementsForOneTick;
    *pulCompare = ullNextTime;
    ullNextTime += ( uint64_t ) uxTimerIncrementsForOneTick;
}

/* Strong override of the weak upstream prototype. The stock implementation
 * in port.c is suppressed via configMTIME_BASE_ADDRESS=0 (it would execute
 * `csrr mhartid`, which traps as illegal-instruction on this core). */
void vPortSetupTimerInterrupt( void )
{
    vPortSetupTickTimer();

    /* Enable machine timer (bit 7) and machine external (bit 11) interrupts.
     * Upstream xPortStartScheduler() does this too when the MTIME addresses
     * are non-zero; with them at 0 the override must do it. mstatus.MIE is
     * still 0 here, so nothing fires until the first task starts. */
    __asm volatile ( "csrs mie, %0" :: "r" ( 0x880U ) );
}

/*-----------------------------------------------------------*/
/* Interrupt routing.                                         */
/*-----------------------------------------------------------*/

/* Weak default firmware MEI ISR: count and ignore. Apps that need
 * interrupt-driven work define their own strong vExternalIRQHandler(). */
__attribute__( ( weak ) ) void vExternalIRQHandler( void )
{
    g_trace_unexpected_irq++;
}

/* Strong override of the weak handler in upstream portASM.S. Called from the
 * trap handler for every non-timer interrupt, with the task context already
 * saved and SP switched to the ISR stack: this IS interrupt context, so
 * FromISR APIs and portYIELD_FROM_ISR() are legal here. */
void freertos_risc_v_application_interrupt_handler( void )
{
    uint32_t ulCause;

    __asm volatile ( "csrr %0, mcause" : "=r" ( ulCause ) );

    if( ulCause == 0x8000000BUL )
    {
        /* Machine external interrupt: uart_rx_ready | spi_done | gpio_edge |
         * tb_test_irq per the SoC aggregation. */
        vExternalIRQHandler();
    }
    else if( ulCause == 0x80000003UL )
    {
        /* Machine software interrupt: clear the source. */
        *( volatile uint32_t * ) CLINT_MSIP = 0U;
    }
    else
    {
        g_trace_unexpected_irq++;
    }
}

/*-----------------------------------------------------------*/
/* Weak application hooks (apps override as needed).          */
/*-----------------------------------------------------------*/

__attribute__( ( weak ) ) void vApplicationTickHook( void )
{
}

/*-----------------------------------------------------------*/
/* Loud-failure handlers.                                     */
/*-----------------------------------------------------------*/

void vAssertFailed( const char * pcFile, unsigned long ulLine )
{
    uart_puts( "\nASSERT " );
    uart_puts( pcFile );
    uart_putc( ':' );
    prvPutU32Dec( ( uint32_t ) ulLine );
    uart_puts( "\n" );
    prvHalt();
}

void vApplicationMallocFailedHook( void )
{
    uart_puts( "\nMALLOC FAILED\n" );
    prvHalt();
}

void vApplicationStackOverflowHook( TaskHandle_t xTask, char * pcTaskName )
{
    ( void ) xTask;
    uart_puts( "\nSTACK OVERFLOW in " );
    uart_puts( pcTaskName );
    uart_putc( '\n' );
    prvHalt();
}

/* A task function that returns lands here (configTASK_RETURN_ADDRESS). */
void vTaskReturnHandler( void )
{
    uart_puts( "\nTASK RETURNED\n" );
    prvHalt();
}

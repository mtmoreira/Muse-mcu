/* rtos_regtest.c — B1: register preservation across context switches.
 *
 * New code (covers the template's register-test requirement; no upstream
 * RISC-V regtest exists). Three tasks each own a distinct 32-bit pattern.
 * The fill/yield/verify sequence is pure assembly in vRegTestAsm():
 *
 *   1. load the task pattern into x5 (t0),
 *   2. fill x1,x6-x31 with the pattern,
 *   3. ecall -> FreeRTOS yield -> full context save/restore,
 *   4. verify every filled register still holds the pattern (in x5).
 *
 * Register coverage note: the upstream port's context is x1 and x5-x31
 * (x2/SP is switched, not filled). x0 is hardwired 0 by the ISA. x3 (gp)
 * and x4 (tp) are explicitly NOT saved/restored by the port ("the global
 * and thread pointers are currently assumed to be constant", portASM.S),
 * so filling them would test something the port does not guarantee; they
 * are excluded by design, not by oversight. x5 holds the pattern across
 * the yield (it is preserved by the context switch) and is verified
 * implicitly by the other checks.
 *
 * Any mismatch calls vRegTestFail(), which prints
 * "TEST regtest FAIL: ..." and halts. Between assembly batches each task
 * also executes a real vTaskDelay(2), so both the voluntary-yield and the
 * tick-driven block/wake context-switch paths are exercised; the 1 kHz tick
 * additionally preempts at arbitrary points inside the sequences.
 *
 * Progress: "MARK regtest <n>" every 100 switches; "TEST regtest PASS" once
 * 600 switches are observed with zero mismatches, then halt.
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "mcu.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define REGTEST_SWITCHES_FOR_PASS   ( 600U )
#define REGTEST_MARK_EVERY          ( 100U )
#define REGTEST_BATCH_ITERS         ( 50U )

/* Non-static: referenced from inline asm in vRegTestAsm; must survive --gc-sections. */
const uint32_t ulRegTestPattern[ 3 ] =
{
    0x11111111U, 0x22222222U, 0x44444444U
};

static volatile uint32_t ulRegTestCount[ 3 ] = { 0U, 0U, 0U };
static volatile uint32_t ulTotalSwitches = 0U;
static volatile uint32_t ulRegTestFailReg = 0U;
static volatile uint32_t ulRegTestFailExpected = 0U;
static volatile uint32_t ulRegTestFailIdx = 0U;
static volatile int iPassDone = 0;

/*-----------------------------------------------------------*/

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

/* Called from the assembly loop after every verified iteration. */
void vRegTestHousekeeping( uint32_t ulIdx )
{
    uint32_t ulTotal;

    ulRegTestCount[ ulIdx ]++;
    ulTotal = ++ulTotalSwitches;

    if( ( ulTotal % REGTEST_MARK_EVERY ) == 0 )
    {
        uart_puts( "MARK regtest " );
        prvPutU32Dec( ulTotal );
        uart_puts( " ctxsw=" );
        prvPutU32Dec( ( uint32_t ) g_trace_ctxsw );
        uart_putc( '\n' );
    }

    if( ( ulTotal >= REGTEST_SWITCHES_FOR_PASS ) && ( iPassDone == 0 ) )
    {
        iPassDone = 1;
        uart_puts( "TEST regtest PASS switches=" );
        prvPutU32Dec( ulTotal );
        uart_puts( " ctxsw=" );
        prvPutU32Dec( ( uint32_t ) g_trace_ctxsw );
        uart_putc( '\n' );
        prvHalt();
    }
}

static volatile uint32_t ulRegTestFailReported = 0;

/* Called from the assembly loop on any register mismatch. Never returns. */
void vRegTestFail( uint32_t ulIdx, uint32_t ulReg, uint32_t ulExpected )
{
    /* Only the first failing task reports; the others halt silently.
     * Disable interrupts to keep the report atomic. */
    __asm volatile ( "csrci mstatus, 8" ::: "memory" );
    if( ulRegTestFailReported == 0 )
    {
        ulRegTestFailReported = 1;
        uart_puts( "TEST regtest FAIL: task " );
        prvPutU32Dec( ulIdx );
        uart_puts( " x" );
        prvPutU32Dec( ulReg );
        uart_puts( " expected " );
        puthex32( ulExpected );
        uart_putc( '\n' );
    }
    prvHalt();
}

/*-----------------------------------------------------------*/
/* Pure-assembly fill -> ecall -> verify loop.
 *
 * The pattern is kept in x5 (t0) across the ecall; x5 is preserved by the
 * FreeRTOS context switch, so no stack reload is needed after the yield.
 * x1 and x6-x31 are filled with the pattern; x0 is hardwired 0, x2 is SP,
 * x3/x4 (gp/tp) are not context-switched by the port, x5 holds the pattern.
 *
 * a0 = task index, a1 = iteration count on entry. The C call to
 * vRegTestHousekeeping happens outside the fill/verify critical region.
 */
__attribute__( ( naked ) ) static void vRegTestAsm( uint32_t ulIdx,
                                                   uint32_t ulIters )
{
    __asm volatile
    (
        "addi sp, sp, -32\n"
        "sw ra, 28(sp)\n"
        "sw a0, 24(sp)\n"        /* task index */
        "sw a1, 20(sp)\n"        /* iterations remaining */
        "1:\n"
        /* t0 (x5) = ulRegTestPattern[idx]; kept in x5 across the ecall */
        "lw a0, 24(sp)\n"
        "la t0, ulRegTestPattern\n"
        "slli a0, a0, 2\n"
        "add t0, t0, a0\n"
        "lw t0, 0(t0)\n"
        /* fill x1,x6-x31 with the pattern (x5 holds pattern) */
        "mv x1, t0\n"
        "mv x6, t0\n"
        "mv x7, t0\n"
        "mv x8, t0\n"
        "mv x9, t0\n"
        "mv x10, t0\n"
        "mv x11, t0\n"
        "mv x12, t0\n"
        "mv x13, t0\n"
        "mv x14, t0\n"
        "mv x15, t0\n"
        "mv x16, t0\n"
        "mv x17, t0\n"
        "mv x18, t0\n"
        "mv x19, t0\n"
        "mv x20, t0\n"
        "mv x21, t0\n"
        "mv x22, t0\n"
        "mv x23, t0\n"
        "mv x24, t0\n"
        "mv x25, t0\n"
        "mv x26, t0\n"
        "mv x27, t0\n"
        "mv x28, t0\n"
        "mv x29, t0\n"
        "mv x30, t0\n"
        "mv x31, t0\n"
        "ecall\n"                /* yield: full context save/restore */
        /* verify x1,x6-x31 == x5 (t0). x6 is checked FIRST, before t1
           (which is x6) is used as the ID scratch. */
        "bne x6, t0, 9f\n"
        "li t1, 1\n"  "bne x1, t0, 8f\n"
        "li t1, 7\n"  "bne x7, t0, 8f\n"
        "li t1, 8\n"  "bne x8, t0, 8f\n"
        "li t1, 9\n"  "bne x9, t0, 8f\n"
        "li t1, 10\n" "bne x10, t0, 8f\n"
        "li t1, 11\n" "bne x11, t0, 8f\n"
        "li t1, 12\n" "bne x12, t0, 8f\n"
        "li t1, 13\n" "bne x13, t0, 8f\n"
        "li t1, 14\n" "bne x14, t0, 8f\n"
        "li t1, 15\n" "bne x15, t0, 8f\n"
        "li t1, 16\n" "bne x16, t0, 8f\n"
        "li t1, 17\n" "bne x17, t0, 8f\n"
        "li t1, 18\n" "bne x18, t0, 8f\n"
        "li t1, 19\n" "bne x19, t0, 8f\n"
        "li t1, 20\n" "bne x20, t0, 8f\n"
        "li t1, 21\n" "bne x21, t0, 8f\n"
        "li t1, 22\n" "bne x22, t0, 8f\n"
        "li t1, 23\n" "bne x23, t0, 8f\n"
        "li t1, 24\n" "bne x24, t0, 8f\n"
        "li t1, 25\n" "bne x25, t0, 8f\n"
        "li t1, 26\n" "bne x26, t0, 8f\n"
        "li t1, 27\n" "bne x27, t0, 8f\n"
        "li t1, 28\n" "bne x28, t0, 8f\n"
        "li t1, 29\n" "bne x29, t0, 8f\n"
        "li t1, 30\n" "bne x30, t0, 8f\n"
        "li t1, 31\n" "bne x31, t0, 8f\n"
        "j 7f\n"
        "9:\n"                   /* x6 mismatch (t1 not yet set) */
        "li t1, 6\n"
        "8:\n"                   /* fail: t1 = reg number, t0 = expected */
        "lw a0, 24(sp)\n"        /* idx */
        "mv a1, t1\n"            /* reg */
        "mv a2, t0\n"            /* expected */
        "call vRegTestFail\n"    /* never returns */
        "7:\n"
        /* housekeeping (C call: outside the fill/verify region) */
        "lw ra, 28(sp)\n"
        "lw a0, 24(sp)\n"
        "call vRegTestHousekeeping\n"
        "lw a1, 20(sp)\n"
        "addi a1, a1, -1\n"
        "sw a1, 20(sp)\n"
        "bnez a1, 1b\n"
        "lw ra, 28(sp)\n"
        "addi sp, sp, 32\n"
        "ret\n"
        :
        :
        : "memory"
    );
}

/*-----------------------------------------------------------*/

static void vRegTestTask( void * pvParameters )
{
    uint32_t ulIdx = ( uint32_t ) ( uintptr_t ) pvParameters;

    for( ; ; )
    {
        /* Real FreeRTOS blocking delay: exercises the tick-driven
         * block/wake context-switch path between verified batches. */
        vTaskDelay( 2 );
        vRegTestAsm( ulIdx, REGTEST_BATCH_ITERS );
    }
}

/*-----------------------------------------------------------*/

int main( void )
{
    uart_puts( "BOOT\n" );
    uart_puts( "TEST regtest START\n" );

    vPortInstallTrapVector();

    xTaskCreate( vRegTestTask, "reg0", configMINIMAL_STACK_SIZE,
                 ( void * ) ( uintptr_t ) 0, 2, NULL );
    xTaskCreate( vRegTestTask, "reg1", configMINIMAL_STACK_SIZE,
                 ( void * ) ( uintptr_t ) 1, 2, NULL );
    xTaskCreate( vRegTestTask, "reg2", configMINIMAL_STACK_SIZE,
                 ( void * ) ( uintptr_t ) 2, 2, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST regtest FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

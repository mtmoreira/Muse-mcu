/* app_demo.c — D1/D2: SPI -> queue -> SHA-256 -> UART end-to-end.
 *
 * New code. Three-task workload per doc/architecture.md section 5:
 *
 *   acquisition task (prio 2): spi_wake_flash(); reads the flash image
 *       header (magic 0x46534C41 "FSLA", version, seed, msg_count) then each
 *       of the 24 messages via SPI 0x03 READ; copies data into a static
 *       pool (4 x 1152 bytes); posts {id, len, buf} to the msg queue
 *       (depth 4); prints "MARK spi_read <id> <len>" and "MARK queue <id>".
 *   sha task (prio 3): blocks on the msg queue; computes sha256_fw();
 *       transmits "PKT 9E55AA01 <id> <len> <digest64hex>" over UART;
 *       prints "MARK sha_done <id>"; returns the buffer to the free pool.
 *   background task (prio 1): continuous xorshift32 loop, never blocks or
 *       yields; prints "MARK bg" every 2k iterations (~20k cycles).
 *
 * D2: sha_selftest_run() executes FIRST at boot, before any task is
 * created. Any vector mismatch prints "SHA SELFTEST FAIL: ..." and
 * halts boot. On success it prints "SHA SELFTEST PASS".
 *
 * After all 24 messages are processed the sha task prints
 * "TEST app_demo PASS" and halts (the testbench watchdog bounds the run).
 *
 * Buffer management: a free-list queue (depth 4) hands pool indices to the
 * acquisition task; the sha task returns them. If the pipeline ever fills,
 * the acquisition task blocks on xQueueSend, providing backpressure. A
 * queue-depth watermark (max uxQueueMessagesWaiting seen) is tracked and
 * reported in the PASS line.
 *
 * Flash image format: tools/gen_flash.py (byte-for-byte contract).
 */

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"

#include "mcu.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

/* D2 self-test (fw/sha256/sha_selftest.c). */
int sha_selftest_run( void );
void sha256_fw( const uint8_t * msg, uint32_t len, uint8_t out[ 32 ] );

/*-----------------------------------------------------------*/
/* Flash image layout (tools/gen_flash.py).                   */
/*-----------------------------------------------------------*/
#define FLASH_MAGIC       0x46534C41UL
#define FLASH_VERSION     1UL
/* Build-overridable for the F2 gate subset (4 messages): the D1 image keeps
 * the default 24. The .hex/.elf pair for F2 is built with
 * EXTRA_DEFS=-DFLASH_MSG_COUNT=4 into a separate build dir; the frozen D1
 * image (fw/build/app_demo.hex) is untouched. */
#ifndef FLASH_MSG_COUNT
#define FLASH_MSG_COUNT   24U
#endif
#define FLASH_MAX_MSG     1024U
#define POOL_BUFS         4U
#define POOL_BUF_SIZE     1152U

typedef struct
{
    uint32_t id;
    uint32_t len;
    uint8_t buf;
} msg_t;

static uint8_t ucMsgPool[ POOL_BUFS ][ POOL_BUF_SIZE ];
static QueueHandle_t xMsgQueue = NULL;
static QueueHandle_t xFreeQueue = NULL;
static SemaphoreHandle_t xPrintMutex = NULL;
static volatile uint32_t ulQueueWatermark = 0;
static volatile uint32_t ulMsgsDone = 0;
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

static void prvPutHexByte( uint8_t b )
{
    static const char hd[] = "0123456789abcdef";
    uart_putc( hd[ ( b >> 4 ) & 0xFU ] );
    uart_putc( hd[ b & 0xFU ] );
}

static void prvHalt( void )
{
    for( ; ; )
    {
    }
}

static void prvFail( const char * reason )
{
    xSemaphoreTake( xPrintMutex, portMAX_DELAY );
    uart_puts( "TEST app_demo FAIL: " );
    uart_puts( reason );
    uart_putc( '\n' );
    prvHalt();
}

/* Read n bytes from SPI flash address addr via 0x03 READ. */
static void prvSpiRead( uint32_t addr, uint8_t * dst, uint32_t n )
{
    spi_cs_low();
    spi_xfer( 0x03 );
    spi_xfer( ( uint8_t ) ( addr >> 16 ) );
    spi_xfer( ( uint8_t ) ( addr >> 8 ) );
    spi_xfer( ( uint8_t ) addr );
    spi_read( dst, ( int ) n );
    spi_cs_high();
}

static uint32_t prvGetU32LE( const uint8_t * p )
{
    return ( ( uint32_t ) p[ 0 ] ) |
           ( ( uint32_t ) p[ 1 ] << 8 ) |
           ( ( uint32_t ) p[ 2 ] << 16 ) |
           ( ( uint32_t ) p[ 3 ] << 24 );
}

/*-----------------------------------------------------------*/
/* Acquisition task (prio 2).                                 */
/*-----------------------------------------------------------*/

static void vAcqTask( void * pvParameters )
{
    uint8_t hdr[ 16 ];
    uint8_t mhdr[ 8 ];
    uint32_t magic, version, seed, msg_count;
    uint32_t offset;
    uint32_t i;
    msg_t msg;
    UBaseType_t uxWaiting;

    ( void ) pvParameters;

    spi_wake_flash();

    /* Flash image header. */
    prvSpiRead( 0, hdr, 16 );
    magic = prvGetU32LE( hdr + 0 );
    version = prvGetU32LE( hdr + 4 );
    seed = prvGetU32LE( hdr + 8 );
    msg_count = prvGetU32LE( hdr + 12 );

    if( ( magic != FLASH_MAGIC ) || ( version != FLASH_VERSION ) ||
        ( msg_count != FLASH_MSG_COUNT ) )
    {
        prvFail( "bad flash header" );
    }

    offset = 16;
    for( i = 0; i < msg_count; i++ )
    {
        /* Take a free pool buffer (blocks when the pipeline is full). */
        if( xQueueReceive( xFreeQueue, &msg.buf, portMAX_DELAY ) != pdPASS )
        {
            prvFail( "free queue" );
        }

        /* Message header: id, len. */
        prvSpiRead( offset, mhdr, 8 );
        msg.id = prvGetU32LE( mhdr + 0 );
        msg.len = prvGetU32LE( mhdr + 4 );
        offset += 8;

        if( ( msg.id != i ) || ( msg.len > FLASH_MAX_MSG ) )
        {
            prvFail( "bad message header" );
        }

        /* Message data. */
        if( msg.len > 0 )
        {
            prvSpiRead( offset, ucMsgPool[ msg.buf ], msg.len );
        }
        offset += msg.len;

        /* Hand to the SHA task (blocks when the queue is full:
         * backpressure). Track the depth watermark and publish it to the
         * GPIO debug scratch register (the testbench's observation
         * point for queue pressure). */
        if( xQueueSend( xMsgQueue, &msg, portMAX_DELAY ) != pdPASS )
        {
            prvFail( "msg queue send" );
        }
        uxWaiting = uxQueueMessagesWaiting( xMsgQueue );
        if( uxWaiting > ulQueueWatermark )
        {
            ulQueueWatermark = uxWaiting;
            GPIO_DBG_SCRATCH = ulQueueWatermark;
        }

        xSemaphoreTake( xPrintMutex, portMAX_DELAY );
        uart_puts( "MARK spi_read " );
        prvPutU32Dec( msg.id );
        uart_putc( ' ' );
        prvPutU32Dec( msg.len );
        uart_putc( '\n' );
        uart_puts( "MARK queue " );
        prvPutU32Dec( msg.id );
        uart_putc( '\n' );
        xSemaphoreGive( xPrintMutex );
    }

    /* All messages injected; the sha task will finish and report. */
    vTaskDelete( NULL );
}

/*-----------------------------------------------------------*/
/* SHA task (prio 3).                                          */
/*-----------------------------------------------------------*/

static void vShaTask( void * pvParameters )
{
    msg_t msg;
    uint8_t digest[ 32 ];
    uint32_t i;

    ( void ) pvParameters;

    for( ; ; )
    {
        xQueueReceive( xMsgQueue, &msg, portMAX_DELAY );

        sha256_fw( ucMsgPool[ msg.buf ], msg.len, digest );

        xSemaphoreTake( xPrintMutex, portMAX_DELAY );
        uart_puts( "PKT 9E55AA01 " );
        prvPutU32Dec( msg.id );
        uart_putc( ' ' );
        prvPutU32Dec( msg.len );
        uart_putc( ' ' );
        for( i = 0; i < 32; i++ )
        {
            prvPutHexByte( digest[ i ] );
        }
        uart_putc( '\n' );
        uart_puts( "MARK sha_done " );
        prvPutU32Dec( msg.id );
        uart_putc( '\n' );
        xSemaphoreGive( xPrintMutex );

        /* Return the buffer to the pool. */
        xQueueSend( xFreeQueue, &msg.buf, portMAX_DELAY );

        /* Pace the consumer: 6 ticks (300k cycles) per message. While the
         * SHA task is delayed and the acquisition task is blocked on the
         * full message queue, the background task (prio 1) runs; it is
         * preempted again when the SHA task unblocks. Without this, the
         * acquisition and SHA tasks are never blocked simultaneously and
         * the background task starves. The delay exceeds the acq task's
         * per-message work (~250k cycles, mostly its MARK prints) so the
         * acq task reliably blocks and yields to bg. */
        vTaskDelay( 6 );

        ulMsgsDone++;
        if( ( ulMsgsDone >= FLASH_MSG_COUNT ) && ( iPassDone == 0 ) )
        {
            iPassDone = 1;
            xSemaphoreTake( xPrintMutex, portMAX_DELAY );
            /* Exact marker-protocol line the testbench waits for. */
            uart_puts( "TEST app_demo PASS\n" );
            uart_puts( "MARK watermark " );
            prvPutU32Dec( ulQueueWatermark );
            uart_putc( '\n' );
            prvHalt();
        }
    }
}

/*-----------------------------------------------------------*/
/* Background task (prio 1): continuous compute, never blocks. */
/*-----------------------------------------------------------*/

static void vBgTask( void * pvParameters )
{
    uint32_t x = 0x9E3779B9U;
    uint32_t iters = 0;

    ( void ) pvParameters;

    for( ; ; )
    {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        /* Mark every 2k iterations (~20k cycles): fast enough for the
         * testbench's >= 10 MARK bg threshold within the background
         * task's scheduled windows, slow enough to keep UART overhead
         * negligible. */
        if( ++iters >= 2000U )
        {
            iters = 0;
            /* Best-effort print: never block the compute loop on the
             * print mutex; skip the mark if another task is printing.
             * Exact marker-protocol line counted by the testbench. */
            if( xSemaphoreTake( xPrintMutex, 0 ) == pdPASS )
            {
                uart_puts( "MARK bg\n" );
                xSemaphoreGive( xPrintMutex );
            }
        }
    }
}

/*-----------------------------------------------------------*/

int main( void )
{
    uint8_t b;

    uart_puts( "BOOT\n" );

    /* D2 FIRST: self-test the SHA-256 before anything else starts. */
    if( sha_selftest_run() != 0 )
    {
        prvHalt();
    }

    uart_puts( "TEST app_demo START\n" );

    vPortInstallTrapVector();

    xMsgQueue = xQueueCreate( 4, sizeof( msg_t ) );
    configASSERT( xMsgQueue != NULL );
    xFreeQueue = xQueueCreate( POOL_BUFS, sizeof( uint8_t ) );
    configASSERT( xFreeQueue != NULL );
    xPrintMutex = xSemaphoreCreateMutex();
    configASSERT( xPrintMutex != NULL );

    /* Pre-fill the free list. */
    for( b = 0; b < POOL_BUFS; b++ )
    {
        configASSERT( xQueueSend( xFreeQueue, &b, 0 ) == pdPASS );
    }

    xTaskCreate( vAcqTask, "acq", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vShaTask, "sha", configMINIMAL_STACK_SIZE * 2, NULL, 3, NULL );
    xTaskCreate( vBgTask, "bg", configMINIMAL_STACK_SIZE, NULL, 1, NULL );

    vTaskStartScheduler();

    uart_puts( "TEST app_demo FAIL: scheduler returned\n" );
    prvHalt();
    return 0;
}

/* image_demo.c — visual application demo (spec v1.0, 2026-10-13).
 *
 * New code. Pipeline:
 *   ImageIO (prio 1): reads a 64x64 GRAY8 image (20-byte "MIMG" header +
 *     4096 pixels) from SPI flash into img_in[], validates the header,
 *     releases the two gradient workers, blocks until the output
 *     framebuffer is complete, then exports header + pixels + SHA-256
 *     digest over UART.
 *   GradientX / GradientY (prio 2): wait for input, compute the Sobel
 *     Gx / Gy of Section 2.2 into img_gx[] / img_gy[] (int16), stripe
 *     by stripe (16 stripes x 4 rows), publishing each finished stripe
 *     ID on a dedicated depth-2 queue.
 *   Combine (prio 3): for each stripe, waits for BOTH gradient IDs,
 *     writes img_out[] = min(255, |Gx| + |Gy|) for every pixel of the
 *     stripe (borders explicitly zero), then notifies ImageIO.
 *
 * UART carries ONLY the output packet during this demo. All
 * diagnostics go to the GPIO debug scratch register (trace codes
 * below), which the testbench records with cycle stamps:
 *   0x1000 load begin        0x1001 load done (input immutable)
 *   0x2000|s GradientX stripe s writes complete (traced before the
 *            queue publication; a post-send trace could be preempted
 *            by Combine and appear out of order)
 *   0x3000|s GradientY stripe s writes complete (same)
 *   0x4000|s Combine wrote stripe s         (after its writes)
 *   0x5000 frame complete    0x6000 export begin   0x6001 export done
 *   0x7F00|n fatal error n (then halt)
 *
 * Buffers are dedicated and non-overlapping (24 KiB total):
 *   img_in 4096 B, img_gx 8192 B, img_gy 8192 B, img_out 4096 B.
 * Their addresses are resolved from the ELF by the host tools.
 */

#include <stdint.h>
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"

#include "mcu.h"
#include "sha256.h"

/* Provided by fw/port/port_glue.S. */
void vPortInstallTrapVector( void );

#define IMG_W        64U
#define IMG_H        64U
#define NPIX         ( IMG_W * IMG_H )
#define STRIPES      16U
#define STRIPE_ROWS  4U
#define HDR_LEN      20U

static uint8_t  img_in[ NPIX ];
static int16_t  img_gx[ NPIX ];
static int16_t  img_gy[ NPIX ];
static uint8_t  img_out[ NPIX ];

static QueueHandle_t xQGx = NULL;
static QueueHandle_t xQGy = NULL;
static SemaphoreHandle_t xStartGx = NULL;
static SemaphoreHandle_t xStartGy = NULL;
static SemaphoreHandle_t xFrameDone = NULL;

#define TRACE( code )  ( GPIO_DBG_SCRATCH = ( uint32_t ) ( code ) )

static void prvHalt( void )
{
    for( ; ; )
    {
    }
}

static void prvFail( uint32_t n )
{
    TRACE( 0x7F00U | n );
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

static uint16_t prvGetU16LE( const uint8_t * p )
{
    return ( uint16_t ) ( p[ 0 ] | ( ( uint16_t ) p[ 1 ] << 8 ) );
}

static uint32_t prvGetU32LE( const uint8_t * p )
{
    return ( ( uint32_t ) p[ 0 ] ) | ( ( uint32_t ) p[ 1 ] << 8 ) |
           ( ( uint32_t ) p[ 2 ] << 16 ) | ( ( uint32_t ) p[ 3 ] << 24 );
}

/*-----------------------------------------------------------*/
/* ImageIO (prio 1).                                          */
/*-----------------------------------------------------------*/

static void vImageIOTask( void * pvParameters )
{
    uint8_t hdr[ HDR_LEN ];
    uint32_t frame_id;
    uint32_t y;

    ( void ) pvParameters;

    TRACE( 0x1000 );

    spi_wake_flash();

    prvSpiRead( 0, hdr, HDR_LEN );
    if( ( hdr[ 0 ] != 'M' ) || ( hdr[ 1 ] != 'I' ) ||
        ( hdr[ 2 ] != 'M' ) || ( hdr[ 3 ] != 'G' ) )
    {
        prvFail( 1 ); /* bad magic */
    }
    if( ( hdr[ 4 ] != 1 ) || ( hdr[ 5 ] != 1 ) )
    {
        prvFail( 2 ); /* bad version or pixel format */
    }
    frame_id = prvGetU32LE( hdr + 8 );
    ( void ) frame_id; /* recorded by the testbench via the header echo */
    if( ( prvGetU16LE( hdr + 12 ) != IMG_W ) ||
        ( prvGetU16LE( hdr + 14 ) != IMG_H ) ||
        ( prvGetU32LE( hdr + 16 ) != NPIX ) )
    {
        prvFail( 3 ); /* bad geometry */
    }

    /* Payload: one SPI read per row, straight into the input buffer. */
    for( y = 0; y < IMG_H; y++ )
    {
        prvSpiRead( HDR_LEN + y * IMG_W, &img_in[ y * IMG_W ], IMG_W );
    }

    TRACE( 0x1001 ); /* input complete and immutable from here */

    xSemaphoreGive( xStartGx );
    xSemaphoreGive( xStartGy );

    /* Block until Combine signals the completed framebuffer. */
    if( xSemaphoreTake( xFrameDone, portMAX_DELAY ) != pdTRUE )
    {
        prvFail( 4 );
    }

    TRACE( 0x6000 ); /* export begin */

    /* Packet: the same 20-byte header, the stored framebuffer, then
     * the SHA-256 of header+payload computed from the stored bytes. */
    {
        SHA256Context ctx;
        uint8_t digest[ 32 ];
        uint32_t i;

        SHA256Reset( &ctx );
        SHA256Input( &ctx, hdr, HDR_LEN );
        SHA256Input( &ctx, img_out, NPIX );
        SHA256Result( &ctx, digest );

        for( i = 0; i < HDR_LEN; i++ )
        {
            uart_putc( ( char ) hdr[ i ] );
        }
        for( i = 0; i < NPIX; i++ )
        {
            uart_putc( ( char ) img_out[ i ] );
        }
        for( i = 0; i < 32; i++ )
        {
            uart_putc( ( char ) digest[ i ] );
        }
    }

    TRACE( 0x6001 ); /* export done */
    prvHalt();
}

/*-----------------------------------------------------------*/
/* Gradient workers (prio 2).                                 */
/*-----------------------------------------------------------*/

static void prvGradientTask( int is_x,
                              SemaphoreHandle_t xStart,
                              QueueHandle_t xQueue,
                              uint32_t trace_base )
{
    uint32_t s, x, y;

    if( xSemaphoreTake( xStart, portMAX_DELAY ) != pdTRUE )
    {
        prvFail( 5 );
    }

    for( s = 0; s < STRIPES; s++ )
    {
        uint32_t y0 = s * STRIPE_ROWS;
        uint32_t y1 = y0 + STRIPE_ROWS - 1;

        for( y = y0; y <= y1; y++ )
        {
            for( x = 0; x < IMG_W; x++ )
            {
                int32_t g = 0;

                if( ( x >= 1 ) && ( x <= 62 ) && ( y >= 1 ) && ( y <= 62 ) )
                {
                    const uint8_t * im = img_in;
                    if( is_x )
                    {
                        g = -( int32_t ) im[ ( y - 1 ) * 64 + ( x - 1 ) ]
                            + ( int32_t ) im[ ( y - 1 ) * 64 + ( x + 1 ) ]
                            - 2 * ( int32_t ) im[ y * 64 + ( x - 1 ) ]
                            + 2 * ( int32_t ) im[ y * 64 + ( x + 1 ) ]
                            - ( int32_t ) im[ ( y + 1 ) * 64 + ( x - 1 ) ]
                            + ( int32_t ) im[ ( y + 1 ) * 64 + ( x + 1 ) ];
                    }
                    else
                    {
                        g = -( int32_t ) im[ ( y - 1 ) * 64 + ( x - 1 ) ]
                            - 2 * ( int32_t ) im[ ( y - 1 ) * 64 + x ]
                            - ( int32_t ) im[ ( y - 1 ) * 64 + ( x + 1 ) ]
                            + ( int32_t ) im[ ( y + 1 ) * 64 + ( x - 1 ) ]
                            + 2 * ( int32_t ) im[ ( y + 1 ) * 64 + x ]
                            + ( int32_t ) im[ ( y + 1 ) * 64 + ( x + 1 ) ];
                    }
                }

                if( is_x )
                {
                    img_gx[ y * IMG_W + x ] = ( int16_t ) g;
                }
                else
                {
                    img_gy[ y * IMG_W + x ] = ( int16_t ) g;
                }
            }
        }

        /* Gradient writes for this stripe are complete. Trace BEFORE
         * publishing: the send unblocks Combine (higher priority),
         * which would preempt this task before a post-send trace
         * could execute, inverting the observed order. */
        TRACE( trace_base | s );
        {
            uint8_t id = ( uint8_t ) s;
            if( xQueueSend( xQueue, &id, portMAX_DELAY ) != pdPASS )
            {
                prvFail( 6 );
            }
        }
    }

    vTaskDelete( NULL );
}

static void vGradientXTask( void * pvParameters )
{
    ( void ) pvParameters;
    prvGradientTask( 1, xStartGx, xQGx, 0x2000U );
}

static void vGradientYTask( void * pvParameters )
{
    ( void ) pvParameters;
    prvGradientTask( 0, xStartGy, xQGy, 0x3000U );
}

/*-----------------------------------------------------------*/
/* Combine (prio 3).                                          */
/*-----------------------------------------------------------*/

static void vCombineTask( void * pvParameters )
{
    uint32_t s, i;

    ( void ) pvParameters;

    for( s = 0; s < STRIPES; s++ )
    {
        uint8_t a = 0xFF, b = 0xFF;

        if( xQueueReceive( xQGx, &a, portMAX_DELAY ) != pdPASS )
        {
            prvFail( 7 );
        }
        if( xQueueReceive( xQGy, &b, portMAX_DELAY ) != pdPASS )
        {
            prvFail( 8 );
        }
        if( ( a != s ) || ( b != s ) )
        {
            prvFail( 9 ); /* stripe identity mismatch */
        }

        for( i = s * STRIPE_ROWS * IMG_W;
             i < ( s + 1 ) * STRIPE_ROWS * IMG_W; i++ )
        {
            int32_t v = img_gx[ i ];
            int32_t w = img_gy[ i ];
            if( v < 0 ) v = -v;
            if( w < 0 ) w = -w;
            v += w;
            if( v > 255 ) v = 255;
            img_out[ i ] = ( uint8_t ) v;
        }

        TRACE( 0x4000U | s );
    }

    TRACE( 0x5000 );
    xSemaphoreGive( xFrameDone );
    vTaskDelete( NULL );
}

/*-----------------------------------------------------------*/

int main( void )
{
    vPortInstallTrapVector();

    xQGx = xQueueCreate( 2, sizeof( uint8_t ) );
    xQGy = xQueueCreate( 2, sizeof( uint8_t ) );
    xStartGx = xSemaphoreCreateBinary();
    xStartGy = xSemaphoreCreateBinary();
    xFrameDone = xSemaphoreCreateBinary();
    if( ( xQGx == NULL ) || ( xQGy == NULL ) || ( xStartGx == NULL ) ||
        ( xStartGy == NULL ) || ( xFrameDone == NULL ) )
    {
        prvFail( 10 );
    }

    xTaskCreate( vImageIOTask, "imgio", configMINIMAL_STACK_SIZE * 2,
                 NULL, 1, NULL );
    xTaskCreate( vGradientXTask, "gradx", configMINIMAL_STACK_SIZE,
                 NULL, 2, NULL );
    xTaskCreate( vGradientYTask, "grady", configMINIMAL_STACK_SIZE,
                 NULL, 2, NULL );
    xTaskCreate( vCombineTask, "combn", configMINIMAL_STACK_SIZE,
                 NULL, 3, NULL );

    vTaskStartScheduler();

    prvFail( 11 ); /* scheduler returned */
    return 0;
}

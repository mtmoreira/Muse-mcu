/* sha_selftest.c — D2 boot self-test for the firmware SHA-256 (new code).
 *
 * Runs 8 NIST CAVP byte-oriented vectors (from selftest_vectors.h, generated
 * by tools/gen_sha_vectors.py) through sha256_fw() and compares digests.
 *
 * NOTE on vector naming: the contract brief lists 'empty, "abc", 55/56/64
 * byte, multi-block'. The vendored CAVS .rsp files contain pseudorandom
 * messages, not ASCII "abc": the Len=24 vector's message is b4:19:0e with
 * digest dff2e730..., which is what the .rsp (and this test) uses. The
 * empty/55/56/64-byte/multi-block coverage is exactly as required; every
 * expected digest is cross-verified against Python hashlib (see the
 * generator run log).
 */

#include <stdint.h>

#include "sha256.h"
#include "selftest_vectors.h"

/* UART output, provided by the platform driver. */
extern void uart_puts( const char * s );
extern void uart_putc( char c );

void sha256_fw( const uint8_t * msg, uint32_t len, uint8_t out[ 32 ] );

static int prvMemcmp( const uint8_t * a, const uint8_t * b, uint32_t n )
{
    uint32_t i;
    for( i = 0; i < n; i++ )
    {
        if( a[ i ] != b[ i ] )
        {
            return 1;
        }
    }
    return 0;
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

/* Returns 0 on success (prints SHA SELFTEST PASS), non-zero on failure
 * (prints SHA SELFTEST FAIL: <index> and the caller must halt boot). */
int sha_selftest_run( void )
{
    uint32_t i;
    uint8_t digest[ 32 ];

    uart_puts( "SHA SELFTEST START\n" );

    for( i = 0; i < ( uint32_t ) SHA_SELFTEST_NVECS; i++ )
    {
        sha256_fw( sha_selftest_vecs[ i ].msg,
                   sha_selftest_vecs[ i ].len,
                   digest );

        if( prvMemcmp( digest, sha_selftest_vecs[ i ].expect, 32 ) != 0 )
        {
            uart_puts( "SHA SELFTEST FAIL: vector " );
            prvPutU32Dec( i );
            uart_puts( " len=" );
            prvPutU32Dec( sha_selftest_vecs[ i ].len );
            uart_putc( '\n' );
            return 1;
        }
    }

    uart_puts( "SHA SELFTEST PASS\n" );
    return 0;
}

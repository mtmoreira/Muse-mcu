/* sha256_fw.c — firmware wrapper around the RFC 6234 SHA-256 (new code).
 *
 * The compression function and padding logic live in the byte-identical
 * upstream sha256.c; this file only adapts the calling convention to what
 * the firmware needs: one shot, no stdio, no dynamic allocation.
 */

#include <stdint.h>

#include "sha256.h"

/* Compute SHA-256 of msg[0..len) into out[32]. */
void sha256_fw( const uint8_t * msg, uint32_t len, uint8_t out[ 32 ] )
{
    SHA256Context ctx;

    SHA256Reset( &ctx );

    if( len > 0 )
    {
        /* SHA256Input takes unsigned int; len is uint32_t, same width. */
        SHA256Input( &ctx, msg, ( unsigned int ) len );
    }

    SHA256Result( &ctx, out );
}

/* string.c — freestanding memory/string primitives for -nostdlib firmware.
 * Needed by the FreeRTOS kernel (pvPortCalloc, ISR-stack fill) and drivers.
 * Written fresh for Muse MCU.
 */
#include <stddef.h>

void * memset( void * s, int c, size_t n )
{
    unsigned char * p = ( unsigned char * ) s;
    while( n-- )
    {
        *p++ = ( unsigned char ) c;
    }
    return s;
}

void * memcpy( void * d, const void * s, size_t n )
{
    unsigned char * dp = ( unsigned char * ) d;
    const unsigned char * sp = ( const unsigned char * ) s;
    while( n-- )
    {
        *dp++ = *sp++;
    }
    return d;
}

int memcmp( const void * a, const void * b, size_t n )
{
    const unsigned char * pa = ( const unsigned char * ) a;
    const unsigned char * pb = ( const unsigned char * ) b;
    while( n-- )
    {
        if( *pa != *pb )
        {
            return ( int ) *pa - ( int ) *pb;
        }
        pa++;
        pb++;
    }
    return 0;
}

int strcmp( const char * a, const char * b )
{
    while( *a && ( *a == *b ) )
    {
        a++;
        b++;
    }
    return ( int )( unsigned char ) *a - ( int )( unsigned char ) *b;
}

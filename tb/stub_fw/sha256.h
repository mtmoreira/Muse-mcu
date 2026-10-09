#ifndef SHA256_H
#define SHA256_H
#include <stdint.h>
typedef struct { uint32_t h[8]; uint64_t len; uint8_t buf[64]; uint32_t nbuf; } sha256_t;
void sha256_init(sha256_t *c);
void sha256_update(sha256_t *c, const uint8_t *data, uint32_t n);
void sha256_final(sha256_t *c, uint8_t out[32]);
#endif

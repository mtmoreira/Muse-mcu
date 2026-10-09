/* Host test driver for extracted RFC 6234 sha256.c.
 * Uses the RFC's own test vectors (section 8.5) plus standard FIPS vectors.
 * This driver is NOT part of the vendored artifact; it only proves the
 * extracted code is correct. (Adaptation boundary: the embedded firmware
 * replaces this stdio driver with its own self-test.)
 */
#include <stdio.h>
#include <string.h>
#include "sha256.h"

static int fails = 0;

static void check(const char *name, const uint8_t *msg, size_t len,
                  const char *expect_hex)
{
    SHA256Context ctx;
    uint8_t digest[SHA256HashSize];
    char got[2 * SHA256HashSize + 1];
    SHA256Reset(&ctx);
    if (len > 0)
        SHA256Input(&ctx, msg, (unsigned int)len);
    SHA256Result(&ctx, digest);
    for (int i = 0; i < SHA256HashSize; i++)
        sprintf(got + 2 * i, "%02x", digest[i]);
    if (strcmp(got, expect_hex) == 0)
        printf("PASS %s\n", name);
    else {
        printf("FAIL %s\n  got    %s\n  expect %s\n", name, got, expect_hex);
        fails++;
    }
}

int main(void)
{
    /* RFC 6234 section 8.5, SHA256 test case 1: "abc" */
    check("rfc-8.5-case1-abc", (const uint8_t *)"abc", 3,
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    /* RFC 6234 section 8.5, SHA256 test case 2: 448-bit message */
    check("rfc-8.5-case2-448bit",
          (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    /* FIPS 180-3: empty string */
    check("fips-empty", (const uint8_t *)"", 0,
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    /* padding boundary: 55 bytes (one block) */
    {
        uint8_t m[55];
        memset(m, 'a', 55);
        check("boundary-55", m, 55,
              "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318");
    }
    /* padding boundary: 56 bytes (two blocks) */
    {
        uint8_t m[56];
        memset(m, 'a', 56);
        check("boundary-56", m, 56,
              "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a");
    }
    /* padding boundary: 64 bytes (two blocks) */
    {
        uint8_t m[64];
        memset(m, 'a', 64);
        check("boundary-64", m, 64,
              "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb");
    }
    /* RFC 6234 section 8.5, SHA256 test case 3: 1,000,000 x 'a' (multi-block) */
    {
        static uint8_t m[1000000];
        memset(m, 'a', sizeof(m));
        check("rfc-8.5-case3-1M-a", m, sizeof(m),
              "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    }
    printf(fails ? "RESULT: %d FAILURES\n" : "RESULT: ALL PASS\n", fails);
    return fails ? 1 : 0;
}

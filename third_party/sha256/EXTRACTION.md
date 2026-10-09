# RFC 6234 SHA-256 extraction

## Source
`rfc6234.txt` — downloaded 2026-10-08 from
https://www.rfc-editor.org/rfc/rfc6234.txt (236,573 bytes).
RFC 6234, "US Secure Hash Algorithms (SHA and SHA-based HMAC and HKDF)",
IETF, May 2011. Informational. Code carries an IETF Trust BSD-style
license (see the banner comments in the extracted files).

## What was extracted (algorithm verbatim)

| File (in this dir) | RFC section | RFC file name |
|--------------------|-------------|---------------|
| sha256.h           | 8.1.1 "The .h file" | sha.h |
| sha-private.h      | 8.1.3 "sha-private.h" | sha-private.h |
| sha256.c           | 8.2.2 "sha224-256.c" | sha224-256.c |

Extraction was mechanical: for each file, take the RFC text from its
banner line (e.g. `/**************************** sha.h ****************************/`)
up to (not including) the next numbered section header; delete RFC page
headers/footers (`Eastlake & Hansen ... [Page N]`, form-feed, and the
`RFC 6234 ... May 2011` running head). Everything else, comments included,
is verbatim from the RFC.

Deliberately excluded:
- 8.1.2 `stdint-example.h` (host and target both have real `<stdint.h>`)
- 8.2.1 `sha1.c`, 8.2.3 `sha384-512.c`, 8.2.4 `usha.c` (not needed)
- 8.3 HMAC code, 8.4 HKDF code (not needed)
- 8.5 "The Test Driver" (the stdio-based `main()` is replaced by the
  embedded self-test; see architecture.md section 4)

## Mechanical adaptation (one line, documented)
`sha256.c` line 49: `#include "sha.h"` changed to `#include "sha256.h"`
to match the renamed header. No other change.

## Host verification (2026-10-08)
Compiled with host gcc 13.3.0: `gcc -Wall -Wextra -O2 sha256.c host_test.c`
(no warnings). `host_test.c` (this dir, NOT part of the vendored artifact)
drives the extracted code through the RFC's own section-8.5 SHA-256
vectors plus standard boundary vectors:

```
PASS rfc-8.5-case1-abc      ("abc" -> ba7816bf...)
PASS rfc-8.5-case2-448bit   (56-byte FIPS message -> 248d6a61...)
PASS fips-empty             ("" -> e3b0c442...)
PASS boundary-55            (55 x 'a', single-block padding)
PASS boundary-56            (56 x 'a', two-block padding)
PASS boundary-64            (64 x 'a', two-block padding)
PASS rfc-8.5-case3-1M-a     (1,000,000 x 'a' multi-block -> cdc76e5c...)
RESULT: ALL PASS
```

The 55/56/64-byte expected values were independently computed with
Python `hashlib.sha256`.

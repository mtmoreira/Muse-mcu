# fw/sha256 — SHA-256 for firmware (adapted from RFC 6234)

## Adaptation boundary

Upstream: `third_party/sha256/{sha256.c,sha-private.h,sha256.h}`, extracted
from RFC 6234, host-tested 7/7 PASS in Phase 1.

- `sha256.c`, `sha-private.h`, `sha256.h` in this directory are **byte-identical
  copies** of the upstream files (`cmp` verified). The compression function,
  message schedule, padding, and length encoding are untouched.
- The upstream stdio-based test driver (`host_test.c`) is **not** used in
  firmware. It is replaced by:
  - `sha256_fw.c` (new): provides
    `void sha256_fw( const uint8_t * msg, uint32_t len, uint8_t out[32] )`,
    a one-shot wrapper around `SHA256Reset`/`SHA256Input`/`SHA256Result`.
    No stdio, no `printf`, no dynamic allocation; freestanding-safe
    (`<stdint.h>` only).
  - `sha_selftest.c` + `selftest_vectors.h` (new): the D2 boot self-test.
    Eight NIST CAVP byte-oriented vectors (empty, "abc", 55/56/64-byte,
    three multi-block) with expected digests. `selftest_vectors.h` is
    **generated** by `tools/gen_sha_vectors.py` from the vendored
    `third_party/nist_vectors/shabytetestvectors/*.rsp` files, so the
    embedded digests are traceable to the NIST source. The contract
    explicitly allows embedding the vectors in this self-test only.

## Verification

- Algorithm: covered by the Phase 1 host test (7/7 PASS) on the identical
  source, plus the on-target `sha_selftest` (8/8 NIST vectors) at every boot
  of `app_demo`.
- D1 end-to-end digests are additionally cross-checked on the host with
  Python `hashlib.sha256` in `tools/check_app.py`.

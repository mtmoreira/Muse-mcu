/* prog_arch_fail.S -- dummy arch-test target (FAIL).
 * Writes FAIL_MAGIC to DONE_ADDR, then ecall. Used to validate tb_arch's
 * failure path (must exit nonzero).
 */
    .text
    .globl _start
_start:
    li   sp, 0x30000
    li   t0, 0x1FFF0            # DONE_ADDR
    li   t1, 0xDEADDEAD         # FAIL_MAGIC
    sw   t1, 0(t0)
    ecall
    j .

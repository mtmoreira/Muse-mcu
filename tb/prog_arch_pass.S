/* prog_arch_pass.S -- dummy arch-test target (PASS).
 * Writes a 3-word signature to SIGBASE and PASS_MAGIC to DONE_ADDR,
 * then ends with ecall. Used to validate tb_arch's capture path.
 */
    .text
    .globl _start
_start:
    li   sp, 0x30000
    lui  t0, 0x18               # SIGBASE 0x00018000
    li   t1, 3
    sw   t1, 0(t0)              # word count
    li   t1, 0x11111111
    sw   t1, 4(t0)
    li   t1, 0x22222222
    sw   t1, 8(t0)
    li   t1, 0x33333333
    sw   t1, 12(t0)
    li   t0, 0x1FFF0            # DONE_ADDR
    li   t1, 0xDEADBEEF         # PASS_MAGIC
    sw   t1, 0(t0)
    ecall
    j .

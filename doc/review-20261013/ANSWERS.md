# Muse MCU: answers to the post-evidence questions

Date: 2026-10-13. Repository: github.com/mtmoreira/Muse-mcu, branch
`work/mcu-acceptance-v1`. All answers below are from source and log
inspection in the repo, plus the targeted reruns listed in Section 1.3.
Where a claim in the 12-page report (doc/Muse-MCU-Project-Report.pdf,
commit 3fe0285) does not survive inspection, this document says so and
Section 8 gives replacement wording.

## Status summary

| Item | Status | One-line outcome |
|---|---|---|
| 1.1 Exact revision | RESOLVED | HEAD 3fe0285, clean tree, manifest sha256 recorded below |
| 1.2 Evidence matrix | RESOLVED | Matrix in 1.2; two provenance gaps named (Mac logs not in repo; FIG2 VCD not in git) |
| 1.3 One complete final run | PARTIAL | Final-revision run in a separate clone: firmware build and E1 PASS at delivery, demo and full runner still executing (1.3); the Oct 9 and Oct 12 headlines are aggregates across revisions and are now described as such |
| 1.4 Reuse validity | RESOLVED | Dependency analysis per change set in 1.4 |
| 1.5 make acceptance vs run_tests.sh | RESOLVED | Same runner, same manifest; run_tests.sh adds provisioning checks and logging only. Fallback parser preserves every field the runner consumes |
| 1.6 ALL SELECTED vs FULL CONTRACT | RESOLVED | Runner prints RESULT: ALL PASS for the selected executable subset; six contract entries have no runner command and are never executed by it |
| 1.7 Entry classification | RESOLVED | Table in 1.7 |
| 2 B7 meaning | RESOLVED (with one caveat) | MARK semantics, error path, and coverage delta in Section 2; caveat: the wrapper FAIL path cannot complete inside the 60M window (2.5) |
| 2 B1-B6 mapping | RESOLVED | Table in 2.7 |
| 3 Application account | RESOLVED (one PARTIAL) | All questions answered from source; no second-seed D1 run exists in evidence (3.6) |
| 4 Preemption/context/faults | RESOLVED | Endpoint definitions, register list, per-fault tables in Section 4 |
| 5 Figures | RESOLVED | Timescale bug confirmed in the generator source; corrected figure generated and attached |
| 6 Synthesis/equivalence | RESOLVED | Claims narrowed to tested functional agreement; no formal equivalence exists |
| 6 F4 tool claim | RESOLVED (claim corrected) | The blanket claim is retracted: -gspecify makes upstream's specify regression pass; the generated SDF is rejected by the parser for a separate, un-isolated reason |
| 7 Provenance | RESOLVED (one PARTIAL) | Arch list, port split, interventions classification in Section 7; UART sink has no standalone qualification (7.3) |

## 1. Exact revision and the meaning of 31/31

### 1.1 Revision

- Implementation presented: commit
  `3fe0285662f909184c1524905d6db3772476976d` on branch
  `work/mcu-acceptance-v1`, working tree clean at inspection time.
- Contract: `acceptance/manifest.yaml`, version 1.0.3, status APPROVED,
  sha256 `9f9667e46a1e03f6490490f43eccf464a7d9ed9900fcf6e6ab8c5d83f32d4fcf`.
- The RTL and firmware under test did not change after the evidence
  runs: the commits after the Oct 9 verification base (99ae5ee) touch
  the runner, gate scripts, Mac setup, docs, and this report only.
  Gate E1 (tools/check_frozen.py) verifies exactly this: rtl/ tree
  clean in git, and the frozen firmware hex hashes match
  results/firmware_freeze.txt. E1 was rerun on HEAD in the final-run
  clone: PASS (bundle: finalrun_e1.log).

### 1.2 Evidence matrix (Oct 9 reference run set)

Source revision for all rows: the frozen tree verified at commit
99ae5ee (final report freeze). Firmware hashes are in
results/firmware_freeze.txt and the per-gate JSONs. "Runner cmd" is
the tools/run_acceptance.py GATES entry unless noted.

| Gate | Harness / checker | Backend and config | Evidence file |
|---|---|---|---|
| A1, A2 | tb/run_arch.sh; tools/check_arch.py vs Spike golden | Icarus 12.0; Spike (pinned source build) for goldens | results/raw/arch/ (45 .dut.sig/.spike.sig pairs) |
| A3 | tb/run_reset.sh (tb_reset, 3 variants) | Icarus 12.0 | tb/build/run_reset_s1..s3.log |
| A4 | tb/run_trap.sh | Icarus 12.0 | tb/build/run_trap.log |
| A5 | tb/run_irq.sh | Icarus 12.0 | tb/build/run_irq.log |
| A6 | tb/run_memmap.sh | Icarus 12.0 | tb/build/run_memmap.log |
| A7 | tb/run_uart_rx.sh (tb uart_source/sink) | Icarus 12.0 | results/raw/uart_rx.log |
| A8 | tb/run_spi.sh (picosoc spiflash model) | Icarus 12.0 | results/raw/spi.log |
| A9 | tb/run_a9_vlt.sh | Verilator 5.032, 50,137,799 cycles | results/a9_gate.json, results/raw/a9_verilator.log |
| B1 | tb/run_rtos_vlt.sh rtos_regtest (Icarus tb_rtos cross-check) | Verilator 5.032 | tb/build/run_rtos_rtos_regtest.log |
| B2 | rtos_queue (BlockQ/GenQTest/QPeek/PollQ) | Verilator 5.032 | tb/build/run_rtos_rtos_queue.log |
| B3 | rtos_sema (semtest/countsem/recmutex) | Verilator 5.032 | tb/build/run_rtos_rtos_sema.log |
| B4 | rtos_notify; fw sha256 d34ccb27... in b4_gate.json; +irqperiod=50000 | Verilator 5.032, ~100M cycles | results/b4_gate.json, tb/logs/run_rtos_vlt_rtos_notify.log |
| B5 | rtos_timer (TimerDemo) | Verilator 5.032 | results/b5_gate.json, results/raw/b5_verilator.log |
| B6 | rtos_isr (IntQueue/IntSemTest) | Verilator 5.032 | results/b6_gate.json, results/raw/b6_verilator.log |
| B7 | tb/run_b7_vlt.sh (MARK count >= 2, no FAIL, 60M cycles) | Verilator 5.032 | results/b7_gate.json; UART log gitignored, retained locally |
| C1 | tb/run_preempt.sh; HP range from ELF nm | Icarus 12.0 | results/raw/preempt.log |
| D1, D2 | tb/run_app.sh; tools/check_app.py (hashlib) | Icarus 12.0; seed 12345 | results/raw/demo_uart.log, results/demo_transcript.txt |
| E1 | tools/check_frozen.py (not a runner gate; run by hand) | host python3 | results/firmware_freeze.txt |
| F1 | synth/run_synth.sh | Yosys 0.33 (sha 2584903a060), Nangate45 typical (lib sha256 in JSON) | results/f1_synth.json (netlist sha256 b1c22515...) |
| F2 | tb/run_gate_app_vlt.sh; check_app.py --expect-nmsg 4 | Verilator 5.032, zero-delay; gate4 fw (FLASH_MSG_COUNT=4), seed 1; 3,297,153 cycles | results/f2_gate.json, results/raw/gate_uart.log |
| F3 | tb/run_gate_preempt_vlt.sh | Verilator 5.032, zero-delay; preempt_test.hex, HP range 0x1d60-0x1df8 | results/f3_gate.json |
| F4 | tb/run_gate_sdf.sh | Icarus 12.0 (attempted) | results/sdf_gate.json; status WITHDRAWN in v1.0.3 |
| G1 | tb/run_fault_notick.sh (FAULT_AT_TICK=100) | Icarus 12.0; fw rtos_queue.hex | results/raw/fault_notick.log |
| G2 | tb/run_g2_final.sh (Verilator harness tb_g2_final.cpp) | Verilator; fw rtos_regtest | results/raw/g2_fault_ctx.log |
| G3 | tb/run_fault_uart.sh; unmodified check_app.py on tampered log copy | host python3 | results/raw/fault_uart_tampered.log, fault_uart_check.log |
| R1 | env/bootstrap.sh (provisioning, not a runner gate) | Ubuntu 24.04 clean VM at build time | third_party/PINS.md |
| R2 | Makefile + tools/run_acceptance.py (the runner itself) | n/a | Makefile |
| DEMO1 | demo/run_demo.sh (wraps tb/run_app.sh) | Icarus 12.0 | results/demo_transcript.txt |
| FIG1 | doc/gen_arch_fig.py | host python3 | doc/fig_arch.png |
| FIG2 | doc/gen_trace_fig.py (requires the D1 VCD) | host python3 | doc/fig_trace.png; source VCD is a gitignored artifact, not in git |

Mac set (2026-10-11/12, MacBook, Apple Silicon): same harness files at
the branch head of the day; tools: Icarus 12.0 (source build),
Verilator 5.032 (source build), xpack GCC 15.2.0-1. First full run
27 PASS with B4/B7/G1/G2 FAIL (MAC_VALIDATION_REPORT.md, original
version); targeted rerun of the four after commits 630dfaf and
254a40d: all PASS, log run_20261012-230314.log on the Mac. The Mac raw
run logs are NOT committed to the repo; they exist on the owner's
MacBook and are attested by the committed report and the owner's
pasted summaries. That is a real provenance gap and is stated here
rather than papered over.

### 1.3 Was there one complete final run?

No, not before this review, and the report should not have implied
otherwise. Precisely:

- Linux: the 31 verdicts are one coherent run set from 2026-10-09 on
  the frozen tree (all gates executed within that campaign, then
  independently re-verified by the finisher pass against the cited
  files). No RTL or firmware change followed. But the verdicts were
  produced gate-by-gate by the runner plus hand-run checks for the
  six non-runner entries, not by one atomic execution of the contract.
- Mac: an aggregate by construction: 27 gates from the Oct 11 full run
  plus 4 gates rerun on Oct 12 after runner/gate-mapping changes.
- For this review, a complete final run on HEAD 3fe0285 was started
  in a separate clone (~/workspace/mcu-final-run, receipts in
  results/finalrun_20261013/ inside that clone) with the host's
  provisioned toolchains (Icarus 12.0, Yosys 0.33, xpack GCC
  15.2.0-1, Verilator 5.052 locally built; note the original B-layer
  evidence used Verilator 5.032, so this run's backend versions are
  recorded, not identical). Completed at the time of writing:
  fw/build.sh ALL OK (14 apps); E1 check_frozen PASS; FIG1
  regenerated (FIG2 regenerates after the demo recreates its VCD in
  the clone; in a fresh clone the VCD does not exist until D1 runs,
  which is itself the provenance point of 1.2). The DEMO1 run and
  the full runner were still executing when this document was
  delivered; their logs land in the same receipts directory and the
  bundle will be updated with the runner summary. Nothing in
  Sections 2-9 depends on that run's outcome: the corrected claims
  in Section 8 stand on the Oct 9/Oct 12 evidence as re-scoped
  there. If the final run surfaces a failure, it will be reported
  as a correction to this document, not silently absorbed.

### 1.4 Why reused results remain valid across the Mac-era changes

The changes after 99ae5ee, by dependency class:

- Commit 630dfaf (gate mappings): changed only the runner's command
  lines for B4/B7/G1/G2 and one script default (G1 fault tick) and
  removed a temporary debug print from rtos_notify.c, restoring the
  exact evidence firmware source (the print had been added on
  2026-10-11 for diagnosis; B4's Oct 9 evidence predates it and the
  restored file is byte-identical to the evidence version). The 27
  other gates' commands, firmware, and checkers are untouched by this
  commit, so their Mac results stand. On Linux nothing was rerun
  because nothing they depend on changed.
- Commit 254a40d (runner): --only flag (additive), verdict accounting
  for unselected/withdrawn entries (presentation of results, not pass
  criteria: a gate's PASS/FAIL still comes from its script exit code),
  and the PyYAML fallback parser (1.5). No gate script, firmware, or
  expected data changed.
- Commits cd7ee98, 638679f, 3fe0285: documentation and the GTKWave
  save file only.

The dependency that matters most is E1's: rtl/ is unchanged since the
freeze and the app firmware hashes still match the freeze record,
which is what the rerun E1 receipt shows.

### 1.5 make acceptance vs tools/run_tests.sh; the fallback parser

- `make acceptance` = `bash fw/build.sh` then `bash tools/run_tests.sh`
  with no arguments. run_tests.sh sources env/activate.sh if TOOLCHAIN
  is unset, enforces preflight (bash 4+, Icarus 12.x first on PATH),
  tees all output to results/run_<timestamp>.log, and invokes
  tools/run_acceptance.py with its arguments unchanged. One runner,
  one manifest, one GATES table: identical semantics. The only
  difference from invoking run_acceptance.py directly is provisioning
  hygiene and the saved log.
- run_acceptance.py consumes exactly four things from the manifest:
  contract_version, status, the ordered requirement ids, and each
  requirement's status field (used for WITHDRAWN). Pass criteria are
  not read from the manifest at all; they live in the gate scripts.
  The stdlib fallback parser extracts exactly those four things
  (verified 2026-10-12 with the yaml import blocked: header printed
  "Contract 1.0.3 status=APPROVED: 32 requirements", F4 reported
  WITHDRAWN, --only B7 ran and passed). It would not preserve fields
  the runner never reads (titles, pass text, timeouts); if the runner
  ever starts consuming those, the fallback must be extended. Today
  the verdict-relevant set is preserved in full.

### 1.6 ALL SELECTED GATES PASS vs FULL CONTRACT PASS

The runner's RESULT: ALL PASS means: every gate it executed in this
invocation passed, where "executed" excludes --only/--skip/--smoke
exclusions (reported SKIPPED) and F4 (WITHDRAWN). It does not mean
the full contract was executed, for two reasons: (a) a filtered
invocation is a subset by request; (b) six entries (E1, R1, R2,
DEMO1, FIG1, FIG2) have no GATES command at all and are never executed
by the runner in any mode; in a full run they report SKIPPED under
the current accounting. The Oct 12 Mac four-gate rerun therefore
establishes exactly "the four previously failing gates now pass on
the Mac", and the 31/31 Mac statement is the aggregate described in
1.3. Replacement cover wording is in Section 8.

### 1.7 Classification of the 32 entries

- Functional tests (26): A1-A9, B1-B7, C1, D1, D2, F1 (synthesis
  execution with audited output), F2, F3, G1, G2 (these two are
  functional harnesses whose verdict is a rejection; see below).
- Negative controls (3): G1, G2, G3. Their pass condition is that an
  unchanged checker rejects a corrupted run. G3 is a checker-only
  control (log-file mutation; Section 4.3).
- Reproducibility / consistency checks (3): E1 (frozen-revision
  consistency), R1 (bootstrap provisions the pinned tools), R2 (the
  one-command runner exists and drives the manifest).
- Artifact-presence checks (3): FIG1, FIG2 (a figure exists, was
  generated from the stated source, and was visually verified), and
  DEMO1 is a functional execution (the D1 workload) packaged for
  humans; it is not independent of D1 and is not counted as separate
  verification anywhere in this document.

FIG1, FIG2, R1, R2 are not functional verification and the report's
scoreboard should have separated them. Corrected in Section 8.

## 2. What each B-layer PASS establishes, especially B7

### 2.1 B7 documents

- Original manifest entry (v1.0.0, commit c72f40e): pass = ">=200
  timeout events, 0 errors, firmware prints BLOCKTIM PASS",
  min_exercises 200, timeout 60,000,000 cycles.
- Amended entry (v1.0.1, commit 99ae5ee, owner-approved 2026-10-09):
  pass = ">=2 timeout events within 60M cycles, 0 errors (no FAIL
  lines); event count from firmware MARK lines observed by
  testbench", min_exercises 2, with a change_note in the manifest
  carrying the arithmetic (48 events per 7950 ticks; 200 events need
  ~1.66B cycles vs the 60M budget; verification run measured 4;
  floor(4 x 0.7) = 2).
- Gate code: tb/run_b7_vlt.sh runs the Verilator harness with
  +timeout=60000000, captures the UART log, FAILs if the log contains
  "FAIL", otherwise PASSes when the maximum MARK blocktim value is
  >= 2.

### 2.2 What a MARK blocktim event is

Not an arbitrary progress print and not a completed upstream test
cycle. fw/app/rtos_blocktim.c's check task wakes every 50 ticks and
prints "MARK blocktim <n>", where n is the cumulative count of queue
operations that blocked and timed out, measured by the kernel trace
macros traceQUEUE_SEND_FAILED + traceQUEUE_RECEIVE_FAILED
(g_trace_qsend_fail + g_trace_qrecv_fail). Each such event is one
xQueueSend/xQueueReceive that waited its full block time and returned
errQUEUE_EMPTY/pdFALSE: precisely the behavior B7 exists to exercise.
The count the gate uses is the last (maximum) MARK value in the UART
log.

### 2.3 Where upstream errors are set and how they reach the verdict

Upstream file: third_party/freertos_demos/blocktim.c (FreeRTOS demo
V202212.00, sha256
b57805c984fe86676064f96d0ef2d755f58d2570bac34e80af5cc87258a2dfad,
byte-identical per third_party/PINS.md). Its two test tasks run Tests
0-5 (primary) and the secondary sequence: every timing or return-value
violation sets the file-scope flag, e.g. Test 1:

```c
if( xQueueReceive( xTestQueue, &xData, xTimeToBlock ) != errQUEUE_EMPTY )
    xErrorOccurred = __LINE__;
xBlockedTime = xTaskGetTickCount() - xTimeWhenBlocking;
if( xBlockedTime < xTimeToBlock )  xErrorOccurred = __LINE__;
if( xBlockedTime > ( xTimeToBlock + bktALLOWABLE_MARGIN ) )
    xErrorOccurred = __LINE__;
```

xAreBlockTimeTestTasksStillRunning() (same file) returns pdFALSE if
either task's cycle counter (xPrimaryCycles / xSecondaryCycles, each
incremented once per full test loop) has not advanced since the
previous call, OR if xErrorOccurred != pdFALSE. The wrapper's check
task calls it every 4th MARK (every 200 ticks); 12 consecutive
pdFALSE results print "TEST blocktim FAIL: demo check" and halt,
which puts "FAIL" in the UART log and fails the gate. So upstream
errors do propagate to the verdict, through the still-running check,
not through the MARK count.

### 2.4 Which scenarios actually ran in the window

60M cycles at 50,000 cycles per tick = 1200 ticks. In 1200 ticks the
primary task completes Test 0 (~900 ticks of timed blocks) and is
inside Tests 1-4 (queue-receive block-time accuracy, doubling block
times); the secondary task runs its initial sequence concurrently.
The four counted timeout events in the evidence run are failed queue
operations from those tests. The full upstream loop (all tests, both
cycle counters advancing repeatedly) does NOT complete in the window,
and the 200-event firmware PASS is unreachable in it by the arithmetic
of 2.1. What the amended gate establishes: blocking-with-timeout
operations occur repeatedly with correct return behavior in the
scenarios reached, the demo's own error flag was never set during
the window (see 2.5 for the limit of this), and neither task stalled
in the window.

### 2.5 Caveat found in this review

The wrapper's FAIL path needs 12 still-running evaluations at
200-tick spacing = 2400 ticks to fire, but the gate window is 1200
ticks. An upstream error set late in the window therefore cannot
produce "TEST blocktim FAIL" before the harness stops the run: the
run would end with a MARK count and no FAIL line, and the gate would
pass it. The Oct 9 gate JSON asserts "xErrorOccurred never set"; the
supporting observation is that both tasks kept producing timeout
events and advancing through the window (a set error flag does not
stop the counters the MARKs measure, so this is indirect). Stated
honestly: within the 60M window the gate directly proves (a) timeout
events occur, (b) no stall, (c) no FAIL printed. It does not directly
prove xErrorOccurred stayed clear for errors occurring after the
last still-running evaluation could have matured. A longer window or
a wrapper that prints xErrorOccurred state in each MARK would close
this; neither was run for this review, so the claim is scoped to
(a)-(c) plus the indirect evidence. This is a real weakening
discovered by inspection, and it is recorded here and in Section 8.

### 2.6 Why runs showed 2 and then 4 events; determinism

The Verilator harness is cycle-deterministic for a fixed firmware
binary, flash of inputs (none for B7), and configuration. The 2-event
and 4-event numbers were not two runs of one fixed configuration:
they bracket the wrapper calibration work recorded in
results/INTERVENTIONS.md (check period and stall-evaluation tuning in
fw/app/rtos_blocktim.c: BLOCKTIM_CHECK_PERIOD changed from the
upstream-style 500-tick poll to 50 ticks, stall evaluation every 4th
MARK). Different check-task periods change how often the check task
(worst-case priority) preempts and perturbs the demo tasks' timing,
which changes how many timeout operations complete inside a fixed
cycle window. The final configuration's evidence run measured 4.
Calling the 2-to-4 spread "run-to-run variation" of one configuration
was wrong; it is configuration-change variation. The manifest's
change_note wording is corrected in Section 8. Empirical check for
this review: the final configuration was run twice back to back
(2026-10-13, HEAD firmware, Verilator 5.052) and produced
byte-identical UART logs (bundle: b7_uart_run1.log,
b7_uart_run2.log): 23 MARK lines, counts rising to a maximum of 4,
PASS both times. A fixed configuration is deterministic, as expected
from a cycle-based simulator with no random inputs.

### 2.7 Coverage retained and lost (B7), and the B1-B6 mapping

Retained at the amended level: repeated blocking-with-timeout on
queues with correct wake timing in Tests 0-4 scenarios reached within
1200 ticks; both tasks live throughout; zero FAIL output. Lost: the
remaining upstream scenarios (Tests 4-5 completion, repeated full
loops of both tasks, the secondary task's later phases) and the
firmware's own 200-event PASS verdict, which the amended gate
bypasses entirely; the gate substitutes a MARK-count floor (2) that
is 1% of the original exercise count. The honest claim is: selected
timeout behavior passed at the amended exercise level (Section 8).

| Gate | Upstream (pinned, byte-identical) | Wrapper | Assertion / error source | Counter and pass logic |
|---|---|---|---|---|
| B1 | none (no upstream RISC-V regtest exists) | fw/app/rtos_regtest.c, new | vRegTestAsm fill/verify in assembly; any mismatch prints TEST regtest FAIL with register id and halts | 600 verified batches (MARK every 100); kernel ctxsw printed alongside (636 at PASS) |
| B2 | BlockQ, GenQTest, QPeek, PollQ | fw/app/rtos_queue.c | each demo's xAre...StillRunning() (own error flags) | ops = queue trace counters; TEST queue PASS at 2000 ops, 0 errors; evidence run 4168 |
| B3 | semtest, countsem, recmutex | fw/app/rtos_sema.c | xAre...StillRunning() x3 | ops = queue trace counters (sem/mutex ride queues); PASS at 1000; evidence 2376 |
| B4 | TaskNotify, TaskNotifyArray | fw/app/rtos_notify.c | demos' check logic + trace notify counters (fixed in wiring, see b4_gate.json) | ops from notify counters; PASS at >= 500 ops, 40 MARKs; evidence 514 |
| B5 | TimerDemo | fw/app/rtos_timer.c | xAreTimerDemoTasksStillRunning() | expiries = traceTIMER_EXPIRED counter; PASS at 200; evidence 209 |
| B6 | IntQueue, IntSemTest (+ template IntQueueTimer.c) | fw/app/rtos_isr.c | xAre...StillRunning() x2; ISRs are genuine MEI/tick contexts (fw ISR + tick hook) | handoffs counted by demo checks; PASS at threshold; evidence 301 |
| B7 | blocktim | fw/app/rtos_blocktim.c | xErrorOccurred (upstream) via still-running; trace fail counters | MARK = timed-out queue ops; gate: max MARK >= 2 and no FAIL in 60M cycles |

All B2-B7 wrappers follow the same pattern: unmodified upstream test
logic, a new check task that polls the demos' own still-running
functions and prints MARK/PASS/FAIL over UART. PASS lines print only
from firmware; the scripts check for the PASS line (B1-B6) or the
MARK floor plus absence of FAIL (B7 only, for the reason in 2.4).

## 3. What the application actually demonstrates

Source: fw/app/app_demo.c (new code), tools/gen_flash.py,
tools/check_app.py, tb/tb_app.sv, tb/uart_sink.sv, tb/run_app.sh.

### 3.1 What releases the acquisition task

Nothing periodic. spi_wake_flash() is a one-time SPI command (0xAB,
release from deep power-down) to the flash chip at task start; it is
not a task wakeup. The acquisition task is a straight-line loop: take
a free pool buffer (blocks on xFreeQueue when all 4 are out), read the
message header and body from flash, xQueueSend to the SHA task
(blocks when the depth-4 queue is full). Its release cadence is set
entirely by buffer and queue availability, i.e. by the consumer's
pace. The report's phrase "wakes the flash" refers to the chip, and
any reading of it as a periodic RTOS release is wrong; there is no
vTaskDelay or delay-until anywhere in the acquisition task.

### 3.2 Priorities, UART behavior, overlap

UART output is polling: uart_putc waits on the TX-ready status bit;
there is no interrupt-driven or DMA path in the demo firmware. The
SHA task (priority 3) outranks acquisition (2). On xQueueSend, the
waiting SHA task is unblocked and the send causes a reschedule before
the acquisition task's next statement, so the SHA task computes and
transmits the packet (about 82 characters at 434 cycles per bit,
roughly 356k cycles of polling transmission) while acquisition waits.
Acquisition and processing therefore do not overlap in any meaningful
way during a packet: the pipeline overlaps only across messages, in
that acquisition may read message n+1's flash data during the SHA
task's deliberate vTaskDelay(6) (6 ticks, 300k cycles) after each
packet, until it blocks on the full queue or the empty free list.
Prints from both tasks are serialized by xPrintMutex. The behavior is
a valid producer/consumer with backpressure, and it is effectively
serialized by priority plus the consumer's pacing delay; it should
not be described as parallel processing.

### 3.3 Background task execution and preemption evidence

The background task (priority 1) runs a xorshift32 loop and attempts a
non-blocking "MARK bg" print every 2000 iterations. Two independent
observations exist in the D1 testbench (tb/tb_app.sv): (a) MARK bg
count in the decoded UART stream: 60 in the evidence run (threshold
10); (b) bg_entries: the testbench counts entries of the retiring PC
(dbg_pc) into the background task's ELF function range (+bg_lo/+bg_hi
from riscv-none-elf-nm on app_demo.elf, range 0x27e8-0x2838 in the
evidence build): 180 entries (threshold 5). An entry into that range
after other code has run is a scheduling resumption of the background
task, so 180 entries plus 60 self-prints are direct evidence the task
executed repeatedly and was preempted and resumed throughout the run,
not merely created. The final PASS line format is "TB_APP: SIM PASS
(24/24 packets live-verified, watermark 4, bg 60/180)".

### 3.4 Watermark 4

It is a measured maximum, not the configured depth restated. Firmware:
after each xQueueSend, the acquisition task samples
uxQueueMessagesWaiting(xMsgQueue) and keeps the maximum in
ulQueueWatermark, which it also writes to the GPIO debug scratch
register. The testbench reads that hardware register at end of run
(dut.gpio0.scratch_q) and fails if it is below +min_watermark
(default 4): "queue watermark 4 < 4 (no queue pressure observed)" is
the failure text for the below-threshold case. The value happened to
reach the queue's full depth (4) in the evidence run, which is the
point of the check (the pipeline genuinely filled); it is a firmware
measurement observed through a peripheral register, not a testbench
constant and not read out of the kernel's queue structure.

### 3.5 Message provenance (all 24)

No application message content comes from published vectors. Per
tools/gen_flash.py (deterministic, byte-for-byte contract with the
firmware and the checker): ids 0-15 have fixed lengths
{0,1,55,56,57,63,64,65,119,120,127,128,129,255,512,1024}, the
SHA-256 padding-boundary lengths; ids 16-23 have lengths
1 + (xorshift32(seed|1) mod 300), which for seed 12345 gives
{70,290,262,96,234,5,83,211}. Every message's content bytes are the
xorshift32(seed XOR id) stream, little-endian words truncated to the
length. Published test data appears only in D2: the boot self-test's
eight NIST CAVP vectors, embedded in fw/sha256/sha_selftest.c.

### 3.6 Freeze order and seeds

Firmware first, messages second, and that order is recorded:
results/firmware_freeze.txt (2026-10-09T09:06Z, git 9f1e8e8) lists
fw/build/app_demo.elf sha256 171cc08d... and app_demo.hex sha256
a72fbb1f... with the header "Frozen BEFORE any host-side flash/message
generation. Any rebuild invalidates this record." The D1 flash image
(seed 12345, stored in the image header and read by the firmware at
runtime) was generated against that frozen binary. The firmware
validates only magic, version, and count from the header, so a
different seed needs no rebuild by design. However: no second-seed
D1 run exists in the evidence set (the F2 gate used seed 1, but with
the separate 4-message gate firmware). PARTIAL: the capability is
by construction and the header path is exercised, but a second-seed
run of the frozen D1 image was not evidenced.

### 3.7 Checker path, end to end

1. The DUT's uart_tx pin is decoded by tb/uart_sink.sv (bit period
   434 cycles, matching bauddiv) inside tb_app.sv. The testbench
   prints each decoded line live (the DEMO1 narration) and writes it
   to results/raw/demo_uart.log via +uartlog.
2. The testbench itself live-verifies: it parses PKT lines as they
   arrive and recomputes digests from the flash image it loaded
   (pkt_verified), counts MARK bg, tracks bg PC-range entries, and
   reads the watermark register at the end. A watchdog (100M cycles,
   the manifest D1 budget) fails the run if the firmware PASS line
   never arrives.
3. After simulation, tb/run_app.sh runs tools/check_app.py on the
   log file: it parses the flash image itself, requires the packet
   count to equal the message count exactly (a 25th packet fails),
   and for each index requires id, length, and hashlib SHA-256 of the
   flash payload to match. Trailing packets are enumerated as
   failures by index. Exit 0 only on full match.

So the external checker's input is the testbench-decoded log of the
simulated TX pin, not a bus probe and not firmware memory. A late
duplicate cannot escape: anything the sink decoded before the
testbench closed the log is counted, and the count check is exact;
a duplicate arriving after the firmware's PASS line is still decoded
during the testbench's drain window (100 cycles) and would break the
testbench's own pkt_verified total; after $finish, nothing is
recorded, which is the honest limit of any post-hoc log check.

### 3.8 The sha_done-before-spi_read ordering

Explained by the logging points, and the narration is not event
order for the read itself. Sequence for message 0: the acquisition
task completes the SPI reads, then xQueueSend unblocks the
higher-priority SHA task, which preempts immediately, computes the
digest, and prints "PKT ..." and "MARK sha_done 0" while holding the
print mutex. Only then does the acquisition task resume and execute
its own print block ("MARK spi_read 0 0", "MARK queue 0"). So
spi_read is logged after the send, by the lower-priority task, and
the transcript order reflects print order under priority preemption,
not the order of the SPI transfer, which necessarily preceded the
send. The same interleave is visible in the raw pin decode used for
Figure A (answers bundle, fig_data.py decode of demo_trace.vcd).

### 3.9 "Digests never in firmware", stated precisely

Application-message reference digests exist only in the host checker
(check_app.py recomputes them from the flash image; the testbench
recomputes them from its own copy of the image). The firmware
contains no expected digest for any application message. Separately
and legitimately, the D2 boot self-test embeds eight published NIST
vectors with their expected digests, because a self-test is
meaningless without them. The report's unqualified sentence conflated
the two and is corrected in Section 8.

## 4. Preemption, context, and fault evidence

### 4.1 C1: exact endpoint definitions (tb/tb_preempt.sv)

- Stimulus: the testbench pulses tb_test_irq every ~20,000 cycles and
  holds it until the trap is taken. The firmware's MEI handler gives
  a queue that the HP task (priority 3) blocks on; the LP task
  (priority 1) is a xorshift loop that never blocks or yields
  (fw/app/preempt_test.c, vLPTask).
- T0 (start): the cycle in which dbg_trap_taken is asserted with
  dbg_mcause == 0x8000000B (machine external interrupt trap actually
  taken by the core). dbg_* are DUT debug outputs of the retiring
  instruction stream.
- T1 (stop): the first later cycle with dbg_instr_valid asserted and
  dbg_pc inside the HP task's function range (+hp_lo/+hp_hi from
  riscv-none-elf-nm --print-size on preempt_test.elf; evidence build
  vHPTask = 0x1d60-0x1df8).
- Latency = T1 - T0 in cycles. It covers: trap entry completion, ISR
  prologue and queue give, kernel scheduling, context switch, and
  restore up to the first retired HP instruction. It excludes: the
  time from tb_test_irq assertion to trap taken (the current
  instruction finishing and interrupt recognition; on this
  single-cycle core that is a few cycles, but it is unmeasured and
  the bound claim does not cover it), and any masking window is
  included only insofar as the trap could not be taken while masked
  (if interrupts were masked at assertion, T0 moves later and the
  excluded interval grows; in this firmware the LP loop never masks
  interrupts).
- ISR/kernel vs task instructions are distinguished by the same PC
  classification: only cycles whose retiring PC lies in the vHPTask
  body stop the measurement; everything else (portASM trap handler,
  kernel, LP) does not. Shared kernel code is never attributed to a
  task.
- LP resumption: after each event the HP task blocks again and LP
  continues; the firmware counts events and lost wakeups, prints
  "TEST preempt PASS events=52 lost=0" at the end, and the testbench
  independently counted 52 MEI-to-HP transitions. A one-way trip
  (LP never resumed) could not produce 52 events because the pulser
  waits for each trap and the HP task only re-blocks after running.

Evidence figure Panel B (attached) shows one complete event from a
fresh capture of this same testbench and firmware (2026-10-13,
answers run): LP PCs until T0, trap-handler and kernel PCs between,
first HP PC at +427 cycles, which is also the evidence run's worst
case over 52 events.

### 4.2 B1: exactly what is checked

fw/app/rtos_regtest.c is new code (no upstream RISC-V regtest
exists). Three tasks each own a distinct 32-bit pattern. Per batch,
pure assembly: load the pattern into x5, fill x1 and x6-x31 with it,
ecall (a genuine FreeRTOS yield through the trap path, full context
save/restore), then verify every filled register still holds the
pattern. That is 28 registers checked per batch: x1, x5-x31.

- SP (x2) is not filled: it is the switch mechanism itself; a wrong
  SP crashes or corrupts the frame rather than passing silently, and
  the G2 control (4.3) proves the frame addressing is the real one.
- x3 (gp) and x4 (tp) are excluded by design and the file says why:
  the upstream port deliberately does not save/restore them
  ("assumed constant", portASM.S), so testing them would test a
  guarantee the port does not make.
- Return PC and status: mepc and mstatus are saved/restored by the
  port as part of the frame (the frame is 28 words of registers plus
  the port's trap state; see G2's sp-112 derivation). They are not
  compared value-by-value in B1; their correctness is exercised
  functionally: a corrupted return PC would divert the verify code
  itself, and the whole suite (every RTOS gate) runs on the same
  trap path. Stated plainly: B1 proves the 28 general registers
  survive; PC/status preservation is proven by continued correct
  execution and by G2's targeted corruption, not by a B1 comparison.
- Counting: the firmware counts completed batches across the three
  tasks; "MARK regtest <n>" prints every 100; PASS at 600 batches.
  The PASS line also prints the kernel's own context-switch counter
  (ctxsw=636 at PASS), which exceeds 600 because tick-driven
  block/wake switches (each task also vTaskDelay(2) between batches)
  count too. "600 switches" in the report means 600 verified
  batches, each containing at least one full save/restore; the
  precise wording is in Section 8.

### 4.3 C1 (427) vs F3 (208): different populations, same firmware

Same firmware image (preempt_test.hex), same endpoint definitions,
same 2000-cycle bound. Differences: C1 runs the RTL under Icarus and
scores 52 events (all of them; worst 427). F3 runs the synthesized
netlist under Verilator (zero-delay) and scores the first 10 events
(the gate's minimum population); worst of those 10 was 208. A maximum
over 10 samples is expected to be at or below a maximum over 52.
Nothing about synthesis improved scheduling latency; both numbers are
the same software path measured on functionally equivalent models,
and F3's claim is only "the netlist reproduces the behavior within
bound on the sampled events". The report's juxtaposition invited the
wrong inference and is annotated in Section 8.

### 4.4 Negative controls

G1 (tick stopped):
- Baseline: the same firmware (rtos_queue.hex) passes as B2 (4168
  ops). The fault harness itself also requires normal MARK progress
  before the fault point.
- Fault: at the 100th timer-tick trap entry, the testbench executes
  `force dut.clint0.irq_timer = 1'b0` (tb/tb_fault_notick.sv),
  suppressing MTI at its source inside the CLINT.
- Activation evidence: after the force point the log shows no
  further MTI trap entries and no further MARK lines; pre-fault
  progress was observed, so the stall is attributable to the force.
- Detection: the testbench watchdog fails the run when no MARK is
  seen for over 100,000 cycles (2,000 ticks at full rate; the
  baseline MARK cadence is far faster), printing "CHECKER REJECTED
  (watchdog: no MARK for >100000 cycles)" and "TB_FAULT_NOTICK: ALL
  PASS", where the gate's PASS means rejection happened.
- Checker integrity: the harness observes trap entries and UART
  MARKs architecturally; it reads no fault-enable flag (the force is
  a simulator construct on the DUT net, invisible to firmware and to
  the progress logic). Removing the force is the B2 configuration.

G2 (context corrupted):
- Baseline: rtos_regtest passes as B1 (600 batches).
- Derivation: the port's context frame is 28 words; the testbench
  (tb/run_g2_final.sh + tb/rtl_vlt/tb_g2_final.cpp) waits for the
  regtest task's ecall (cycle 239,378, pc 0x1d5c), reads the task's
  live SP (0x00010890), computes the saved-x5 slot as SP - 112 =
  0x00010820, and observes the actual store of the task's known
  pattern 0x22222222 to that address at cycle 239,381 (readback
  confirmed at 239,384).
- Injection: backdoor write of 0xdddddddd to 0x00010820, readback
  confirmed ("ACTIVE").
- First failure: when the task is restored, the corrupted x5 (the
  register the verify code uses as the expected-pattern source) makes
  the check of x6 report "TEST regtest FAIL: task 1 x6 expected
  dddddddd" at cycle 443,667, i.e. 204,283 cycles after injection,
  at the task's next verify batch. The harness requires this FAIL
  and reports the gate as PASS (rejection).
- Checker integrity: the harness gates its instrumentation behind
  the gate build (INTERVENTIONS.md, B1/G2 isolation entry) so the B1
  binary is uninstrumented; the firmware checker that fires is the
  unmodified B1 verify code.

G3 (UART stream tampered):
- What was mutated: a copy of the captured UART log file
  (results/raw/fault_uart_tampered.log): one digest nibble flipped
  and PKT 3's line duplicated, in post-processing
  (tb/run_fault_uart.sh). Nothing on any simulated wire was altered.
- Result: the unmodified tools/check_app.py rejects it: "CHECK_APP:
  FAIL (25/24 packets)" with sequence/length/digest mismatches from
  packet 4. Baseline: the untampered log passes (D1).
- Scope, stated plainly: G3 validates the host checker's sensitivity
  to count, order, and digest corruption in its input. It does not
  validate the UART hardware's response to a physical serial fault,
  and it must not be cited as a wire-level fault test. The report's
  G3 row is corrected in Section 8.

These three are representative fault-detection results on three
different checker paths (watchdog liveness, register-state verify,
host digest checker), not comprehensive fault coverage, and no such
claim is made.

## 5. Figures: diagnosis and replacement

### 5.1 The factor-of-1000, confirmed in source

doc/gen_trace_fig.py never reads the VCD $timescale. It plots raw VCD
timestamps and labels the axis "time (ns)" and the footer "Time
units: ns". The VCD's $timescale is 1 ps, so every plotted number is
picoseconds wearing a nanosecond label: the axis span 1e10 to 3e10 is
9.88 ms to 29.88 ms of simulated time (a 20.00 ms window: 1M cycles at
20 ns), not ~20 seconds. The GTKWave captions in the report (20 ms)
were correct; Figure 2's axis and footer are wrong by exactly 1000x.
The waveform shapes are unaffected; only the time labels lie.

### 5.2 PC[31:16] row

Conceded. All application code executes from the boot ROM at base 0,
so PC[31:16] is identically zero and the row can show nothing. It
demonstrates neither task activity nor preemption and should not
have been presented as a task-execution trace. The replacement
figure classifies the full 32-bit retiring PC against ELF symbol
ranges instead (with shared kernel code labelled as shared, since PC
alone cannot attribute kernel cycles to a task).

### 5.3 UART band

Conceded as presented: an undifferentiated density band with no
decoded content. The replacement decodes the actual bytes from the
TX pin (8N1, 434 cycles/bit) and prints the recovered packet text.

### 5.4 Which contract revision generated the figures

Both generators hardcode the title string "contract v1.0.0" (written
during the v1.0.0 phase). The figures were generated and gated on
2026-10-09, under contract v1.0.1. Neither v1.0.1 (B7 count) nor
v1.0.3 (F4 withdrawal) changes the architecture or the D1 workload,
so the figures' content is current; their title strings are stale
metadata. The report citing v1.0.3 alongside v1.0.0-titled figures
without explanation was sloppy; the generators' titles should carry
the manifest version read at generation time.

### 5.5 FIG1 staleness

The report's claim that the diagram "cannot drift" is too strong.
doc/gen_arch_fig.py does not parse the RTL at generation time: its
block list is a hand-maintained Python list that was derived from
rtl/*.sv and doc/architecture.md when written. What actually guards
FIG1: the FIG1 gate included a human visual verification against the
RTL (2026-10-09), and the list still matches the tree today (nine
modules in rtl/*.sv, same nine boxes; verified by inspection for
this review). If a module were added tomorrow, the figure would be
stale until someone edited the list. Corrected wording in Section 8.

### 5.6 Replacement figure (attached: fig_evidence.png / .svg)

Generated by answers/make_figure.py + fig_data.py (bundle) from
recorded data only:

- Panel A: the D1 VCD (sha256
  0b89f6e613c14feb99dafac95f9ae0a34ff722226ea2b2f2bde36f8e1deeb6a4,
  $timescale 1 ps), first 2 ms excerpt. SPI transactions decoded from
  MOSI at SCK rising edges under CS: 0xAB wake; 0x03 READ at
  0x000000 returning the 16-byte image header; 0x03 READ at 0x000010
  returning message 0's header (id 0, len 0). UART decoded from the
  TX pin: the full text of PKT 0 is printed in the figure; its digest
  is SHA-256 of the empty message (message 0 has length 0), matching
  the host checker's verdict on the full log. Excerpt status: yes,
  the first 2 ms of a 20 ms window; the full capture is preserved.
- Panel B: one complete C1 preemption event from a separate capture
  (tb_preempt run 2026-10-13 with an added $dumpvars module; same
  RTL, same firmware build inputs; the capture is labelled separate
  from Panel A in the figure). Retiring PCs classified by ELF ranges
  (nm: vLPTask 0x1c98-0x1cbc, trap handler at 0x1600, vHPTask
  0x1d60-0x1df8; everything else shown as kernel/port shared code).
  LP runs until T0 (MEI trap taken, mcause 0x8000000B), handler and
  kernel segments follow, first HP instruction at +427 cycles (this
  happens to be the worst case of the 52-event evidence run), LP/
  kernel resumption after. Time axis is cycles from T0 at 20 ns per
  cycle, derived from the VCD $timescale.
- Panel C: the B1 PASS lines and the G2 FAIL line as text excerpts,
  explicitly labelled as separate tests.

Ambiguity note, as requested: in shared kernel code the figure does
not claim which task "owns" the cycles; attribution exists only for
the task-body ranges and the trap handler. The 345 MB Panel B
capture is retained in the working area (not in git, like the D1
VCD); a downsampled excerpt can be produced on request.

## 6. Synthesis, timing, and equivalence

### 6.1 F1/F2/F3 facts

- Netlist: synth/mcu_netlist.v, sha256
  b1c22515da35b54e9c3c06f4aa6bc63682f84cfe26abe8462f2c435264bfae9c
  (results/f1_synth.json). Synthesis: synth/run_synth.sh, Yosys 0.33
  (git sha1 2584903a060) reading the NangateOpenCellLibrary typical
  liberty (sha256 8d540a4d... in the same JSON).
- Cell models for simulation: synth/nangate45_cells.v, project
  generated zero-delay functional models (synth/gen_cells.py), not
  the upstream timing models. Memories: rtl/bootrom.sv and
  rtl/sram.sv behavioral models substituted for the two black-box
  stubs; every other instance in the simulation is a mapped standard
  cell from the netlist, driven by a C++ harness (tb/gate/) that
  models the SPI flash protocol and samples uart_tx. The RTL CPU and
  peripherals are not present in the F2/F3 simulations (that is the
  point of the gates); the testbench harness differs from the Icarus
  one and is documented in tb/run_gate_app_vlt.sh's header.
- Firmware and checkers: F2 uses a separate 4-message firmware build
  (FLASH_MSG_COUNT=4, lengths 0/56/64/1024, seed 1) and the same
  tools/check_app.py with --expect-nmsg 4; result 4/4. F3 uses the
  identical preempt_test.hex as C1 and the same endpoint definitions;
  result 10/10 events, worst 208 cycles (see 4.3 for why the two
  maxima are not comparable as an improvement).
- Initialization: the verilate commands (tb/run_gate_app_vlt.sh,
  tb/run_gate_preempt_vlt.sh) pass no --x-initial or --x-assign
  options. Verilator is two-state: no X values exist in these
  simulations, and uninitialized state takes Verilator's default
  (zero unless randomized; no randomization flags were used). The
  C++ harness applies the same reset protocol as the RTL benches.
  These runs therefore provide no X-propagation evidence, and none
  is claimed for them: X/reset robustness evidence lives in the
  Icarus runs (A3 reset variants, four-state), and the report's
  architecture section already disclosed Icarus's own optimism
  limits. Verilator results must not be cited as a four-state check.
- Formal equivalence: none exists. No LEC or formal tool was run
  (no eqy/sby collateral in the repo). All "equivalence" language in
  the report is replaced by: tested functional agreement between RTL
  and netlist on the F2 workload (4 packets) and the F3 workload (10
  events) under zero-delay simulation. That is evidence, not proof,
  of equivalence.
- 50 MHz is the simulation clock setting (testbench #10 toggle,
  20 ns period; bauddiv 434 derives from it). No static timing
  analysis was run at any point; no frequency is claimed from
  synthesis. F1's JSON records max_clean_frequency_mhz: null for
  F4's flow and no STA exists elsewhere either.
- Area: 19,495.4 um2 is the Yosys-reported sum of mapped standard
  cell areas from the liberty. It excludes both black-box memory
  macros (boot ROM and SRAM contribute no area) and all physical
  implementation overhead (routing, fill, IO). It is a logic cell
  area estimate, not a die area.

### 6.2 F4: the tool claim, corrected with new evidence

The blanket sentence "Icarus 12.0 cannot simulate specify path
delays" is retracted. New experiments run for this review (bundle:
f4test/ files) on the local Icarus Verilog 12.0:

1. Upstream's own regression, ivtest/ivltests/specify4.v from the
   v12_0 tree, compiled with default flags: output DIFFERS from the
   committed gold exactly on the delayed transitions (q changes at
   the clock edge instead of 3 units later). Compiled with
   -gspecify: output MATCHES gold byte for byte.
2. The project's original minimal test (a NOT gate with
   (a => y) = 5.0): default flags, y reacts in the same instant as a
   (no delay), reproducing the Oct 9 observation; with -gspecify, y
   holds X and transitions 5 ns after the input event, i.e. the
   specify delay applies.
3. The full F4 build with -gspecify added (iverilog -g2012 -gspecify,
   upstream models + netlist + tb_gate_sdf): compiles cleanly and
   the "Omitting $sdf_annotate() since specify blocks are being
   omitted" warning is gone; $sdf_annotate executes at runtime. It
   then fails on the SDF file itself: "synth/mcu.sdf:SDF ERROR: Too
   many errors: syntax error" and "SDF ERROR: Invalid DELAYFILE
   format" reported at line 1, after which annotation is absent and
   the run proceeds unannotated. A minimal hand-written SDF in the
   same format parses on this build (it produced a scope warning,
   not a format error), so the defect is in some construct(s) of the
   168,930-line generated file; it was not isolated further in this
   review, and the $setuphold timing checks in the upstream models
   remain untested under annotation.

Accurate statement: the Oct 9 investigation tested only with default
flags, under which Icarus omits specify blocks (its own warning said
so), and generalized that into a tool incapability. The mechanism
works with -gspecify. The F4 flow as a whole still does not run: the
generated SDF is rejected by Icarus's parser for an un-isolated
reason. F4 was therefore withdrawn after an unresolved tool/model
integration failure, with the path-delay layer now understood and
the SDF-format layer still open. The withdrawal itself was and
remains an owner's scope decision, and per instruction it is not
reinstated as a gate here.

## 7. Provenance and the role of the engineer

### 7.1 The 45 architectural tests

Names (results/raw/arch/, one .dut.sig/.spike.sig pair each):
RV32I (39): I-add-00, I-addi-00, I-and-00, I-andi-00, I-auipc-00,
I-beq-00, I-bge-00, I-bgeu-00, I-blt-00, I-bltu-00, I-bne-00,
I-fence-00, I-jal-00, I-jalr-00, I-lb-00, I-lbu-00, I-lh-00, I-lhu-00,
I-lui-00, I-lw-00, I-nop-00, I-or-00, I-ori-00, I-sb-00, I-sh-00,
I-sll-00, I-slli-00, I-slt-00, I-slti-00, I-sltiu-00, I-sltu-00,
I-sra-00, I-srai-00, I-srl-00, I-srli-00, I-sub-00, I-sw-00, I-xor-00,
I-xori-00. Zicsr (6): Zicsr-csrrc-00, Zicsr-csrrci-00, Zicsr-csrrs-00,
Zicsr-csrrsi-00, Zicsr-csrrw-00, Zicsr-csrrwi-00.
Source: riscv-arch-test at the revision pinned in
third_party/PINS.md; test bodies unmodified; the adapter files are
the project's own (linker script and the macro shim in
third_party/riscv_arch_test/ plus tools/build_arch.py). Identical
ELFs and memory map feed both Spike (which writes .spike.sig via
+signature) and the DUT run (which writes .dut.sig from the same
signature region addresses): tools/run_arch.sh and
tools/check_arch.py (45/45 byte-identical in the evidence run).
Exclusions, stated plainly: this is the RV32I + Zicsr subset of the
suite only, one test instance (00) per instruction form, no M/A/C
extensions (the core implements none), no privileged-architecture
suite beyond the six CSR forms. It is not ISA certification and is
not described as such anywhere in the corrected wording.
On macOS, the committed .spike.sig files are inputs: they are tied to
the test sources and ELFs by the freeze discipline (signatures were
generated in the same Linux run set whose checker re-verified 45/45;
the Mac compares DUT output against the committed files, and E1's
hash checks cover the firmware side, not the .sig files themselves:
a stricter statement is that the .sig provenance rests on the Linux
run record in results/ACCEPTANCE_REPORT.md).

### 7.2 Port reuse vs glue, restated

Byte-identical upstream (PINS.md, per-file sha256): FreeRTOS-Kernel
V11.3.1 core files AND its portable/GCC/RISC-V port (port.c,
portASM.S, portmacro.h, portContext.h). New in fw/port/:
port_glue.S/port_glue.c (trap vector installation, external
interrupt dispatch to the firmware handler, tick setup),
freertos_risc_v_chip_specific_extensions.h, and FreeRTOSConfig.h
(including the trace macros the wrappers count with). So: the port
is upstream; the hardware binding around it is new. The PDF report's
Section 2.2 phrasing ("bound to this hardware by a newly written
port layer") is accurate; anywhere the shorter phrase "new port"
appears it should be read as this split, and the reuse table in
Section 5 of the report already lists it correctly.

### 7.3 The UART sink

tb/uart_sink.sv (and its source counterpart used in A7) are
project-written for this repo, not a third-party model. The original
architecture document (doc/architecture.md section 7) recorded the
decision at design time: "UART sink/source models: new (tb/);
protocol cross-checked vs cocotbext-uart examples." No separate
scope-change approval exists because the approved architecture
itself specifies the new models with the cross-check note. No
standalone qualification campaign for the sink exists. Its
qualification is indirect and, in this case, strong: a decoder bug
would have to produce byte-exact wrong output that still lets
check_app.py verify 24/24 SHA-256 digests computed independently in
Python (A7 additionally passes 64 known bytes in order through the
source/firmware/sink path, and the demo transcript text is human
readable and semantically consistent with the firmware source).
PARTIAL because the qualification is by end-to-end consequence, not
by an independent unit test of the sink against a reference decoder.

### 7.4 The 35 intervention entries, classified

results/INTERVENTIONS.md has 35 dated entries (the report says 36;
that count included the file's title line and is corrected). They
are a builder's log, not a log of human interventions:

- Human decisions/corrections recorded: 2 (project start and
  contract approval context; the B7 v1.0.1 owner-approved change).
  The F4 entry records an agent investigation and a BLOCKED status;
  the owner's withdrawal decision itself is in the manifest history
  (v1.0.3), and the Mac-era owner decisions (the ~/work rule, the
  push-token discipline, the order to re-investigate the ARM
  diagnosis) are in MAC_VALIDATION_REPORT.md and the project record,
  not in INTERVENTIONS.md.
- Phase/worker progress reports (agent bookkeeping): 10.
- Autonomous agent debugging (RTL, firmware, testbench, harness
  bugs found and fixed by the builders): 20.
- Environment/coordination incidents: 3 (bootstrap provisioning;
  a firmware hex overwritten by a parallel worker; one transient
  demo stall handled with a grace period).
Total: 35. Of the debugging entries, the substantive defects were:
a UART RX bug in RTL, a UART RX overrun in firmware, a testbench
reset race, two C1 event-rate mismatches, a D1 background-starvation
scheduling flaw, B1 callee-saved register bugs, and the B4/B5/B6
demo-timing investigations. None of these were human-found; the
human's recorded role was approval, scope, and process decisions.

### 7.5 Who wrote what; agents and sessions

The owner personally wrote no implementation or checker code in the
repo. He authored the commissioning brief and the architecture
requirements that became doc/architecture.md, approved the contract
and its two amendments, set the process rules (Section 7 of the
report), supplied access tokens, and ran the Mac validation commands
on his own machine, pasting outputs back. Implementation was done by
the assistant (Glitch, Muse) orchestrating worker subagents on the
Linux VM across 2026-10-08/09 (the phase structure is visible in the
intervention log's worker reports), with the Mac bring-up and the
October 12 corrections done interactively with the owner. No speedup
or autonomy claim is made: commit counts and calendar spans are not
effort measures, and the owner reviewed and gated at the contract,
amendment, and platform-validation points.

### 7.6 The ARM diagnosis incident, with its evidence chain

Original (wrong) text, MAC_VALIDATION_REPORT.md first version,
commit adfd593: the four Mac failures were attributed to an
ARM/Verilator code-generation issue, and a temporary MARK debug
print was added to the B4 firmware during that investigation
(commit 180f7fc). Owner's intervention: he directed a deeper
investigation on the grounds that the same gates had been built and
run successfully before, and asked for all four failures to be
investigated, not just the first. Corrected diagnosis, established
by diffing each Mac gate invocation against the Oct 9 evidence runs
(b4_gate.json, b7_gate.json, results/raw/fault_notick.log,
g2_fault_ctx.log): four independent wiring divergences (B4 stimulus
and timeout, B7 verdict basis, G1 fault tick, G2 harness identity),
detailed in the current MAC_VALIDATION_REPORT.md (commit cd7ee98)
and in Section 6 of the PDF report. Fix commits 630dfaf and 254a40d;
local x86 verification reproduced the evidence numbers exactly
(B4 514 ops/40 marks, B7 4 events, G1 identical finish timestamp,
G2 identical injection cycle/address/values) before the Mac rerun,
which then passed all four. This incident is unrelated to an older,
separate experiment's synthesis issue; nothing from that experiment
is evidence here, and the two are not conflated in the corrected
report.

### 7.7 Bootstrap: clean environment vs provisioned reruns

R1's clean-environment evidence is the original provisioning: the
Oct 8-9 build ran on a freshly provisioned Ubuntu 24.04 VM where
env/bootstrap.sh installed the pinned set from checksummed downloads
(Phase 0 worker report in INTERVENTIONS.md; third_party/PINS.md).
The macOS setup (env/setup.sh) ran on the owner's real, already-used
MacBook, not a clean machine. Every later suite execution, including
this review's final run, ran in an already-provisioned environment
and proves rerun reproducibility, not clean-room bootstrap. The
final-run clone for this review reused the host's installed
toolchains (it did not re-run bootstrap); that is stated in its
receipts rather than implied otherwise.

## 8. Report statements corrected, with replacement wording

1. Cover verdict. Replace "31 of 31 active contract requirements
   PASS on the Linux reference platform (2026-10-09), and 31 of 31
   again on macOS" with: "31 of 31 active requirements passed in the
   Linux verification campaign of 2026-10-09 on the frozen tree
   (gate-by-gate execution with independent re-verification; six
   entries are consistency or artifact checks, not functional
   tests). On macOS, 27 gates passed in the first full run
   (2026-10-11) and the remaining 4 in a targeted rerun after gate
   wiring fixes (2026-10-12): an aggregate across two runs and a
   runner change, not one atomic run. A single-clone full run on the
   final revision was added during the post-report review
   (Section 1.3)."
2. "No acceptance criterion was weakened" (report Sections 1, 7).
   Replace with: "Two criteria were changed with the owner's
   recorded approval: B7's exercise count was reduced from 200 to 2
   events (v1.0.1) because the original count is arithmetically
   unreachable in the contract's own cycle budget, and F4 was
   withdrawn (v1.0.3). All other criteria are as originally
   approved."
3. B7 result phrasing anywhere implying the upstream requirement
   was met. Replace with: "Selected blocking-timeout behavior
   passed at the amended exercise level: at least 2 timed-out queue
   operations within 60M cycles (4 observed), no stall, no FAIL
   output. The original 200-event requirement was not met and is
   not claimed; coverage retained and lost is itemized in the
   review answers, Section 2.7, including the caveat that the
   wrapper's stall-FAIL path cannot complete inside the 60M window
   (answers 2.5)."
4. B7 "run-to-run variation (prior run: 2, this run: 4)". Replace
   with: "The two measurements came from different wrapper
   configurations during calibration; a fixed Verilator
   configuration is cycle-deterministic."
5. Synthesis "equivalence" implications (report 2.4, 4.2). Replace
   with: "The synthesized netlist showed tested functional agreement
   with the RTL on the F2 application subset (4 packets) and the F3
   preemption subset (10 events) under zero-delay simulation. No
   formal equivalence was run."
6. F3 vs C1 numbers presented side by side without populations.
   Add: "F3's worst case (208) is over its first 10 events; C1's
   (427) is over 52 events of the same firmware. The difference is
   sample population and model, not an improvement from synthesis."
7. FIG1 "the drawing cannot drift from the source". Replace with:
   "Generated from a block list derived from the rtl/ modules and
   verified against the tree at the FIG1 gate; the generator does
   not re-parse the RTL, so future RTL additions would require a
   list update."
8. FIG2 (doc/fig_trace.png and report Figure 2). The axis and footer
   time units are wrong by 1000x (picoseconds labelled as
   nanoseconds); the PC[31:16] row carries no information; the UART
   band is undeciphered. Superseded by the corrected figure in this
   review package; the generator needs a timescale fix before any
   republication.
9. "Expected digests live only in the host checker" (report 4.3 and
   architecture summary). Replace with: "Expected digests for
   application messages exist only in the host-side verification
   (check_app.py and the testbench's independent recomputation).
   The boot self-test separately embeds eight published NIST
   vectors, as a self-test must."
10. G3 description. Add: "G3 mutates a copy of the captured UART log
    in post-processing. It validates the host checker's rejection of
    a corrupted packet stream; it is not a wire-level fault test."
11. "600 switches" for B1. Replace with: "600 verified
    fill/yield/verify batches across three tasks (x1, x5-x31 checked
    per batch); the kernel context-switch counter read 636 at the
    PASS point."
12. "36 intervention entries". Replace with 35, and do not call
    them human interventions: 2 record owner decisions; the rest
    are builder progress reports, autonomous debugging, and
    environment incidents (answers 7.4).
13. F4 root cause (MAC_VALIDATION_REPORT.md and report Section 8).
    Replace "Icarus 12.0 cannot simulate specify path delays" with:
    "Under the compile flags originally used, Icarus omits specify
    blocks (its warning states this); with -gspecify, upstream's
    specify regression passes and the project's minimal test shows
    the delays. The generated SDF is separately rejected by
    Icarus's parser for an un-isolated construct. F4 was withdrawn
    after this unresolved tool/model integration failure (answers
    6.2)."
14. Demo description "acquisition task wakes the flash" left
    ambiguous, and any phrasing suggesting parallel processing.
    Clarify per answers 3.1 and 3.2: one-time flash wake command;
    the pipeline is effectively serialized by priority and the
    consumer's pacing delay, with overlap only across messages
    during that delay.

## 9. Narrowly worded claims the evidence supports

For public use, the following are supported as written:

- "A single-cycle RV32I+Zicsr microcontroller in SystemVerilog
  (1,307 lines of RTL), with CLINT, UART, SPI, and GPIO, was built
  to a written acceptance contract approved before implementation."
- "Its instruction behavior matched the Spike ISA simulator byte
  for byte on 45 riscv-arch-test cases (39 RV32I, 6 Zicsr): a
  subset result, not ISA certification."
- "FreeRTOS (kernel and RISC-V port byte-identical upstream) ran
  seven workload groups on the core with zero errors at the
  exercise levels the contract specifies; one workload's exercise
  count was reduced by an owner-approved amendment whose
  arithmetic is published in the contract."
- "A three-task application read 24 generated messages from SPI
  flash, hashed them with SHA-256 under FreeRTOS, and reported
  digests over UART; an independent Python checker verified every
  packet's id, length, and digest against the flash image."
- "Worst measured preemption latency was 427 cycles against a
  2000-cycle bound over 52 events, measured from interrupt trap
  entry to the first retired instruction of the unblocked task."
- "The design synthesized to 11,858 Nangate45 cells (19,495 um2 of
  mapped logic cell area, memories excluded), and the netlist
  reproduced the application subset and preemption behavior in
  zero-delay simulation. No formal equivalence or timing signoff
  was performed."
- "Three fault-injection controls (stopped tick, corrupted saved
  register, corrupted packet stream in the checker input) were all
  detected by the unchanged checkers."
- "The full suite was executed on two platforms (Linux x86-64 and
  macOS on Apple Silicon), the Mac result being an aggregate of a
  full run and a targeted rerun after gate-wiring fixes."
- "The human's role was requirements, contract approval and
  amendments, scope and process decisions, and platform
  validation; implementation and first-line debugging were done by
  AI agents, whose 35-entry work log is published in the repo."

## 10. Evidence bundle (attached with this document)

- ANSWERS.md (this file)
- fig_evidence.png / fig_evidence.svg (corrected figure, Section 5.6)
- make_figure.py, fig_data.py (figure generation; runnable against
  the repo VCD)
- bundle/f4test/: specify4.v, specify4.gold, spec4.out (default
  flags), spec4s.out (-gspecify, matches gold), nottest.v
- bundle/f4_compile.log (full F4 build with -gspecify: clean),
  bundle/f4run.log ($sdf_annotate executes; SDF parser errors)
- bundle/b7_uart_run1.log, bundle/b7_uart_run2.log (B7 determinism
  check, Section 2.6: byte-identical)
- bundle/finalrun receipts: e1_check_frozen.log and fw build result
  from the final-revision clone; demo and runner logs follow in the
  same receipts directory when the run completes (Section 1.3)
- Repository files cited throughout are at commit 3fe0285 on
  work/mcu-acceptance-v1: acceptance/manifest.yaml (sha256 in 1.1),
  tools/run_acceptance.py, tools/run_tests.sh, fw/app/*.c,
  tools/check_app.py, tb/tb_app.sv, tb/tb_preempt.sv,
  results/*_gate.json, results/f1_synth.json, results/sdf_gate.json,
  results/firmware_freeze.txt, results/INTERVENTIONS.md,
  third_party/PINS.md.

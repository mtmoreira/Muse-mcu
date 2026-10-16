# Muse MCU visual demo: Sobel edge detection under FreeRTOS

A 64x64 grayscale image travels the full path: SPI flash, MCU SRAM,
two FreeRTOS gradient workers, a combining task, an SRAM output
framebuffer, and back out over UART, where a host checker compares
it against an independent OpenCV reference. A second run repeats the
path with a single-bit fault injected into one SRAM write.

Spec: `Muse_MCU_Visual_Demo_Requirements.md` v1.0 (2026-10-13).
This demo is a separate application target (`fw/app/image_demo.c`);
it does not change or close any item of the acceptance suite.

## Commands

```bash
./demo/image/demo.sh setup
./demo/image/demo.sh reproduce
./demo/image/demo.sh walk --run <run-id>
./demo/image/demo.sh walk --run <run-id>            # fault run too
./demo/image/demo.sh show --run <run-id> --stage 06
./demo/image/demo.sh verify --run <run-id>          # exits nonzero for the fault run
./demo/image/demo.sh negative-control --run <run-id>
./demo/image/demo.sh render-video --baseline <run-id> --fault <run-id>   # after owner review
```

`reproduce` builds the firmware once (freeze record in
`runs/FREEZE-<ts>.txt` with ELF/hex/source hashes and the git HEAD),
generates the main input, runs baseline and fault, then generates a
second, distinct input AFTER the freeze and runs it through the same
binary (GEN1). Each run lands in its own `runs/<id>/` directory and
nothing overwrites a previous review's evidence.

`reproduce` enforces the functional outcomes before it builds any
walkthrough assets. `run_one` records each run's checker exit code
in `checker_exit.txt`, and the reproduce flow gates on it: a
baseline or extra run whose functional checker fails stops
reproduce with a nonzero exit. The fault run must satisfy the
opposite requirement plus confirmation: the checker must have
rejected it, and the negative-control wrapper must confirm the
detection (packet integrity MATCH, image reference MISMATCH,
detection CONFIRMED); a fault run the checker passes, or one the
negative control cannot confirm, also stops reproduce. The
remaining acceptance items in the table below are computed from
the recorded run artifacts by `make_index.py` at the end of a
successful reproduce; the runner does not gate on them
individually.

`walk`/`show` use captured evidence only; they do not rerun the
simulation. `verify` reruns the unchanged functional checker.
`negative-control` is the experiment wrapper: it succeeds only when
the injection record and the checker's rejection are both present.

## Task and data flow

| Task | Priority | Role |
|---|---|---|
| ImageIO | 1 | Read + validate the MIMG header, load pixels via SPI into `img_in`, release both workers, block for the completed frame, export header + framebuffer + SHA-256 over UART |
| GradientX | 2 | Sobel Gx per stripe into `img_gx` (int16), publish stripe IDs on a depth-2 queue |
| GradientY | 2 | Sobel Gy per stripe into `img_gy`, publish on its own queue |
| Combine | 3 | For each stripe wait for BOTH IDs, write `img_out` = min(255, \|Gx\|+\|Gy\|) for all 256 pixels of the stripe, notify ImageIO after stripe 15 |

16 stripes of 4 rows. A stripe ID is published only after that
stripe's gradient writes complete. Input is immutable after loading;
both workers block on start semaphores; Combine blocks on the
queues; ImageIO blocks on the frame-done semaphore. No busy-wait
synchronization. Gx and Gy are independent over the same input;
Combine depends on both; on this single core the tasks interleave
(no multicore speedup is claimed or measured).

Configuration (recorded, `fw/freertos/FreeRTOSConfig.h`): 1 kHz
tick, preemptive scheduling on, time slicing at the kernel default
(the macro is not overridden), `configMAX_PRIORITIES` 5.

Diagnostics never touch the UART (reserved for the packet). Tasks
write trace codes to the GPIO debug scratch register (0x1000 load
begin, 0x1001 load done, 0x2000|s / 0x3000|s gradient stripe
published, 0x4000|s combine stripe written, 0x5000 frame complete,
0x6000/0x6001 export begin/end); the testbench logs them with cycle
stamps in `events.csv`.

Buffers (dedicated, non-overlapping, addresses resolved from the
ELF at run time into `symbols.json`): `img_in` 4096 B, `img_gx`
8192 B, `img_gy` 8192 B, `img_out` 4096 B, 24 KiB of the 128 KiB
SRAM.

## Verification (independent, spec Section 3)

- Reference: OpenCV (pinned 4.11.0 in the demo venv) `cv2.Sobel`,
  CV_16S, ksize 3, scale 1, delta 0, BORDER_CONSTANT, outer frame
  zeroed, widen, clamp. The adapter is qualified against
  hand-computed constant/step/impulse patterns
  (`tools/ref_sobel.py qualify`: ALL PASS).
- `tools/check_image.py` (fault-blind) compares separately: SPI
  payload decoded from the stage02 VCD vs the canonical pixels;
  committed input/Gx/Gy/output SRAM writes reconstructed from
  `writes.csv` vs input and reference; the pin-decoded UART packet
  (header fields, SHA-256 over received bytes, payload vs the stored
  framebuffer); UART payload vs reference; trace ordering
  (dependencies); tb protocol verdict.
- End boundary: the packet is 4148 bytes; after the final digest
  byte's stop bit the testbench observes 50,000 further cycles and
  any extra byte fails the run. Watchdog 100,000,000 cycles.

## Fault experiment (spec Section 4)

Testbench-only, armed for the writeback phase: on the committed
write of output byte offset 2080 (pixel 32,32), the SRAM data lane
is forced to intended XOR 0x80, once. Expected and observed: input
and gradients match baseline; exactly one output pixel differs; the
UART payload carries the corrupted stored byte; the packet digest
still matches its (corrupted) contents; the unchanged image
comparison rejects. Reported as three separate verdicts: packet
integrity MATCH, image reference MISMATCH, negative-control
detection CONFIRMED. The faulty application itself is FAIL, never
PASS.

## Results (recorded reproduce, 2026-10-13 to 2026-10-15)

Recorded runs: `baseline-20261013-222600`,
`fault-20261013-222600-r4`, `extra-20261013-222600`, all under the
single freeze in `runs/FREEZE-20261013-222600.txt` (ELF sha256
fee1d28b...). `runs/index.html` holds the per-requirement table read
live from the artifacts: APP1-APP5, NEG1, NEG2, GEN1, VIEW1,
REPRO1, REVIEW1, all MET. Each run's `results.json` carries the
per-observation verdicts; the fault run's three negative-control
verdicts are in its `negative_control.log`. The recovery note
`runs/RECOVERY-20261014.txt` documents the aborted attempts
(environment process losses and two testbench/tooling defects,
all preserved on disk) that preceded the final runs. Measured
reproduction time: each full simulation is 20.56M cycles and takes
about 35 minutes wall on the 2-core VM used here (Icarus, roughly
10k cycles/s); the three runs with checking, assets and views
total about 1 hour 50 minutes of compute.

## Resource use and limits

- Firmware text and buffers: see the freeze record and
  `fw/build/image_demo.elf` (nm/size output is in the run logs).
- Simulation cost: measured per run in `runs/*/tb_console.log`
  (wall time) and `tb_result.json` (cycles). The UART packet alone
  is 4148 bytes at 4340 cycles per byte, about 18.0M cycles.
- No timing signoff, no formal equivalence, no claim beyond this
  workload: APP4 is not proof of complete RTOS correctness.
- GTKWave views: per-stage `.tcl` launchers and `.gtkw` save files
  ship with both walkthrough runs; the save files were generated
  with GTKWave 3.3.116 and validated opening on Linux. Named
  markers are applied by the `.tcl` launchers at open time: this
  GTKWave build does not persist Tcl-set named markers into
  `.gtkw` files (verified empirically; the save file's marker
  slots stay unset), so open stages via `demo.sh show` or the
  `.tcl` files to get the markers. Mac launch path exercised
  2026-10-15: the owner's Homebrew GTKWave 3.4.0 opens the
  committed views correctly (groups, signals, zoom window), but
  that build has no Tcl support ("Tcl support not compiled into
  gtkwave"), so it cannot run the `.tcl` launchers or generate
  save files itself. On such a machine `make_gtkw.py` falls back
  to templating each `.gtkw` from a sibling run's GTKWave-written
  view, rewriting only the file references; the view content is
  identical because the runs are deterministic (the templated
  files were verified to open).
- The combined stage02 load-window trace (about 123 MB per run)
  exceeds GitHub's 100 MB file limit and is not committed; it is
  retained in the working tree under each run directory and is
  bit-reproducible from `demo.sh reproduce` (the simulations are
  deterministic: identical cycle counts across independent runs).
  The stage 03-07 slice traces are committed.

## Video

Rendered after the owner's review (completed 2026-10-15) from the
two reviewed runs, and only from those runs:

- baseline: `runs/baseline-20261013-222600`
- fault: `runs/fault-20261013-222600-r4`

Render command:

```bash
./demo/image/demo.sh render-video --baseline baseline-20261013-222600 --fault fault-20261013-222600-r4
```

This runs `tools/render_video.py`, which composes every frame from
the run artifacts (writes.csv, stage VCD slices, stage assets,
results.json, tb_result.json, anchors.json) and encodes with
ffmpeg. Outputs land in `demo/image/video/`:

- `Muse_MCU_Visual_Demo.mp4`: 1080x1350 portrait, H.264, 30 fps,
  77 s, silent, with burned-in captions. After the hook it adds
  three scenes to the original storyboard: the designed circuit
  (core, SRAM, SPI0, UART0, GPIO, CLINT on one bus), the software
  stack (application tasks, FreeRTOS kernel, drivers, hardware),
  and, before the closing verdicts, the methodology (contract
  first, independent implementations, byte-exact comparison of
  raw evidence, negative control).
- `Muse_MCU_Visual_Demo_VO.mp4`: the narrated edition, same
  frames plus a voice-over (ElevenLabs voice "Will") synthesized
  per storyboard segment and fitted to each window.
  Script: `narration.txt`. It is labeled throughout
  as a replay of recorded RTL simulation; waveform scenes carry
  simulation cycle references and note where time is compressed
  or cycles are omitted.
- `captions.srt`: the same caption text and timecodes as the
  burned-in captions.
- `cover.png`: 1080x1350 cover image (title, input image, edge
  output).
- `qa/`: one extracted frame per storyboard segment, used to
  check readability and layout after rendering.

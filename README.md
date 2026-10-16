# Muse MCU

An acceptance-driven RV32I + Zicsr single-cycle MCU with a FreeRTOS
application stack, built and verified against a written contract
(`acceptance/manifest.yaml`, v1.0.3). Every requirement in the
contract maps to a gate that produces its own evidence under
`results/`; nothing is declared passing on a summary line.

Final contract result: **31 of 31 active requirements PASS** on
Linux (2026-10-09) and revalidated 31 of 31 on macOS (2026-10-12).
One requirement (F4, SDF timing simulation) was withdrawn by the
project owner and is recorded as withdrawn in the manifest, not
counted as a pass. Status tracker: `results/ACCEPTANCE_STATUS.md`.
Full report: `results/ACCEPTANCE_REPORT.md` and
`doc/Muse-MCU-Project-Report.pdf`.

## Layout

| Path | Contents |
|---|---|
| `rtl/` | MCU RTL (core, SoC, peripherals) |
| `fw/` | Firmware: FreeRTOS port, drivers, applications (`fw/app/`) |
| `tb/` | Testbenches |
| `acceptance/` | The contract: `manifest.yaml` |
| `tools/` | Gate runners and checkers (`tools/run_tests.sh`) |
| `env/` | Environment setup (`setup.sh`, pinned versions in `VERSIONS.md`) |
| `results/` | Acceptance report, status tracker, per-gate evidence |
| `demo/` | Human-watchable demos (see below) |
| `doc/` | Architecture notes, Mac setup guide, project report PDF |

## Setup

One script installs and verifies every dependency (RISC-V GCC
toolchain, Verilator, Icarus Verilog, GTKWave, Spike, Python
packages). It is idempotent and safe to re-run:

```bash
bash env/setup.sh
```

Supported hosts: macOS (arm64 and x64) and Ubuntu 24.04. Pinned
tool versions are listed in `env/VERSIONS.md`; macOS-specific
notes, including the Gatekeeper fix for locally built tools, are
in `doc/MAC_SETUP.md`. No paths are hardcoded: the suite locates
its tools from the environment the setup script prepares.

## Validation

```bash
make acceptance   # builds firmware, then runs every mandatory gate
make smoke        # the labeled fast subset
```

`make acceptance` exits nonzero on any failure or incomplete
gate. Results land in `results/` (start with
`results/ACCEPTANCE_STATUS.md` for the per-requirement verdicts
and their evidence pointers). A fresh clone plus `make
acceptance` is the complete reproduction path for the contract
result.

## Demos

### Console demo (DEMO1)

A human-watchable end-to-end application run with a narrated
console feed and an independent packet checker:

```bash
bash demo/run_demo.sh
```

Transcript: `results/demo_transcript.txt`.

### Image-processing visual demo

A separate FreeRTOS application (`fw/app/image_demo.c`) loads a
64x64 image from simulated SPI flash, computes Sobel gradients
with two worker tasks, combines them in a third task, and
exports the result over UART with a SHA-256 digest. The demo
package adds per-stage waveform views, an independent OpenCV
reference checker, a testbench-only fault-injection run as a
negative control, and a 55 second video rendered after owner
review. Its own acceptance list is 11 items, all MET on Linux
and macOS.

```bash
cd demo/image
./demo.sh setup                 # Python environment for the tools
./demo.sh reproduce             # baseline, fault and extra-image runs
./demo.sh walk --run <run-id>   # guided stage-by-stage tour (needs a display)
./demo.sh verify --run <run-id> # re-run the checker on a recorded run
./demo.sh negative-control --run <fault-run-id>
./demo.sh render-video --baseline <run-id> --fault <run-id>
```

Full instructions, the run records, and the acceptance table:
`demo/image/README.md`. Recorded runs live in `demo/image/runs/`
(start at `demo/image/runs/index.html`); the video and its
captions are in `demo/image/video/`.

## Branch note

This work lives on `work/mcu-acceptance-v1`. The default branch
is untouched.

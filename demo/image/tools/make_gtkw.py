#!/usr/bin/env python3
"""Generate per-stage GTKWave Tcl launchers + .gtkw save files.

For each run and stage with a VCD: a stageNN.tcl that adds the
stage's signals (friendly grouping via trace comments), sets the
zoom to the anchor window, and places named markers at the anchor
events. The .gtkw is produced by running GTKWave headless with that
Tcl plus a save step when GTKWave is available; otherwise only the
Tcl launcher is shipped (spec allows tested Tcl launchers).
"""
import argparse
import json
import os
import shutil
import subprocess

SIGNALS = {
    "default": [
        ("SPI", ["tb_image.dut.spi_cs_n", "tb_image.dut.spi_sck",
                 "tb_image.dut.spi_mosi", "tb_image.dut.spi_miso"]),
        ("SRAM writes", ["tb_image.dut.ram.d_wstrb",
                         "tb_image.dut.ram.d_waddr",
                         "tb_image.dut.ram.d_wdata"]),
        ("UART + trace", ["tb_image.dut.uart_tx",
                          "tb_image.dut.gpio0.scratch_q"]),
        ("Core", ["tb_image.dut.dbg_pc", "tb_image.dut.dbg_trap_taken",
                  "tb_image.dut.dbg_mcause"]),
    ],
    "05": [
        ("Core", ["tb_image.dut.dbg_pc", "tb_image.dut.dbg_trap_taken",
                  "tb_image.dut.dbg_mcause"]),
        ("Trace (task events)", ["tb_image.dut.gpio0.scratch_q"]),
        ("Pins (idle)", ["tb_image.dut.spi_cs_n", "tb_image.dut.uart_tx"]),
    ],
    "07": [
        ("UART", ["tb_image.dut.uart_tx"]),
        ("Trace (task events)", ["tb_image.dut.gpio0.scratch_q"]),
    ],
}


def tcl_for(run_dir, stage, st):
    groups = SIGNALS.get(stage, SIGNALS["default"])
    lines = []
    for gname, sigs in groups:
        lines.append(f"gtkwave::addCommentTracesFromList {{{gname}}}")
        flat = " ".join(sigs)
        lines.append(f"gtkwave::addSignalsFromList {{{flat}}}")
    t0 = st.get("t0_ns") or 0
    t1 = st.get("t1_ns") or 0
    if t1 > t0:
        lines.append(f"gtkwave::setZoomRangeTimes {t0} {t1}")
    start_cycle = {"02": 0}.get(stage)
    ev_lines = []
    for e in st.get("events", []):
        c = e.get("cycle")
        if c is None:
            continue
        # VCD time for stages whose file starts at a known cycle 0;
        # sliced/offset files: anchors store file-relative windows and
        # event times are computed from the stage's own start event.
        ev_lines.append((c, e["name"]))
    return "\n".join(lines) + "\n", ev_lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    args = ap.parse_args()
    rd = args.run_dir
    anchors = json.load(open(os.path.join(rd, "anchors.json")))
    have_gtk = subprocess.run(["which", "gtkwave"], capture_output=True,
                              text=True).stdout.strip()
    start_cycle = {}
    ev = {}
    with open(os.path.join(rd, "events.csv")) as f:
        next(f)
        for line in f:
            c, v = line.strip().split(",")
            ev.setdefault(int(v, 16), int(c))
    # Stage03's slice starts 25 cycles before the row-32 CS fall
    # (make_assets' win0_cyc), not at cycle 0.
    tb_p = os.path.join(rd, "tb_result.json")
    base03 = 0
    if os.path.exists(tb_p):
        with open(tb_p) as f:
            base03 = max(0, json.load(f)["cs35_start_cycle"] - 25)
    start_cycle = {"02": 0, "03": base03, "05": ev.get(0x1001, 0),
                   "06": ev.get(0x4007, 0), "04": ev.get(0x4007, 0),
                   "07": None}
    for stage, st in sorted(anchors["stages"].items()):
        vcd = st.get("vcd")
        if not vcd:
            continue
        tcl, _ = tcl_for(rd, stage, st)
        # markers: file-relative times
        base = start_cycle.get(stage)
        mk = []
        for e in st.get("events", []):
            c = e.get("cycle")
            if c is None or base is None:
                continue
            t = (c - base) * 20
            if t >= 0:
                name = e["name"].replace('"', "'")[:48]
                mk.append(f'gtkwave::setNamedMarker {t} "{name}"')
        # GTKWave 3.3.116 does not persist Tcl-set named markers into
        # .gtkw save files (verified empirically: the save file's
        # marker slots stay -1). The markers therefore live in these
        # .tcl launchers, applied at open time; also drop the primary
        # marker on the first event so it is visibly placed.
        if mk:
            t0 = mk[0].split()[1]
            mk.insert(0, f"gtkwave::setMarker {t0}")
        tcl = tcl + "\n".join(mk) + "\n"
        tcl_path = os.path.join(rd, f"stage{stage}.tcl")
        with open(tcl_path, "w") as f:
            f.write(tcl)
        gtkw_path = os.path.join(rd, f"stage{stage}.gtkw")
        saved = False
        if have_gtk:
            save_tcl = tcl_path + ".save.tcl"
            with open(save_tcl, "w") as f:
                f.write(tcl)
                # GTKWave 3.3.116 Tcl API: saveFile/exit do not exist;
                # the menu-path commands below are the working ones
                # (verified headless on this build).
                f.write("gtkwave::/File/Write_Save_File_As "
                        f'"{os.path.abspath(gtkw_path)}"\n')
                f.write("gtkwave::/File/Quit\n")
            if not os.environ.get("GTKW_NO_TCL"):
                # xvfb-run exists only on headless Linux; macOS and
                # any desktop session run gtkwave directly.
                cmd = ((["xvfb-run", "-a"] if shutil.which("xvfb-run")
                        else []) + ["gtkwave", os.path.join(rd, vcd),
                                    "-S", save_tcl])
                try:
                    r = subprocess.run(
                        cmd, capture_output=True, text=True,
                        timeout=1200)
                    if os.path.exists(gtkw_path):
                        saved = True
                        print(f"gtkw {stage}: saved view written")
                    else:
                        tail = (r.stderr or "").strip().splitlines()
                        print(f"gtkw {stage}: gtkwave save failed "
                              f"({r.returncode})"
                              + (f": {tail[-1]}" if tail else ""))
                except subprocess.TimeoutExpired:
                    print(f"gtkw {stage}: gtkwave timed out (1200 s) "
                          f"loading {vcd}")
            os.remove(save_tcl)
        if not saved:
            # Tcl-less GTKWave builds (e.g. Homebrew macOS 3.4.0:
            # "Tcl support not compiled into gtkwave") cannot run
            # the save script at all, and .gtkw files carry no
            # markers anyway (see above). The view definition is
            # identical for every deterministic run of a stage,
            # so template it from a sibling run's GTKWave-written
            # .gtkw, rewriting only the file references.
            if template_view(rd, stage, vcd, gtkw_path):
                print(f"gtkw {stage}: view templated from a "
                      f"sibling run (Tcl-less GTKWave)")
            else:
                print(f"gtkw {stage}: Tcl launcher only "
                      f"(no saved view available)")
    return 0


def template_view(rd, stage, vcd, gtkw_path):
    """Copy a sibling run's stageNN.gtkw, rewriting [dumpfile],
    [dumpfile_mtime], [dumpfile_size] and [savefile] for this run.
    Only used when the template's trace basename matches this
    stage's, so the view content (signals, groups, zoom) is the
    one GTKWave itself produced for an identical deterministic
    run. Returns True on success."""
    import glob
    import time
    runs_dir = os.path.dirname(os.path.abspath(rd))
    vcd_abs = os.path.join(rd, vcd)
    for cand in sorted(glob.glob(os.path.join(
            runs_dir, "*", f"stage{stage}.gtkw"))):
        if os.path.abspath(cand) == os.path.abspath(gtkw_path):
            continue
        try:
            lines = open(cand).read().splitlines()
        except OSError:
            continue
        dump = next((ln for ln in lines
                     if ln.startswith("[dumpfile]")), "")
        if os.path.basename(vcd) not in dump:
            continue
        st = os.stat(vcd_abs)
        out = []
        for ln in lines:
            if ln.startswith("[dumpfile]"):
                out.append(f'[dumpfile] "{vcd_abs}"')
            elif ln.startswith("[dumpfile_mtime]"):
                out.append(f'[dumpfile_mtime] '
                           f'"{time.ctime(st.st_mtime)}"')
            elif ln.startswith("[dumpfile_size]"):
                out.append(f"[dumpfile_size] {st.st_size}")
            elif ln.startswith("[savefile]"):
                out.append(f'[savefile] '
                           f'"{os.path.abspath(gtkw_path)}"')
            else:
                out.append(ln)
        with open(gtkw_path, "w") as f:
            f.write("\n".join(out) + "\n")
        return True
    return False


if __name__ == "__main__":
    raise SystemExit(main())

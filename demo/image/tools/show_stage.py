#!/usr/bin/env python3
"""Open one walkthrough stage: validate anchors/evidence, print the
narration, open the stage image and the waveform view.

Errors are explicit: missing anchors, missing stage VCD, or stale
evidence hashes abort with a clear message (spec Section 5).
"""
import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys


def sha256f(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def opener(path):
    system = platform.system()
    try:
        if system == "Darwin":
            subprocess.Popen(["open", path])
        elif os.environ.get("DISPLAY"):
            subprocess.Popen(["xdg-open", path])
        else:
            print(f"  (headless: open it manually) {path}")
            return
        print(f"  opened: {path}")
    except Exception as e:  # noqa: BLE001
        print(f"  (could not open automatically: {e}) {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--here", required=True)
    ap.add_argument("--run", required=True)
    ap.add_argument("--stage", required=True)
    args = ap.parse_args()
    rd = os.path.join(args.here, "runs", args.run)
    anchors_p = os.path.join(rd, "anchors.json")
    if not os.path.exists(anchors_p):
        print(f"ERROR: no anchors.json for run {args.run} (was reproduce run?)")
        return 2
    anchors = json.load(open(anchors_p))
    stage = anchors["stages"].get(args.stage)
    if stage is None:
        print(f"ERROR: stage {args.stage} has no anchor in {args.run}")
        return 2
    # stale-hash guard ("flash_bin" is a logical name: its path lives
    # in the run's meta.json, not in the run directory)
    meta = {}
    meta_p = os.path.join(rd, "meta.json")
    if os.path.exists(meta_p):
        meta = json.load(open(meta_p))
    for name, h in anchors.get("evidence_hashes", {}).items():
        p = meta.get("flash_bin") if name == "flash_bin" \
            else os.path.join(rd, name)
        if not os.path.exists(p) or sha256f(p) != h:
            print(f"ERROR: evidence {name} is missing or changed since "
                  f"the assets were built; refusing to present stale data")
            return 2
    texts = json.load(open(os.path.join(args.here, "tools",
                                        "stage_texts.json")))
    t = texts[args.stage]
    print(f"\n=== Stage {args.stage}: {t['title']}  (run {args.run}, "
          f"{anchors['kind']}) ===")
    print(f"Inspecting: {t['inspect']}")
    print(f"Artifact:   {t['artifact']}")
    print(f"Look for:   {t['look']}")
    print(f"Establishes: {t['establishes']}")
    for e in stage.get("events", []):
        print(f"  event: {e}")
    img = os.path.join(rd, stage["image"]) if stage.get("image") else None
    if img:
        opener(img)
    vcd = stage.get("vcd")
    if vcd:
        vpath = os.path.join(rd, vcd)
        if not os.path.exists(vpath):
            print(f"ERROR: stage VCD missing: {vpath}")
            return 2
        gtkw = os.path.join(rd, f"stage{args.stage}.gtkw")
        tcl = os.path.join(rd, f"stage{args.stage}.tcl")
        print(f"  waveform: {vpath}")
        print(f"  zoom: t0={stage.get('t0_ns')} ns t1={stage.get('t1_ns')} ns "
              f"(VCD time base)")
        if os.path.exists(gtkw):
            print(f"  saved view: {gtkw}")
            opener_gtk = ["gtkwave", vpath, gtkw]
        elif os.path.exists(tcl):
            opener_gtk = ["gtkwave", vpath, "-S", tcl]
        else:
            opener_gtk = ["gtkwave", vpath]
        if platform.system() == "Darwin" or os.environ.get("DISPLAY"):
            try:
                subprocess.Popen(opener_gtk)
                print(f"  launched: {' '.join(opener_gtk)}")
            except Exception as e:  # noqa: BLE001
                print(f"  (gtkwave launch failed: {e}; open the VCD manually)")
        else:
            print(f"  (headless: launch with) {' '.join(opener_gtk)}")
    if args.stage == "08" and os.path.exists(os.path.join(rd, "assets",
                                                           "stage08_crop.png")):
        opener(os.path.join(rd, "assets", "stage08_crop.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Independent reference for the image demo, per spec Section 3.1.

Uses OpenCV (pinned, see setup record) cv2.Sobel:
  CV_16S, ksize=3, scale=1, delta=0, BORDER_CONSTANT.
The outermost derivative borders are then set to zero (the firmware
does the same). Output = min(255, |Gx| + |Gy|) computed after
widening to int32.

Modes:
  compute --raw IN.raw --outdir DIR
      writes gx.npy, gy.npy (int16), ref_out.raw, ref_out.png,
      ref.json (versions + hashes)
  qualify
      hand-checkable constant / step-edge / impulse patterns run
      through the same adapter path and asserted against values
      computed by hand from the Section 2.2 formulas.
"""
import argparse
import hashlib
import json
import os

import cv2
import numpy as np

SPEC = {
    "function": "cv2.Sobel",
    "ddepth": "CV_16S",
    "ksize": 3,
    "scale": 1,
    "delta": 0,
    "borderType": "BORDER_CONSTANT",
    "post": "zero outermost 1px frame of Gx/Gy; widen int32; "
            "out = min(255, |Gx| + |Gy|) as uint8",
}


def sobel_adapter(img_u8):
    """The one path used for both qualification and reference output."""
    gx = cv2.Sobel(img_u8, cv2.CV_16S, 1, 0, ksize=3, scale=1, delta=0,
                   borderType=cv2.BORDER_CONSTANT)
    gy = cv2.Sobel(img_u8, cv2.CV_16S, 0, 1, ksize=3, scale=1, delta=0,
                   borderType=cv2.BORDER_CONSTANT)
    for g in (gx, gy):  # zero the outermost frame, per spec
        g[0, :] = 0
        g[-1, :] = 0
        g[:, 0] = 0
        g[:, -1] = 0
    out = np.minimum(
        255, np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32))
    ).astype(np.uint8)
    return gx.astype(np.int16), gy.astype(np.int16), out


def formula_at(img, x, y):
    """Section 2.2 formulas evaluated directly (for hand checks)."""
    I = lambda xx, yy: int(img[yy, xx])
    gx = (-I(x-1, y-1) + I(x+1, y-1) - 2*I(x-1, y) + 2*I(x+1, y)
          - I(x-1, y+1) + I(x+1, y+1))
    gy = (-I(x-1, y-1) - 2*I(x, y-1) - I(x+1, y-1)
          + I(x-1, y+1) + 2*I(x, y+1) + I(x+1, y+1))
    return gx, gy


def qualify():
    ok = True

    def check(name, cond, detail):
        nonlocal ok
        print(f"QUAL {name}: {'PASS' if cond else 'FAIL'} ({detail})")
        ok = ok and cond

    # constant image -> all derivatives zero
    img = np.full((64, 64), 200, np.uint8)
    gx, gy, out = sobel_adapter(img)
    check("constant", gx.max() == 0 and gy.max() == 0 and out.max() == 0,
          "200 everywhere")

    # vertical step edge: 0 for x<32, 255 for x>=32
    img = np.zeros((64, 64), np.uint8)
    img[:, 32:] = 255
    gx, gy, out = sobel_adapter(img)
    egx, egy = formula_at(img, 31, 32)
    check("step formula value", (egx, egy) == (1020, 0),
          f"hand formula at (31,32) = {(egx, egy)}")
    check("step cv2==formula", int(gx[32, 31]) == egx
          and int(gx[32, 32]) == egx and int(gy[32, 31]) == 0,
          f"cv2 gx(31,32)={gx[32, 31]} gx(32,32)={gx[32, 32]}")
    check("step output clamp", int(out[32, 31]) == 255,
          "1020 clamps to 255")
    check("step borders zero", gx[0, 31] == 0 and gx[32, 0] == 0,
          "frame zeroed")

    # impulse: single 255 at (32,32) on black
    img = np.zeros((64, 64), np.uint8)
    img[32, 32] = 255
    gx, gy, out = sobel_adapter(img)
    spots = {(31, 32): (510, 0), (33, 32): (-510, 0),
             (32, 31): (0, 510), (32, 33): (0, -510),
             (31, 31): (255, 255), (33, 33): (-255, -255)}
    good = True
    for (x, y), (ex, ey) in spots.items():
        fx, fy = formula_at(img, x, y)
        if (fx, fy) != (ex, ey) or int(gx[y, x]) != ex or int(gy[y, x]) != ey:
            good = False
    check("impulse cv2==formula==hand", good, "6 neighbour positions")

    print("QUALIFY:", "ALL PASS" if ok else "FAILURES PRESENT")
    return 0 if ok else 1


def compute(raw_path, outdir):
    os.makedirs(outdir, exist_ok=True)
    raw = open(raw_path, "rb").read()
    assert len(raw) == 4096
    img = np.frombuffer(raw, np.uint8).reshape(64, 64)
    gx, gy, out = sobel_adapter(img)
    np.save(os.path.join(outdir, "gx.npy"), gx)
    np.save(os.path.join(outdir, "gy.npy"), gy)
    with open(os.path.join(outdir, "ref_out.raw"), "wb") as f:
        f.write(out.tobytes())
    import PIL.Image
    PIL.Image.fromarray(out, "L").save(os.path.join(outdir, "ref_out.png"))
    meta = {
        "reference": SPEC,
        "cv2_version": cv2.__version__,
        "numpy_version": np.__version__,
        "input_raw_sha256": hashlib.sha256(raw).hexdigest(),
        "ref_out_sha256": hashlib.sha256(out.tobytes()).hexdigest(),
        "gx_sha256": hashlib.sha256(gx.tobytes()).hexdigest(),
        "gy_sha256": hashlib.sha256(gy.tobytes()).hexdigest(),
    }
    with open(os.path.join(outdir, "ref.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print(json.dumps(meta))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)
    sub.add_parser("qualify")
    c = sub.add_parser("compute")
    c.add_argument("--raw", required=True)
    c.add_argument("--outdir", required=True)
    args = ap.parse_args()
    if args.mode == "qualify":
        raise SystemExit(qualify())
    compute(args.raw, args.outdir)


if __name__ == "__main__":
    main()

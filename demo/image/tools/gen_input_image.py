#!/usr/bin/env python3
"""Generate the canonical 64x64 GRAY8 input images for the image demo.

Deterministic procedural drawings (PIL, hard shapes + one antialiased
text glyph). The .raw file is the canonical pixel source of truth;
the .png is the same pixels as a viewable grayscale PNG.

Usage: gen_input_image.py --kind main|extra --outdir DIR
Writes <kind>.raw, <kind>.png, <kind>_preview.png (8x NEAREST),
<kind>.json (provenance + hashes).
"""
import argparse
import hashlib
import json
import os

from PIL import Image, ImageDraw, ImageFont

W = H = 64
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def main_image():
    img = Image.new("L", (W, H), 0)
    px = img.load()
    for y in range(H):  # vertical gradient background 24 -> 96
        v = 24 + (96 - 24) * y // (H - 1)
        for x in range(W):
            px[x, y] = v
    d = ImageDraw.Draw(img)
    d.rectangle([1, 1, 62, 62], outline=160)                    # frame
    d.ellipse([38, 4, 56, 22], fill=235)                        # sun
    font = ImageFont.truetype(FONT, 34)
    d.text((5, 8), "M", font=font, fill=255)                    # letter
    d.line([0, 63, 44, 26], fill=200, width=2)                  # diagonal
    for y in range(54, 64):                                     # sea stripes
        d.line([0, y, 63, y], fill=60 if (y // 2) % 2 == 0 else 115)
    return img


def extra_image():
    img = Image.new("L", (W, H), 110)
    d = ImageDraw.Draw(img)
    for r, v in ((27, 255), (21, 0), (15, 255), (9, 0), (4, 255)):
        d.ellipse([32 - r, 32 - r, 32 + r, 32 + r], outline=v, width=3)
    d.line([32, 0, 32, 63], fill=255, width=1)
    d.line([0, 32, 63, 32], fill=255, width=1)
    for cy in range(2):                                         # checker corner
        for cx in range(2):
            for yy in range(8):
                for xx in range(8):
                    if (xx // 4 + yy // 4 + cx + cy) % 2 == 0:
                        d.point((cx * 8 + xx, cy * 8 + yy), fill=255)
                    else:
                        d.point((cx * 8 + xx, cy * 8 + yy), fill=0)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", choices=["main", "extra"], required=True)
    ap.add_argument("--outdir", required=True)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    img = main_image() if args.kind == "main" else extra_image()
    raw = img.tobytes()
    assert len(raw) == 4096
    frame_id = 1 if args.kind == "main" else 2
    desc = ("Procedural 64x64 scene: gradient background, framed sun, "
            "bold letter M, diagonal, sea stripes (PIL drawing, this script)"
            if args.kind == "main" else
            "Procedural 64x64 pattern: concentric rings, cross, checkerboard "
            "corner on mid gray (PIL drawing, this script)")

    base = os.path.join(args.outdir, args.kind)
    with open(base + ".raw", "wb") as f:
        f.write(raw)
    img.save(base + ".png")
    img.resize((512, 512), Image.NEAREST).save(base + "_preview.png")
    meta = {
        "kind": args.kind,
        "frame_id": frame_id,
        "width": W, "height": H, "format": "GRAY8 row-major",
        "source": desc,
        "generator": "demo/image/tools/gen_input_image.py (PIL)",
        "raw_sha256": sha256(raw),
        "png_sha256": sha256(open(base + ".png", "rb").read()),
    }
    with open(base + ".json", "w") as f:
        json.dump(meta, f, indent=2)
    print(json.dumps(meta))


if __name__ == "__main__":
    main()

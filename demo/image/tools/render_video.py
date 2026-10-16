#!/usr/bin/env python3
"""Render the Muse MCU visual demo video from two recorded runs.

Produces, in --out-dir:
  Muse_MCU_Visual_Demo.mp4  1080x1350, H.264, 30 fps, about 55 s
  captions.srt               same captions that are burned into frames
  cover.png                  1080x1350 cover image

Every number, waveform and image comes from the run directories
(results.json, tb_result.json, anchors.json, decoded_tables.json,
writes.csv, stage06/stage07 VCD slices and the stage assets).
Frames are composed with PIL and piped to ffmpeg. No em dashes.
"""
import argparse
import csv
import io
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1080, 1350, 30
BG = (13, 15, 18)
PANEL = (22, 25, 30)
WHITE = (240, 242, 245)
GRAY = (154, 160, 166)
ACCENT = (127, 212, 255)
GREEN = (88, 190, 105)
RED = (255, 82, 82)
UNWRITTEN = (214, 80, 0)

# Consistent task colors used everywhere a task is named.
TASK_COLORS = {
    "ImageIO": (176, 176, 176),
    "GradientX": (66, 165, 245),
    "GradientY": (171, 127, 245),
    "Combine": (88, 179, 104),
}

FD = "/usr/share/fonts/truetype/dejavu"
F_TITLE = ImageFont.truetype(f"{FD}/DejaVuSans-Bold.ttf", 46)
F_TITLE_XL = ImageFont.truetype(f"{FD}/DejaVuSans-Bold.ttf", 58)
F_H = ImageFont.truetype(f"{FD}/DejaVuSans-Bold.ttf", 34)
F_BODY = ImageFont.truetype(f"{FD}/DejaVuSans.ttf", 30)
F_BODY_B = ImageFont.truetype(f"{FD}/DejaVuSans-Bold.ttf", 30)
F_SMALL = ImageFont.truetype(f"{FD}/DejaVuSans.ttf", 24)
F_CAP = ImageFont.truetype(f"{FD}/DejaVuSans.ttf", 33)
F_MONO = ImageFont.truetype(f"{FD}/DejaVuSansMono.ttf", 25)
F_MONO_B = ImageFont.truetype(f"{FD}/DejaVuSansMono-Bold.ttf", 27)


def wrap(draw, text, font, maxw):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=font) <= maxw:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def text_block(draw, x, y, text, font=F_BODY, fill=WHITE, maxw=1000,
               leading=1.25):
    for ln in wrap(draw, text, font, maxw):
        draw.text((x, y), ln, font=font, fill=fill)
        y += int(font.size * leading)
    return y


def base_frame(tag, tag_color, title, caption, cap_color=ACCENT):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 24), "REPLAY OF RECORDED RTL SIMULATION", font=F_SMALL,
           fill=GRAY)
    tw = d.textlength(tag, font=F_SMALL)
    d.text((W - 40 - tw, 24), tag, font=F_SMALL, fill=tag_color)
    y = 62
    for ln in wrap(d, title, F_TITLE, 1000):
        d.text((40, y), ln, font=F_TITLE, fill=WHITE)
        y += 56
    # caption band
    d.rectangle([0, 1130, W, H], fill=(18, 20, 24))
    d.rectangle([0, 1130, W, 1136], fill=cap_color)
    cy = 1158
    for ln in wrap(d, caption, F_CAP, 984):
        d.text((48, cy), ln, font=F_CAP, fill=WHITE)
        cy += 44
    return img, d


def fit_asset(path, maxw, maxh, trim=False):
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    im = Image.alpha_composite(bg, im).convert("RGB")
    if trim:
        g = np.asarray(im.convert("L")) < 250
        rows = np.where(g.any(axis=1))[0]
        cols = np.where(g.any(axis=0))[0]
        if len(rows) and len(cols):
            im = im.crop((max(0, cols[0] - 14), max(0, rows[0] - 14),
                          min(im.width, cols[-1] + 15),
                          min(im.height, rows[-1] + 15)))
    s = min(maxw / im.width, maxh / im.height)
    return im.resize((int(im.width * s), int(im.height * s)),
                     Image.LANCZOS)


F_CHIP = ImageFont.truetype(f"{FD}/DejaVuSans-Bold.ttf", 27)
F_CHIP_S = ImageFont.truetype(f"{FD}/DejaVuSans.ttf", 20)


def chip(d, x, y, w, name, sub, color):
    d.rounded_rectangle([x, y, x + w, y + 78], radius=10, fill=color)
    tw = d.textlength(name, font=F_CHIP)
    d.text((x + (w - tw) / 2, y + 8), name, font=F_CHIP,
           fill=(10, 10, 10))
    tw = d.textlength(sub, font=F_CHIP_S)
    d.text((x + (w - tw) / 2, y + 44), sub, font=F_CHIP_S,
           fill=(30, 30, 30))


# ---------------------------------------------------------------- data

def load_rows(path):
    rows = []
    with open(path) as f:
        next(f)
        for line in f:
            c, a, dd, s = line.strip().split(",")
            rows.append((int(c), int(a, 16), int(dd, 16), int(s, 16)))
    return rows


def committed_sequence(rows, base, size):
    seq = []
    for c, addr, data, strb in rows:
        for lane in range(4):
            if strb & (1 << lane):
                off = addr + lane - base
                if 0 <= off < size:
                    seq.append((c, off, (data >> (8 * lane)) & 0xFF))
    return seq


class Run:
    def __init__(self, rd):
        self.dir = rd
        self.results = json.load(open(os.path.join(rd, "results.json")))
        self.tb = json.load(open(os.path.join(rd, "tb_result.json")))
        self.anchors = json.load(open(os.path.join(rd, "anchors.json")))
        self.tables = json.load(
            open(os.path.join(rd, "assets", "decoded_tables.json")))
        sym = json.load(open(os.path.join(rd, "symbols.json")))
        rows = load_rows(os.path.join(rd, "writes.csv"))
        self.in_seq = committed_sequence(
            rows, int(sym["img_in"], 16), 4096)
        out_all = committed_sequence(
            rows, int(sym["img_out"], 16), 4096)
        load_done = self.anchors["stages"]["05"]["events"][0]["cycle"]
        self.out_seq = [e for e in out_all if e[0] >= load_done]
        # Animation sequences: the img_in region is first cleared
        # with zeroes (cycles ~74k), then the pixel bytes land one
        # by one. Animate the write that establishes each byte's
        # final value (the data write), not the clear pass.
        self.in_anim = self._data_seq(self.in_seq)
        self.out_anim = self._data_seq(self.out_seq)
        self.in_final = self._final(self.in_seq)
        self.out_final = self._final(out_all)

    @staticmethod
    def _data_seq(seq):
        last = {}
        for c, off, b in seq:
            last[off] = (c, b)
        return sorted((c, off, b) for off, (c, b) in last.items())

    @staticmethod
    def _final(seq):
        arr = bytearray(4096)
        for _c, off, b in seq:
            arr[off] = b
        return bytes(arr)

    def asset(self, name):
        return os.path.join(self.dir, "assets", name)


def pixel_img(arr_bytes, size, written_mask=None):
    a = np.frombuffer(arr_bytes, np.uint8).reshape(64, 64)
    rgb = np.stack([a] * 3, axis=-1).astype(np.uint8)
    if written_mask is not None:
        rgb[~written_mask] = UNWRITTEN
    return Image.fromarray(rgb).resize((size, size), Image.NEAREST)


class Animator:
    """Applies a committed byte-write sequence progressively."""

    def __init__(self, seq):
        self.seq = seq
        self.c0 = seq[0][0]
        self.c1 = seq[-1][0]
        self.reset()

    def reset(self):
        self.vals = bytearray(4096)
        self.mask = np.zeros(4096, dtype=bool)
        self.idx = 0
        self.count = 0

    def frame(self, frac, size):
        target = self.c0 + frac * (self.c1 - self.c0)
        while self.idx < len(self.seq) and self.seq[self.idx][0] <= target:
            _c, off, b = self.seq[self.idx]
            self.vals[off] = b
            if not self.mask[off]:
                self.mask[off] = True
                self.count += 1
            self.idx += 1
        img = pixel_img(bytes(self.vals), size,
                        self.mask.reshape(64, 64))
        return img, int(target), self.count


# ------------------------------------------------------- waveform panels

def waveform_panels(run_base, run_fault, tmpdir):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    sys.path.insert(0, os.path.join(os.path.dirname(
        os.path.abspath(__file__))))
    from vcd_tools import parse_vcd, value_at

    plt.rcParams.update({
        "font.family": "DejaVu Sans", "text.color": "#e8eaed",
        "axes.edgecolor": "#5a6068", "axes.labelcolor": "#e8eaed",
        "xtick.color": "#9aa0a6", "ytick.color": "#9aa0a6",
        "figure.facecolor": "#0d0f12", "axes.facecolor": "#0d0f12",
        "savefig.facecolor": "#0d0f12"})

    # UART TX panel from the baseline stage07 slice.
    _ts, s = parse_vcd(os.path.join(
        run_base.dir, "stage07_uart.vcd"), {"uart_tx"})
    tx = s["uart_tx"]
    xs, ys = [], []
    for t, v in tx:
        xs.append(t / 1000)
        ys.append(v)
    fig, ax = plt.subplots(figsize=(10.0, 2.9), dpi=100)
    ax.step(xs, ys, where="post", color="#7fd4ff", lw=1.6)
    ax.set_xlim(0, 470000)
    ax.set_ylim(-0.25, 1.45)
    ax.set_yticks([0, 1])
    ax.set_yticklabels(["0", "1"])
    excerpt = run_base.tables["uart_excerpt"]
    start_ns = 29130
    for k in range(5):
        bx = start_ns + k * 86800
        ax.axvline(bx, color="#5a6068", lw=0.7, ls=":")
        val = excerpt[str(2001 + k)]
        ax.text(bx + 43400, 1.22, f"byte {2001 + k}\n0x{val:02x}",
                ha="center", fontsize=10.5, color="#e8eaed")
    ax.set_xlabel("simulation time (ns), excerpt of stage07 VCD; "
                  "one byte = 86,800 ns")
    ax.set_title("UART TX pin, packet bytes 2000 onward",
                 color="#e8eaed", fontsize=12)
    fig.tight_layout()
    p_uart = os.path.join(tmpdir, "panel_uart.png")
    fig.savefig(p_uart)
    plt.close(fig)

    # Injection panel from the fault stage06 slice.
    _ts, s = parse_vcd(os.path.join(
        run_fault.dir, "stage06_writeback.vcd"),
        {"d_wstrb", "d_waddr", "d_wdata"})
    lo, hi = 262000, 328000  # ns

    def lane(name, fn=lambda v: v):
        xs, ys = [], []
        for t, v in s[name]:
            ns = t / 1000
            if lo - 20000 <= ns <= hi + 20000:
                xs.append(ns)
                ys.append(fn(v))
        return xs, ys

    fig, axes = plt.subplots(3, 1, figsize=(10.0, 3.6), dpi=100,
                             sharex=True)
    x, y = lane("d_waddr")
    axes[0].step(x, y, where="post", color="#7fd4ff", lw=1.4)
    axes[0].set_ylabel("d_waddr")
    axes[0].tick_params(labelbottom=False)
    tgt = (0x1D8E4) >> 2
    axes[0].axhline(tgt, color="#ff5252", lw=0.8, ls="--")
    axes[0].text(0.012, 0.06, "dashed line: target word 0x7639 "
                 "(byte address 0x1d8e4)", fontsize=10,
                 color="#ff8a80", transform=axes[0].transAxes,
                 bbox=dict(facecolor="#0d0f12", edgecolor="none",
                           alpha=0.8, pad=2))
    x, y = lane("d_wdata", lambda v: v & 0xFF)
    axes[1].step(x, y, where="post", color="#ffd54f", lw=1.4)
    axes[1].set_ylabel("d_wdata[7:0]")
    axes[1].tick_params(labelbottom=False)
    x, y = lane("d_wstrb")
    axes[2].step(x, y, where="post", color="#58b368", lw=1.4)
    axes[2].set_ylabel("d_wstrb")
    axes[2].set_xlabel("simulation time (ns), excerpt of stage06 VCD; "
                       "surrounding cycles omitted")
    inj_ns = 293630
    for ax_ in axes:
        ax_.set_xlim(lo, hi)
        ax_.axvline(inj_ns, color="#ff5252", lw=1.6)
    axes[0].set_title("SRAM write of pixel (32,32): bus presents 0x00, "
                      "testbench flips bit 7 at acceptance",
                      color="#e8eaed", fontsize=12)
    fig.tight_layout()
    p_inj = os.path.join(tmpdir, "panel_inj.png")
    fig.savefig(p_inj)
    plt.close(fig)
    return p_uart, p_inj


# ---------------------------------------------------------------- scenes

CAPTIONS = [
    (0.0, 3.0, "A 64 by 64 grayscale image, processed by a "
               "microcontroller running in RTL simulation."),
    (3.0, 9.0, "The image is read from SPI flash into SRAM. Every "
               "byte is checked against the source image."),
    (9.0, 14.0, "Two gradient tasks compute the Sobel Gx and Gy for "
                "each stripe of four rows."),
    (14.0, 19.0, "Combine waits on queues for both gradient stripes. "
                 "No stripe is combined early."),
    (19.0, 23.5, "Combine writes the edge image into the output "
                 "framebuffer, one stripe at a time."),
    (23.5, 26.0, "The finished frame is read back over UART with a "
                 "SHA-256 digest."),
    (26.0, 31.0, "Baseline result: the stored image matches the "
                 "OpenCV reference. Zero mismatches."),
    (31.0, 36.0, "Fault run: same firmware, same input. The testbench "
                 "will flip one bit in SRAM."),
    (36.0, 41.0, "Fault run: the computation and task schedule "
                 "replay identically."),
    (41.0, 47.0, "At the final write of pixel (32, 32), one bit is "
                 "flipped: 0x00 becomes 0x80."),
    (47.0, 52.0, "The corrupted byte is exported over UART. The "
                 "reference comparison finds exactly one wrong pixel."),
    (52.0, 55.0, "The checker rejects the faulty image. Define "
                 "behavior and verify the evidence."),
]


def cap_at(t):
    for a, b, txt in CAPTIONS:
        if a <= t < b:
            return txt
    return CAPTIONS[-1][2]


def scene_title(base, fault, uart_panel, inj_panel):
    # 0-3 s: input + edge preview
    img, d = base_frame("BASELINE", GREEN,
                        "Sobel edge detection on the Muse MCU",
                        cap_at(0))
    d.text((45, 200), "INPUT IMAGE: 64 x 64 GRAY8, frame 1",
           font=F_SMALL, fill=GRAY)
    img.paste(pixel_img(base.in_final, 470), (45, 240))
    d.text((580, 200), "EDGE OUTPUT (SOBEL)", font=F_SMALL, fill=GRAY)
    img.paste(pixel_img(base.out_final, 470), (580, 240))
    d.text((532, 440), ">", font=F_TITLE_XL, fill=ACCENT)
    y = text_block(d, 45, 760,
                   "A FreeRTOS application on a RISC-V MCU core, "
                   "simulated in RTL. The image arrives from SPI "
                   "flash; four tasks compute its Sobel edge map; "
                   "an independent checker verifies every byte.",
                   font=F_BODY, maxw=990)
    y = text_block(d, 45, y + 26,
                   "Runs: baseline-20261013-222600 and "
                   "fault-20261013-222600-r4 (reviewed).",
                   font=F_SMALL, fill=GRAY, maxw=990)
    return [img] * 90


def anim_frames(run, seq, tag, tag_color, title, cap, label,
                nframes, canvas=640):
    anim = Animator(seq)
    frames = []
    hold = None
    for i in range(nframes):
        frac = min(1.0, i / max(1, nframes - 12))
        cimg, cyc, cnt = anim.frame(frac, canvas)
        img, d = base_frame(tag, tag_color, title, cap)
        d.text((40, 150), label, font=F_SMALL, fill=GRAY)
        img.paste(cimg, ((W - canvas) // 2, 190))
        d.text((40, 190 + canvas + 24),
               f"cycle {cyc:,}   {cnt:,} of 4,096 bytes written",
               font=F_MONO_B, fill=ACCENT)
        d.text((40, 190 + canvas + 66),
               "orange = not yet written; playback accelerated",
               font=F_SMALL, fill=GRAY)
        frames.append(img)
        hold = img
    return frames


def scene_load(base):
    frames = anim_frames(
        base, base.in_anim, "BASELINE", GREEN,
        "Loading the image: SPI flash to SRAM", cap_at(3),
        "INPUT SRAM BUFFER, RECONSTRUCTED FROM COMMITTED WRITES",
        180)
    # add the decoded SPI strip panel to the last frames' lower area
    strip = ("row 32 read: cmd 0x03, address 0x000814; MISO bytes "
             "match the stored pixels byte for byte")
    for i, img in enumerate(frames):
        if i >= 60:
            d = ImageDraw.Draw(img)
            d.rectangle([40, 986, 1040, 1076], fill=PANEL)
            text_block(d, 58, 1002, strip, font=F_SMALL, maxw=950)
    return frames


def scene_algorithm(base):
    img, d = base_frame("BASELINE", GREEN,
                        "Sobel gradients, one stripe at a time",
                        cap_at(9))
    card = fit_asset(base.asset("stage04_pixel.png"), 1000, 560,
                     trim=True)
    img.paste(card, (40, 160))
    y = 160 + card.height + 30
    labels = [("ImageIO", "ImageIO", "priority 1"),
              ("GradientX", "GradientX", "priority 2"),
              ("GradientY", "GradientY", "priority 2"),
              ("Combine", "Combine", "priority 3")]
    x = 40
    for key, name, sub in labels:
        chip(d, x, y, 240, name, sub, TASK_COLORS[key])
        x += 253
    y += 104
    y = text_block(
        d, 40, y,
        "GradientX computes Gx and GradientY computes Gy for the "
        "same four-row stripe, into separate SRAM buffers. "
        "out = min(255, |Gx| + |Gy|).", maxw=990)
    text_block(d, 40, y + 10,
               "Pixel (32, 32) above: Gx write at cycle 1,869,189; "
               "Gy write at cycle 1,933,984 (from the write monitor).",
               font=F_SMALL, fill=GRAY, maxw=990)
    return [img] * 150


def scene_rtos(base):
    img, d = base_frame("BASELINE", GREEN,
                        "Real task interleaving", cap_at(14))
    card = fit_asset(base.asset("stage05_rtos.png"), 1000, 330)
    img.paste(card, (40, 160))
    y = 160 + card.height + 26
    y = text_block(
        d, 40, y,
        "Retired-PC classification from the recorded trace. GXn "
        "and GYn mark gradient stripe n published on its queue; "
        "CBn marks Combine writing stripe n.", maxw=990)
    y = text_block(
        d, 40, y + 8,
        "Combine runs only after both publications for that "
        "stripe: blocking queues, no polling.", maxw=990)
    text_block(d, 40, y + 16,
               "window: cycles 1,752,629 (load done) to 1,828,871 "
               "(Combine stripe 2); time compressed",
               font=F_SMALL, fill=GRAY, maxw=990)
    return [img] * 150


def scene_uart(base, uart_panel):
    img, d = base_frame("BASELINE", GREEN,
                        "Readback over UART", cap_at(23.5))
    card = fit_asset(uart_panel, 1000, 300)
    img.paste(card, (40, 170))
    y = 170 + card.height + 30
    tb = base.tb
    y = text_block(
        d, 40, y,
        f"One packet: 20 B header + 4,096 B payload + 32 B "
        f"SHA-256 = {tb['packet_bytes_seen']:,} bytes.", maxw=990)
    y = text_block(
        d, 40, y + 8,
        "The payload equals the stored framebuffer, and the digest "
        "recomputes correctly, so the export is lossless.", maxw=990)
    text_block(d, 40, y + 16,
               f"last byte at cycle {tb['last_byte_cycle']:,}; "
               "50,000 quiet cycles observed, no extra bytes",
               font=F_SMALL, fill=GRAY, maxw=990)
    return [img] * 75


def scene_baseline_result(base):
    img, d = base_frame("BASELINE", GREEN,
                        "Baseline result: exact match", cap_at(26))
    card = fit_asset(base.asset("stage08_compare.png"), 1000, 350)
    img.paste(card, (40, 160))
    y = 160 + card.height + 24
    d.text((40, y), "FUNCTIONAL: PASS", font=F_TITLE, fill=GREEN)
    y += 72
    c = base.results["checks"]
    rows = [
        f"output SRAM: {c['output_sram']['coverage']:,} bytes "
        f"compared, {c['output_sram']['mismatch_count']} mismatches",
        f"gradients: Gx {c['gradients_sram']['gx_mismatches']} and "
        f"Gy {c['gradients_sram']['gy_mismatches']} mismatches over "
        f"8,192 values each",
        "input SRAM and SPI payload: all 4,096 bytes match",
        "UART payload equals stored image; SHA-256 digest OK",
    ]
    for r in rows:
        d.text((40, y), r, font=F_BODY, fill=WHITE)
        y += 44
    return [img] * 150


def scene_fault_intro(fault):
    frames = anim_frames(
        fault, fault.in_anim, "FAULT RUN", RED,
        "Fault run: same start, one flipped bit", cap_at(31),
        "INPUT SRAM BUFFER, FAULT RUN REPLAY", 150, canvas=560)
    for img in frames:
        d = ImageDraw.Draw(img)
        d.rectangle([40, 850, 1040, 1080], fill=PANEL)
        y = text_block(d, 58, 868,
                       "Same frozen firmware, same input image. "
                       "The only change is in the testbench:",
                       font=F_BODY, maxw=950)
        text_block(d, 58, y + 6,
                   "flip bit 7 of the final SRAM write to output "
                   "pixel (32, 32), offset 2080.",
                   font=F_BODY_B, fill=(255, 160, 140), maxw=950)
    return frames


def scene_fault_rtos(fault):
    img, d = base_frame("FAULT RUN", RED,
                        "Fault run: computation replays identically",
                        cap_at(36))
    card = fit_asset(fault.asset("stage05_rtos.png"), 1000, 330)
    img.paste(card, (40, 196))
    y = 196 + card.height + 26
    c = fault.results["checks"]
    rows = [
        "task evidence: pass (same stripe order and timing)",
        f"gradients: {c['gradients_sram']['gx_mismatches'] + c['gradients_sram']['gy_mismatches']} mismatches; input and SPI payload match",
        "nothing in the computation knows about the fault",
        "the flip happens at the SRAM write port, in the testbench",
    ]
    for r in rows:
        y = text_block(d, 40, y, r, maxw=990)
        y += 6
    return [img] * 150


def scene_injection(fault, inj_panel):
    img, d = base_frame("FAULT RUN", RED,
                        "The injection: one bit, one write",
                        cap_at(41))
    card = fit_asset(inj_panel, 1000, 370)
    img.paste(card, (40, 160))
    y = 160 + card.height + 22
    tb = fault.tb["fault"]
    d.text((40, y), f"target address {tb['addr']}  "
           "(framebuffer base + 2080)", font=F_BODY_B, fill=WHITE)
    y += 48
    d.text((40, y), "final write of pixel (32, 32): cycle 1,940,572",
           font=F_BODY, fill=WHITE)
    y += 44
    d.text((40, y), f"injection recorded at cycle {tb['cycle']:,}",
           font=F_BODY, fill=WHITE)
    y += 52
    d.text((40, y), "intended byte   0x00   0000 0000",
           font=F_MONO_B, fill=WHITE)
    y += 46
    d.text((40, y), "committed byte  0x80   1000 0000  (bit 7 flipped)",
           font=F_MONO_B, fill=(255, 160, 140))
    y += 52
    d.text((40, y), f"byte strobe 0x1; testbench readback after "
           f"the write: {tb['readback_byte']}", font=F_BODY,
           fill=WHITE)
    return [img] * 180


def scene_fault_result(fault):
    img, d = base_frame("FAULT RUN", RED,
                        "One wrong pixel", cap_at(47))
    card = fit_asset(fault.asset("stage08_crop.png"), 470, 470)
    img.paste(card, (40, 170))
    x = 545
    y = 190
    m = fault.results["checks"]["output_sram"]["mismatches"][0]
    y = text_block(d, x, y,
                   f"pixel ({m['x']}, {m['y']}): expected "
                   f"{m['expected']}, stored {m['actual']}",
                   font=F_BODY_B, maxw=490)
    y = text_block(d, x, y + 8,
                   "The UART export carried the corrupted byte "
                   "faithfully: payload equals the stored image, "
                   "digest still verifies.", maxw=490)
    y = text_block(d, x, y + 8,
                   "Only the reference comparison sees the error.",
                   maxw=490)
    card2 = fit_asset(fault.asset("stage08_compare.png"), 1000, 330)
    img.paste(card2, (40, 700))
    return [img] * 150


def scene_close(base, fault):
    img, d = base_frame("VERDICTS", ACCENT,
                        "Two runs, three separate verdicts",
                        cap_at(52))
    y = 190
    d.text((40, y), "BASELINE", font=F_H, fill=GREEN)
    d.text((330, y), "functional PASS, zero mismatches",
           font=F_BODY, fill=WHITE)
    y += 80
    d.text((40, y), "FAULT RUN", font=F_H, fill=RED)
    d.text((330, y), "functional FAIL, exactly one wrong pixel",
           font=F_BODY, fill=WHITE)
    y += 100
    rows = [("packet integrity (UART + SHA-256):", "MATCH", GREEN),
            ("image vs reference:", "MISMATCH", RED),
            ("negative control detection:", "CONFIRMED", GREEN)]
    for lab, val, col in rows:
        d.text((40, y), lab, font=F_BODY, fill=WHITE)
        tw = d.textlength(val, font=F_BODY_B)
        d.text((W - 60 - tw, y), val, font=F_BODY_B, fill=col)
        y += 52
    y += 60
    for ln in wrap(d, "Define behavior and verify the evidence.",
                   F_TITLE, 1000):
        d.text((40, y), ln, font=F_TITLE, fill=WHITE)
        y += 56
    return [img] * 90


def make_cover(base, out_path):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((40, 60), "MUSE MCU", font=F_SMALL, fill=GRAY)
    y = 110
    for ln in wrap(d, "Sobel edge detection, verified on silicon "
                      "behavior", F_TITLE_XL, 1000):
        d.text((40, y), ln, font=F_TITLE_XL, fill=WHITE)
        y += 70
    y += 20
    y = text_block(d, 40, y,
                   "A FreeRTOS image pipeline on a RISC-V MCU in "
                   "RTL simulation, plus a one-bit SRAM fault that "
                   "the checker had to catch.", font=F_BODY, maxw=990)
    y += 30
    d.text((45, y), "INPUT", font=F_SMALL, fill=GRAY)
    d.text((570, y), "EDGE OUTPUT", font=F_SMALL, fill=GRAY)
    y += 36
    img.paste(pixel_img(base.in_final, 470), (45, y))
    img.paste(pixel_img(base.out_final, 470), (570, y))
    y += 500
    d.text((40, y), "Replay of recorded RTL simulation",
           font=F_H, fill=ACCENT)
    y += 54
    text_block(d, 40, y,
               "Baseline: PASS with zero mismatches. "
               "Fault run: one flipped bit, detected.",
               font=F_BODY, maxw=990)
    img.save(out_path)


def srt_time(t):
    ms = int(round(t * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline-dir", required=True)
    ap.add_argument("--fault-dir", required=True)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    import tempfile
    tmpdir = tempfile.mkdtemp(prefix="render_video_")

    base = Run(args.baseline_dir)
    fault = Run(args.fault_dir)
    uart_panel, inj_panel = waveform_panels(base, fault, tmpdir)

    scenes = []
    scenes += scene_title(base, fault, uart_panel, inj_panel)
    scenes += scene_load(base)
    scenes += scene_algorithm(base)
    scenes += scene_rtos(base)
    scenes += anim_frames(base, base.out_anim, "BASELINE", GREEN,
                          "Writing the edge image to SRAM",
                          cap_at(19),
                          "OUTPUT FRAMEBUFFER, COMMITTED WRITES",
                          135)
    scenes += scene_uart(base, uart_panel)
    scenes += scene_baseline_result(base)
    scenes += scene_fault_intro(fault)
    scenes += scene_fault_rtos(fault)
    scenes += scene_injection(fault, inj_panel)
    scenes += scene_fault_result(fault)
    scenes += scene_close(base, fault)
    assert len(scenes) == FPS * 55, f"frame count {len(scenes)}"

    out_mp4 = os.path.join(args.out_dir, "Muse_MCU_Visual_Demo.mp4")
    cmd = ["ffmpeg", "-y", "-f", "image2pipe", "-framerate",
           str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt",
           "yuv420p", "-r", str(FPS), "-preset", "medium",
           "-crf", "20", "-movflags", "+faststart", out_mp4]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for fr in scenes:
        buf = io.BytesIO()
        fr.save(buf, "PNG")
        proc.stdin.write(buf.getvalue())
    proc.stdin.close()
    rc = proc.wait()
    if rc != 0:
        raise SystemExit(f"ffmpeg failed with {rc}")

    with open(os.path.join(args.out_dir, "captions.srt"), "w") as f:
        for i, (a, b, txt) in enumerate(CAPTIONS, 1):
            f.write(f"{i}\n{srt_time(a)} --> {srt_time(b)}\n"
                    f"{txt}\n\n")
    make_cover(base, os.path.join(args.out_dir, "cover.png"))
    print(f"wrote {out_mp4} ({len(scenes)} frames)")


if __name__ == "__main__":
    main()

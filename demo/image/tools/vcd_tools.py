#!/usr/bin/env python3
"""Minimal VCD tools for the image demo: value-change parsing with
$timescale handling, SPI transaction decode (mode 0, MSB first,
sampled on SCK rising edges under CS), and UART byte decode (8N1).

Shared by the checker (SPI payload observation) and the stage-asset
generator (decoded tables, anchors, VCD slicing). Times are returned
in picoseconds using the file's own $timescale.
"""
import re

SCALE = {"s": 10**12, "ms": 10**9, "us": 10**6, "ns": 10**3, "ps": 1, "fs": 0}


def parse_vcd(path, wanted):
    """Return (timescale_ps, {name: [(t_ps, value), ...]}).

    wanted: set of signal names (last component of hierarchy)."""
    ids = {}
    series = {}
    timescale_ps = 1
    cur = 0
    with open(path, errors="replace") as f:
        in_defs = True
        for line in f:
            if in_defs:
                if line.startswith("$timescale"):
                    m = re.search(r"(\d+)\s*(ms|us|ns|ps|fs|s)", line)
                    if m:
                        timescale_ps = int(m.group(1)) * SCALE[m.group(2)]
                elif line.startswith("$var"):
                    parts = line.split()
                    code, name = parts[3], parts[4]
                    if name in wanted:
                        ids[code] = name
                        series[name] = []
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue
            if not line or line[0] == "$":
                continue
            if line[0] == "#":
                cur = int(line[1:].strip()) * timescale_ps
            elif line[0] in "01xXzZ":
                code = line[1:].strip()
                if code in ids:
                    series[ids[code]].append(
                        (cur, 1 if line[0] == "1" else 0))
            elif line[0] in "bB":
                bits, code = line[1:].split()
                if code in ids:
                    try:
                        series[ids[code]].append((cur, int(bits, 2)))
                    except ValueError:
                        series[ids[code]].append((cur, 0))
    return timescale_ps, series


def value_at(series, t):
    v = series[0][1] if series else 0
    for tt, vv in series:
        if tt > t:
            break
        v = vv
    return v


def edges(series, init):
    out, prev = [], init
    for t, v in series:
        if v != prev:
            out.append((t, v))
            prev = v
    return out


def decode_spi(cs, sck, mosi, miso):
    """Transactions: list of (t_start_ps, t_end_ps, mosi_bytes, miso_bytes)."""
    txns = []
    cs_e = edges(cs, 1)
    sck_e = {}
    prev = 0
    rises = []
    for t, v in sck:
        if v != prev:
            if v == 1:
                rises.append(t)
            prev = v
    import bisect
    rise_times = [t for t in rises]
    for i, (t0, v0) in enumerate(cs_e):
        if v0 != 0:
            continue
        t1 = cs_e[i + 1][0] if i + 1 < len(cs_e) else None
        mb, ib = [], []
        cur_m, cur_i, nb = 0, 0, 0
        j = bisect.bisect_left(rise_times, t0)
        while j < len(rise_times) and (t1 is None or rise_times[j] < t1):
            t = rise_times[j]
            cur_m = (cur_m << 1) | value_at(mosi, t)
            cur_i = (cur_i << 1) | value_at(miso, t)
            nb += 1
            if nb == 8:
                mb.append(cur_m)
                ib.append(cur_i)
                cur_m = cur_i = nb = 0
            j += 1
        txns.append((t0, t1, mb, ib))
    return txns


def slice_vcd(src_path, dst_path, t0_ps, t1_ps):
    """Write a new VCD containing only changes in [t0_ps, t1_ps],
    re-based so the window starts at 0. Header (incl. $var defs) is
    copied verbatim (timescale preserved); initial values at t0 are
    emitted first so traces start defined."""
    # Streaming implementation: the source VCD can exceed 100 MB and
    # materializing it as a list of Python strings takes gigabytes.
    # Pass 1 collects the header and the last value per code before
    # t0; pass 2 streams the window changes straight to the output.
    head = []
    timescale_ps = 1
    last = {}
    cur = 0
    with open(src_path, errors="replace") as f:
        for line in f:
            head.append(line)
            if line.startswith("$timescale"):
                m = re.search(r"(\d+)\s*(ms|us|ns|ps|fs|s)", line)
                if m:
                    timescale_ps = int(m.group(1)) * SCALE[m.group(2)]
            if line.startswith("$enddefinitions"):
                break
        for line in f:
            if not line.strip():
                continue
            if line[0] == "#":
                cur = int(line[1:].strip()) * timescale_ps
                if cur >= t0_ps:
                    break
                continue
            if line[0] == "$":
                continue
            if cur < t0_ps:
                _record(last, line)
    n_changes = 0
    cur = 0
    in_body = False
    with open(src_path, errors="replace") as fin, \
            open(dst_path, "w") as out:
        for line in head:
            out.write(line if line.endswith("\n") else line + "\n")
        out.write("#0\n")
        out.write("$dumpvars\n")
        for code, raw in sorted(last.items()):
            out.write(raw + "\n")
        out.write("$end\n")
        cur_out = 0
        for line in fin:
            if not in_body:
                if line.startswith("$enddefinitions"):
                    in_body = True
                continue
            if not line.strip():
                continue
            if line[0] == "#":
                cur = int(line[1:].strip()) * timescale_ps
                if cur > t1_ps:
                    break
                continue
            if line[0] == "$":
                continue
            if t0_ps <= cur <= t1_ps:
                rel = (cur - t0_ps) // timescale_ps
                if rel != cur_out:
                    out.write(f"#{rel}\n")
                    cur_out = rel
                out.write(line.rstrip("\n") + "\n")
                n_changes += 1
    return n_changes


def _record(store, line):
    if line[0] in "01xXzZ":
        store[line[1:].strip()] = line.rstrip("\n")
    elif line[0] in "bB":
        parts = line.split()
        if len(parts) == 2:
            store[parts[1]] = line.rstrip("\n")

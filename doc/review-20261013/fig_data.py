"""Parse the D1 demo VCD (timescale-aware) and decode SPI + UART."""
import re, sys

def parse_vcd(path, want):
    timescale_ps = None
    id2sig = {}
    data = {s: [] for s in want}
    cur = 0
    in_defs = True
    with open(path, errors="replace") as f:
        for line in f:
            if in_defs:
                if line.startswith("$timescale"):
                    continue
                if "1ps" in line and timescale_ps is None:
                    timescale_ps = 1
                if "1ns" in line and timescale_ps is None:
                    timescale_ps = 1000
                m = re.search(r"\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)", line)
                if m and m.group(2) in want:
                    id2sig[m.group(1)] = m.group(2)
                if line.startswith("$enddefinitions"):
                    in_defs = False
                continue
            if line.startswith("#"):
                cur = int(line[1:])
                continue
            if line and line[0] in "01xzXZ" and len(line.strip()) >= 2:
                v, vid = line[0], line[1:].strip()
                if vid in id2sig:
                    data[id2sig[vid]].append((cur, 1 if v == "1" else 0))
            elif line and line[0] in "bB":
                parts = line[1:].split()
                if len(parts) == 2 and parts[1] in id2sig:
                    try:
                        data[id2sig[parts[1]]].append((cur, int(parts[0], 2)))
                    except ValueError:
                        pass
    return timescale_ps, data

def edges(series, init=1):
    out, prev = [], init
    for t, v in series:
        if v != prev:
            out.append((t, v)); prev = v
    return out

def decode_spi(cs, sck, mosi, miso, ts_ps):
    """Return list of transactions: (t_start_ps, t_end_ps, mosi_bytes, miso_bytes)."""
    # build time-ordered event streams
    def at(series, t, init):
        v = init
        for tt, vv in series:
            if tt > t: break
            v = vv
        return v
    cs_e = edges(cs, 1)
    txns = []
    sck_e = edges(sck, 0)
    mosi_e = edges(mosi, 0); miso_e = edges(miso, 0)
    i = 0
    times = sorted(set([t for t, _ in cs_e]))
    for j in range(0, len(cs_e)):
        t, v = cs_e[j]
        if v == 0:  # falling: txn start
            t_end = cs_e[j+1][0] if j+1 < len(cs_e) else None
            rises = [tt for tt, vv in sck_e if t < tt and (t_end is None or tt < t_end) and vv == 1]
            mb, ib = [], []
            cur_mo, cur_mi = 0, 0
            for k, rt in enumerate(rises):
                cur_mo = (cur_mo << 1) | at(mosi_e, rt, at(mosi, rt, 0))
                cur_mi = (cur_mi << 1) | at(miso_e, rt, at(miso, rt, 0))
                if k % 8 == 7:
                    mb.append(cur_mo); ib.append(cur_mi); cur_mo, cur_mi = 0, 0
            txns.append((t, t_end, mb, ib))
    return txns

def decode_uart(tx, ts_ps, bit_ps):
    """Decode 8N1 from TX edge series (init idle=1). Returns list of (t_ps, byte)."""
    e = edges(tx, 1)
    out = []
    times = [t for t, _ in e]
    vals = {t: v for t, v in e}
    def val_at(t):
        v = 1
        for tt, vv in e:
            if tt > t: break
            v = vv
        return v
    idx = 0
    all_t = sorted(set([t for t, _ in tx] + [t for t, _ in e]))
    # scan falling edges
    prev = 1; series = sorted(tx)
    fall = []
    pv = 1
    for t, v in series:
        if pv == 1 and v == 0: fall.append(t)
        pv = v
    for t0 in fall:
        # start bit at t0; sample bits at t0 + 1.5*bit, ...
        byte = 0; ok = True
        for b in range(8):
            ts = t0 + int(bit_ps * (1.5 + b))
            if val_at(ts): byte |= (1 << b)
        stop_t = t0 + int(bit_ps * 9.5)
        if val_at(stop_t) != 1: ok = False
        out.append((t0, byte, ok))
    # dedupe overlapping decodes (a data-bit fall re-triggers): keep only decodes spaced >= 9 bits
    filt = []; last = -10**18
    for t0, byte, ok in out:
        if t0 - last >= int(bit_ps * 9):
            filt.append((t0, byte, ok)); last = t0
    return filt

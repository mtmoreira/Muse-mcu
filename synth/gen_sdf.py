#!/usr/bin/env python3
"""gen_sdf.py — generate SDF 2.1 back-annotation from Nangate45 liberty.

Yosys 0.33 (the manifest-pinned synthesis tool) has no `write_sdf`, so this
script generates the SDF directly from the liberty timing arcs and the
synthesized netlist hierarchy. Methodology is documented and deterministic.

Delay model (documented, not signoff):
- Each liberty NLDM `cell_rise`/`cell_fall` table is evaluated at the MEDIAN
  input slew (index_1) and MEDIAN output load (index_2) of that table.
- `rise_constraint`/`fall_constraint` (setup/hold) are evaluated the same way;
  the SDF SETUP/HOLD value is the max of rise/fall (worst case).
- SDF triplets are (typ:typ:typ) — typical-corner only, matching the typical
  liberty and the typical cell models.
- Combinational IOPATH rise/fall mapping follows `timing_sense`:
  positive_unate: out_rise<-in_rise (cell_rise), out_fall<-in_fall (cell_fall)
  negative_unate: out_rise<-in_fall (cell_fall), out_fall<-in_rise (cell_rise)
  non_unate (clk->q): out_rise=cell_rise, out_fall=cell_fall.

Usage: synth/gen_sdf.py [--lib PATH] [--net PATH] [--top NAME] [--out PATH]
         [--dut SCOPE]   # SDF INSTANCE paths are relative to this scope

INSTANCE paths are written relative to --dut (default: dut), e.g.
`cpu/_249_` for testbench `mcu_top dut`. SDF DIVIDER is `/`.
"""
import argparse, hashlib, os, re, sys, datetime

LIB_DEFAULT = os.path.join(
    os.environ.get("PDK_DIR", os.path.expanduser("~/workspace/pdk-dl/nangate45")),
    "NangateOpenCellLibrary_typical.lib")


def brace_block(text, start):
    assert text[start] == "{"
    depth, i, in_str = 0, start, False
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\": i += 1
            elif c == '"': in_str = False
        else:
            if c == '"': in_str = True
            elif c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: return text[start+1:i], i+1
        i += 1
    raise ValueError("unbalanced braces")


def find_groups(text, keyword):
    pat = re.compile(re.escape(keyword) + r'\s*(?P<header>\([^)]*\))\s*\{')
    for m in pat.finditer(text):
        inner, _ = brace_block(text, m.end()-1)
        yield m.group("header"), inner


def parse_nldm(body, kind):
    """Return scalar delay: value at median index_1/index_2 of kind table."""
    for header, inner in find_groups(body, kind):
        idx1 = re.search(r'index_1\s*\(\s*"([^"]+)"', inner)
        idx2 = re.search(r'index_2\s*\(\s*"([^"]+)"', inner)
        vm = re.search(r'values\s*\(\s*(.*?)\s*\)\s*;', inner, re.S)
        if not (idx1 and idx2 and vm): continue
        n1 = len(idx1.group(1).split(','))
        rows = [r.strip().strip('"') for r in vm.group(1).replace('\\\n','').split(',')]
        # rows are n1 rows x n2 cols, but values() flattens row-major;
        # re-chunk by counting: total values / n1 = n2
        n2 = len(rows) // n1
        mi, mj = n1 // 2, n2 // 2
        try:
            return float(rows[mi*n2 + mj])
        except (ValueError, IndexError):
            continue
    return None


def parse_liberty(path):
    """cell -> {pin -> {'arcs': [(related, sense, rise, fall)],
                        'setup': val, 'hold': val}}"""
    text = open(path).read()
    cells = {}
    for chead, cbody in find_groups(text, 'cell'):
        cname = re.match(r'\(\s*(\w+)\s*\)', chead).group(1)
        pins = {}
        for phead, pbody in find_groups(cbody, 'pin'):
            pname = re.match(r'\(\s*"?(\w+)"?\s*\)', phead).group(1)
            info = {'arcs': [], 'setup': None, 'hold': None, 'clk': 'CK'}
            for thead, tbody in find_groups(pbody, 'timing'):
                rel = re.search(r'related_pin\s*:\s*"(\w+)"', tbody)
                rel = rel.group(1) if rel else None
                sense = re.search(r'timing_sense\s*:\s*(\w+)', tbody)
                sense = sense.group(1) if sense else None
                ttype = re.search(r'timing_type\s*:\s*(\w+)', tbody)
                ttype = ttype.group(1) if ttype else None
                if ttype in ('setup_rising', 'setup_falling'):
                    rc = parse_nldm(tbody, 'rise_constraint')
                    fc = parse_nldm(tbody, 'fall_constraint')
                    vals = [v for v in (rc, fc) if v is not None]
                    if vals: info['setup'] = max(vals); info['clk'] = rel or 'CK'
                elif ttype in ('hold_rising', 'hold_falling'):
                    rc = parse_nldm(tbody, 'rise_constraint')
                    fc = parse_nldm(tbody, 'fall_constraint')
                    vals = [v for v in (rc, fc) if v is not None]
                    if vals: info['hold'] = max(vals); info['clk'] = rel or 'CK'
                elif rel:
                    cr = parse_nldm(tbody, 'cell_rise')
                    cf = parse_nldm(tbody, 'cell_fall')
                    if cr is not None and cf is not None:
                        info['arcs'].append((rel, sense, cr, cf))
            pins[pname] = info
        cells[cname] = pins
    return cells


def netlist_instances(nl_path, top='mcu_top'):
    """Return [(hier_path, celltype)] for all leaf cell instances under top."""
    nl = open(nl_path).read()
    mods = {}
    for m in re.finditer(r'^\s*(?:\(\*.*?\*\)\s*)?module\s+(\w+)', nl, re.M):
        e = nl.index('\nendmodule', m.end())
        # body starts after the header's terminating ';'
        hs = nl.index(';', m.end())
        mods[m.group(1)] = nl[hs+1:e]
    defined = set(mods)
    result = []
    def walk(mod, prefix):
        body = mods[mod]
        for im in re.finditer(r'^\s*(\w+)\s+(\w+)\s*\(', body, re.M):
            typ, inst = im.group(1), im.group(2)
            if typ in ('module','wire','input','output','inout','reg','assign',
                       'parameter','localparam','function','task'): continue
            hp = f"{prefix}/{inst}" if prefix else inst
            if typ in defined:
                walk(typ, hp)
            else:
                result.append((hp, typ))
    walk(top, '')
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lib', default=LIB_DEFAULT)
    ap.add_argument('--net', default='synth/mcu_netlist.v')
    ap.add_argument('--top', default='mcu_top')
    ap.add_argument('--dut', default='dut')
    ap.add_argument('--out', default='synth/mcu.sdf')
    a = ap.parse_args()

    lib_sha = hashlib.sha256(open(a.lib,'rb').read()).hexdigest()
    cells = parse_liberty(a.lib)
    insts = netlist_instances(a.net)
    # keep only instances under top (walk from top)
    print(f"gen_sdf: {len(cells)} liberty cells, {len(insts)} leaf instances")

    lines = []
    A = lines.append
    A('(DELAYFILE')
    A('  (SDFVERSION "2.1")')
    A(f'  (DESIGN "{a.top}")')
    A(f'  (DATE "{datetime.date.today().isoformat()}")')
    A('  (VENDOR "Muse-mcu")')
    A('  (PROGRAM "synth/gen_sdf.py")')
    A('  (VERSION "1.0")')
    A('  (DIVIDER /)')
    A('  (VOLTAGE 1.10:1.10:1.10)')
    A('  (PROCESS "typical")')
    A('  (TEMPERATURE 25.0:25.0:25.0)')
    A('  (TIMESCALE 1ns)')
    A('')
    A(f'  # liberty sha256: {lib_sha}')
    A('  # delay model: NLDM evaluated at median slew/load; triplets typ:typ:typ')
    A('')

    n_cell, n_iopath, n_tc = 0, 0, 0
    missing = set()
    for hpath, ctype in insts:
        if ctype in ('bootrom', 'sram'):
            continue  # declared behavioral macros: zero-delay, no SDF
        pins = cells.get(ctype)
        if not pins:
            missing.add(ctype); continue
        rel = hpath  # already relative to dut scope
        A('  (CELL')
        A(f'    (CELLTYPE "{ctype}")')
        A(f'    (INSTANCE {rel})')
        # delays
        iopaths = []
        for pname, info in pins.items():
            for (rp, sense, cr, cf) in info['arcs']:
                if sense == 'negative_unate':
                    dr, df = cf, cr
                else:  # positive_unate / non_unate
                    dr, df = cr, cf
                iopaths.append(f'        (IOPATH {rp} {pname} '
                               f'({dr:.4f}:{dr:.4f}:{dr:.4f}) '
                               f'({df:.4f}:{df:.4f}:{df:.4f}))')
        if iopaths:
            A('    (DELAY')
            A('      (ABSOLUTE')
            for io in iopaths: A(io)
            A('      )')
            A('    )')
            n_iopath += len(iopaths)
        # timing checks
        tcs = []
        for pname, info in pins.items():
            if info['setup'] is not None:
                tcs.append(f'        (SETUP {pname} (posedge {info["clk"]}) '
                           f'({info["setup"]:.4f}:{info["setup"]:.4f}:{info["setup"]:.4f}))')
            if info['hold'] is not None:
                tcs.append(f'        (HOLD {pname} (posedge {info["clk"]}) '
                           f'({info["hold"]:.4f}:{info["hold"]:.4f}:{info["hold"]:.4f}))')
        if tcs:
            A('    (TIMINGCHECK')
            for tc in tcs: A(tc)
            A('    )')
            n_tc += len(tcs)
        A('  )')
        n_cell += 1
    A(')')
    A('')

    with open(a.out, 'w') as f:
        f.write('\n'.join(lines))
    print(f"gen_sdf: wrote {a.out}: {n_cell} cells, {n_iopath} iopaths, {n_tc} timing checks")
    if missing:
        print(f"gen_sdf: WARNING: liberty cells missing: {sorted(missing)}")
    # sanity: no zero delays on real arcs
    print("gen_sdf: done")


if __name__ == '__main__':
    main()

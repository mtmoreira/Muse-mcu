#!/usr/bin/env python3
"""gen_cells.py — generate zero-delay functional Verilog models for the
Nangate45 typical liberty cells, for gate-level simulation (F2/F3).

Parses cell pin `function` strings (operators ! & | ^ are already valid
Verilog), `ff` groups (next_state with * -> &, + -> |, optional async
clear/preset), and `latch` groups. Cells using `statetable` (the CLKGATE*
clock gates, never used by the synth flow) are skipped and reported.

Usage: synth/gen_cells.py [--lib PATH] [--out PATH]

The output header records the liberty sha256 so the provenance of every
model is pinned to the exact file the netlist was mapped against.
"""
import argparse
import hashlib
import re
import sys

LIB_DEFAULT = "/home/hatch/workspace/pdk-dl/nangate45/NangateOpenCellLibrary_typical.lib"


def brace_block(text, start):
    """Return (body, end_index) for the brace group opened at text[start]."""
    assert text[start] == "{"
    depth = 0
    i = start
    in_str = False
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return text[start + 1:i], i + 1
        i += 1
    raise ValueError("unbalanced braces")


def find_groups(body, keyword):
    """Yield (header, body) for each `keyword (...) { ... }` group.

    `header` is the raw text between the keyword and the opening brace
    (e.g. '( "IQ" , "IQN" )' or '(AND2_X1)'); callers extract names from it.
    """
    pat = re.compile(re.escape(keyword) + r'\s*(?P<header>\([^)]*\))\s*\{')
    for m in pat.finditer(body):
        brace_pos = m.end() - 1
        inner, _end = brace_block(body, brace_pos)
        yield m.group("header"), inner


def header_name(header):
    """First identifier inside a group header's parentheses."""
    m = re.search(r'\(\s*"?(?P<n>[A-Za-z_][A-Za-z0-9_]*)', header)
    if not m:
        raise ValueError(f"cannot parse group header: {header!r}")
    return m.group("n")


def get_str(body, key):
    m = re.search(re.escape(key) + r'\s*:\s*"([^"]*)"', body)
    return m.group(1).strip() if m else None


def get_word(body, key):
    m = re.search(re.escape(key) + r'\s*:\s*([A-Za-z0-9_]+)', body)
    return m.group(1) if m else None


def edge_sens(cond):
    """Event-control term for an async clear/preset condition.

    The liberty gives the ACTIVE condition (e.g. "!RN"). Only simple
    single-signal conditions are supported; anything else fails closed.
    """
    m = re.fullmatch(r"!\s*([A-Za-z_][A-Za-z0-9_]*)", cond)
    if m:
        return f"negedge {m.group(1)}"
    m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)", cond)
    if m:
        return f"posedge {m.group(1)}"
    raise ValueError(f"async condition too complex for edge sensitivity: {cond!r}")


def verilog_expr(lib_expr):
    """Translate a .lib boolean expression to Verilog.

    Pin functions already use ! & | ^ (valid Verilog). ff next_state uses
    * for AND and + for OR, which are translated.
    """
    e = lib_expr.strip()
    # sanity: only known operators/parens/identifiers
    if re.search(r'[^A-Za-z0-9_!&|^~*+()\s]', e):
        raise ValueError(f"unsupported operator in expression: {e!r}")
    e = e.replace("*", "&").replace("+", "|")
    return e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=LIB_DEFAULT)
    ap.add_argument("--out", default="synth/nangate45_cells.v")
    args = ap.parse_args()

    with open(args.lib) as f:
        text = f.read()
    lib_sha = hashlib.sha256(text.encode()).hexdigest()

    cells = []   # (name, verilog_source)
    skipped = []  # (name, reason)

    for cheader, cbody in find_groups(text, "cell"):
        cell_name = header_name(cheader)
        # skip pg-only / filler / antenna / tap cells with no logic pins
        pins = []  # (name, direction, function, three_state)
        for pheader, pbody in find_groups(cbody, "pin"):
            pname = header_name(pheader)
            direction = get_word(pbody, "direction")
            if direction in (None, "internal"):
                continue
            func = get_str(pbody, "function")
            ts = get_str(pbody, "three_state")
            pins.append((pname, direction, func, ts))

        ff_info = None
        for _h, fbody in find_groups(cbody, "ff"):
            ff_info = {
                "next_state": get_str(fbody, "next_state"),
                "clocked_on": get_str(fbody, "clocked_on"),
                "clear": get_str(fbody, "clear"),
                "preset": get_str(fbody, "preset"),
            }
        latch_info = None
        for _h, lbody in find_groups(cbody, "latch"):
            latch_info = {
                "data_in": get_str(lbody, "data_in"),
                "enable": get_str(lbody, "enable"),
            }

        has_statetable = "statetable" in cbody

        try:
            if has_statetable:
                skipped.append((cell_name, "statetable (clock gate)"))
                continue
            if ff_info and ff_info["next_state"] is None:
                raise ValueError("ff without next_state")
            if not pins:
                skipped.append((cell_name, "no logic pins"))
                continue

            inputs = [p for p in pins if p[1] == "input"]
            outputs = [p for p in pins if p[1] == "output"]
            inouts = [p for p in pins if p[1] not in ("input", "output")]
            if inouts:
                raise ValueError(f"inout pins unsupported: {[p[0] for p in inouts]}")

            port_decls = []
            for pname, direction, _, _ in pins:
                port_decls.append(f"  input  wire {pname}" if direction == "input"
                                  else f"  output wire {pname}")
            ports = ",\n".join(port_decls)

            lines = [f"module {cell_name} ("]
            lines.append(ports)
            lines.append(");")

            if ff_info:
                ns = verilog_expr(ff_info["next_state"])
                ck = ff_info["clocked_on"]
                clr = verilog_expr(ff_info["clear"]) if ff_info["clear"] else None
                pre = verilog_expr(ff_info["preset"]) if ff_info["preset"] else None
                sens = [f"posedge {ck}"]
                if clr:
                    # clear/preset are given as active conditions, e.g. "!RN"
                    sens.append(edge_sens(clr))
                if pre:
                    sens.append(edge_sens(pre))
                lines.append("  reg IQ;")
                lines.append(f"  always @({ ' or '.join(sens) }) begin")
                if clr and pre:
                    lines.append(f"    if ({clr}) IQ <= 1'b0;")
                    lines.append(f"    else if ({pre}) IQ <= 1'b1;")
                    lines.append(f"    else IQ <= {ns};")
                elif clr:
                    lines.append(f"    if ({clr}) IQ <= 1'b0;")
                    lines.append(f"    else IQ <= {ns};")
                elif pre:
                    lines.append(f"    if ({pre}) IQ <= 1'b1;")
                    lines.append(f"    else IQ <= {ns};")
                else:
                    lines.append(f"    IQ <= {ns};")
                lines.append("  end")
                for pname, _, func, _ in outputs:
                    if func == "IQ":
                        lines.append(f"  assign {pname} = IQ;")
                    elif func == "IQN":
                        lines.append(f"  assign {pname} = ~IQ;")
                    else:
                        raise ValueError(f"ff output {pname} has unexpected function {func!r}")
            elif latch_info:
                d = latch_info["data_in"]
                g = latch_info["enable"]
                if not d or not g:
                    raise ValueError("latch without data_in/enable")
                lines.append("  reg IQ;")
                lines.append("  always @* begin")
                lines.append(f"    if ({g}) IQ = {d};")
                lines.append("  end")
                for pname, _, func, _ in outputs:
                    if func == "IQ":
                        lines.append(f"  assign {pname} = IQ;")
                    elif func == "IQN":
                        lines.append(f"  assign {pname} = ~IQ;")
                    else:
                        raise ValueError(f"latch output {pname} has unexpected function {func!r}")
            else:
                for pname, _, func, ts in outputs:
                    if func is None:
                        raise ValueError(f"output {pname} has no function")
                    e = verilog_expr(func)
                    if ts:
                        te = verilog_expr(ts)
                        lines.append(f"  assign {pname} = ({te}) ? ({e}) : 1'bz;")
                    else:
                        lines.append(f"  assign {pname} = {e};")

            lines.append("endmodule")
            lines.append("")
            cells.append((cell_name, "\n".join(lines)))
        except ValueError as ex:
            skipped.append((cell_name, str(ex)))

    header = f"""// nangate45_cells.v — ZERO-DELAY functional models of the Nangate45
// standard cells, for gate-level simulation ONLY (F2/F3). Not for synthesis.
// Auto-generated by synth/gen_cells.py from:
//   {args.lib}
//   sha256: {lib_sha}
// Combinational cells: continuous assigns from the liberty's pin functions.
// Sequential cells: behavioral always blocks from the ff/latch groups
// (async clear/preset modeled as active conditions from the liberty).
// No timing arcs are modeled: every gate sim using this file is ZERO-DELAY.
`timescale 1ns/1ps

"""
    with open(args.out, "w") as f:
        f.write(header)
        for _name, src in cells:
            f.write(src)

    print(f"gen_cells: wrote {len(cells)} cell models to {args.out}")
    if skipped:
        print(f"gen_cells: skipped {len(skipped)} cells:")
        for name, reason in skipped:
            print(f"  {name}: {reason}")


if __name__ == "__main__":
    sys.exit(main())

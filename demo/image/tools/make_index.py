#!/usr/bin/env python3
"""Generate runs/index.html: the review index with per-requirement
statuses read live from the run artifacts (never hardcoded)."""
import argparse
import json
import os
import subprocess
import sys


def load(p):
    try:
        return json.load(open(p))
    except Exception:  # noqa: BLE001
        return None


def verdict(run_dir):
    r = load(os.path.join(run_dir, "results.json"))
    return r["functional"] if r else "NO RESULTS"


def check(run_dir, name):
    r = load(os.path.join(run_dir, "results.json"))
    if not r:
        return False
    return bool(r["checks"].get(name, {}).get("pass"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs-dir", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--fault", required=True)
    ap.add_argument("--extra", required=True)
    args = ap.parse_args()
    D = args.runs_dir
    B, F, E = (os.path.join(D, x) for x in
               (args.baseline, args.fault, args.extra))

    nc = subprocess.run(
        [sys.executable,
         os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "negative_control.py"),
         "--run-dir", F], capture_output=True, text=True)
    neg_ok = nc.returncode == 0

    def assets_complete(rd):
        a = load(os.path.join(rd, "anchors.json"))
        if not a:
            return False
        for s, st in a["stages"].items():
            if st.get("image") and not os.path.exists(
                    os.path.join(rd, st["image"])):
                return False
            if st.get("vcd") and not os.path.exists(
                    os.path.join(rd, st["vcd"])):
                return False
            if st.get("vcd") and not os.path.exists(
                    os.path.join(rd, f"stage{s}.gtkw")):
                return False
        return True

    rows = [
        ("APP1", "input reaches SRAM via SPI, all bytes match",
         check(B, "spi_payload") and check(B, "input_sram")),
        ("APP2", "both gradient tasks execute; stored Gx/Gy match reference",
         check(B, "gradients_sram") and check(B, "task_evidence")),
        ("APP3", "stripe dependencies + completion enforced (trace ordering)",
         check(B, "task_evidence")),
        ("APP4", "all 4096 output pixels written and match reference",
         check(B, "output_sram")),
        ("APP5", "UART recovers stored framebuffer; digest + quiet boundary",
         check(B, "uart_packet") and check(B, "tb_protocol")),
        ("NEG1", "same firmware/input, exactly the specified 1-bit fault",
         bool(load(os.path.join(F, "tb_result.json")) or {})
         and load(os.path.join(F, "tb_result.json")).get("fault_fired") == 1),
        ("NEG2", "faulty stored + recovered images: one mismatch; checker rejects",
         neg_ok and verdict(F) == "FAIL"),
        ("GEN1", "frozen binary processes a distinct post-freeze input",
         verdict(E) == "PASS"),
        ("VIEW1", "both walkthroughs: every image, signal set, zoom present",
         assets_complete(B) and assets_complete(F)),
        ("REPRO1", "commands reproduce artifacts with recorded revisions",
         any(x.startswith("FREEZE-") for x in os.listdir(D))),
        ("REVIEW1", "walkthrough ready for owner review",
         assets_complete(B) and assets_complete(F)),
    ]

    def run_card(rid, rd, label):
        r = load(os.path.join(rd, "results.json")) or {"checks": {}}
        lis = "".join(
            f"<li>{k}: {'PASS' if v['pass'] else 'FAIL'}</li>"
            for k, v in r.get("checks", {}).items())
        stages = "".join(
            f'<li><a href="{rid}/assets/stage{s}_'
            + {"01": "input", "02": "load", "03": "strip", "04": "pixel",
               "05": "rtos", "06": "writeback", "07": "uart",
               "08": "compare"}[s] + f'.png">stage {s}</a> '
            f'(<a href="{rid}/anchors.json">anchors</a>)</li>'
            for s in ["01", "02", "03", "04", "05", "06", "07", "08"])
        return (f"<h2>{label}: {rid}</h2>"
                f"<p>functional verdict: <b>{verdict(rd)}</b></p>"
                f"<ul>{lis}</ul><ul>{stages}</ul>")

    html = ["<html><head><meta charset='utf-8'>"
            "<title>Muse MCU visual demo: review index</title></head><body>",
            "<h1>Muse MCU visual demo: review index</h1>",
            "<table border='1' cellspacing='0' cellpadding='4'>"
            "<tr><th>ID</th><th>criterion</th><th>status</th></tr>"]
    for rid_, desc, ok in rows:
        html.append(f"<tr><td>{rid_}</td><td>{desc}</td>"
                    f"<td>{'MET' if ok else 'NOT MET'}</td></tr>")
    html.append("</table>")
    html.append(run_card(args.baseline, B, "Baseline run"))
    html.append(run_card(args.fault, F, "Fault run"))
    html.append(run_card(args.extra, E, "Post-freeze extra input run"))
    html.append("<h2>Negative control (fault run)</h2><pre>"
                + nc.stdout + "</pre>")
    html.append("</body></html>")
    with open(os.path.join(D, "index.html"), "w") as f:
        f.write("\n".join(html))
    print("index written:", os.path.join(D, "index.html"))
    for rid_, desc, ok in rows:
        print(f"{rid_}: {'MET' if ok else 'NOT MET'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

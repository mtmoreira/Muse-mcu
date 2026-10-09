#!/usr/bin/env python3
"""Overnight watchdog for the Muse MCU project.

Ground-truth check on ~/workspace/Muse-mcu: is work still progressing,
is it stalled, or is a final report present (and does its evidence hold up)?

Outputs a JSON verdict on stdout:
  IN_PROGRESS - recent activity (sims running, fresh logs, recent commits)
  STALLED     - no activity for >90 min and no final report
  NEEDS_WORK  - final report exists but is incomplete (FAIL/BLOCKED/<31 PASS)
  COMPLETE    - final report exists with >=31 PASS and no FAIL/BLOCKED

COMPLETE still requires the caller to verify each claimed PASS against its
evidence file before believing it.
"""
import os, json, subprocess, time, glob, re

ROOT = os.path.expanduser("~/workspace/Muse-mcu")
NOW = time.time()
IDLE_S = 5400  # 90 minutes


def mtime(p):
    try:
        return os.path.getmtime(p)
    except OSError:
        return 0


def main():
    info = {"root": ROOT, "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S")}

    # Final report candidates
    report = None
    for c in ("results/ACCEPTANCE_REPORT.md", "results/acceptance_report.md",
              "results/FINAL_REPORT.md", "results/report.md"):
        p = os.path.join(ROOT, c)
        if os.path.exists(p):
            report = p
            break
    info["final_report"] = report

    # Last commit time
    git_ts = 0
    try:
        out = subprocess.run(["git", "-C", ROOT, "log", "-1", "--format=%ct"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        git_ts = int(out) if out.isdigit() else 0
    except Exception:
        pass
    info["last_commit_age_min"] = round((NOW - git_ts) / 60, 1) if git_ts else None

    # Recently written logs
    recent_logs = []
    for pat in ("tb/logs/*.log", "results/raw/**/*.log", "results/**/*.log",
                "fw/build/*.log", "synth/*.log"):
        for f in glob.glob(os.path.join(ROOT, pat), recursive=True):
            if NOW - mtime(f) < IDLE_S:
                recent_logs.append(os.path.relpath(f, ROOT))
    info["recent_logs"] = recent_logs[:20]
    info["recent_log_count"] = len(recent_logs)

    # Simulations actually running
    sims = False
    try:
        ps = subprocess.run(["ps", "aux"], capture_output=True, text=True, timeout=30).stdout
        for line in ps.splitlines():
            low = line.lower()
            if ("vvp" in low or "iverilog" in low) and "grep" not in low and "watchdog" not in low:
                sims = True
                break
    except Exception:
        pass
    info["sims_running"] = sims

    alive = sims or (git_ts and NOW - git_ts < IDLE_S) or len(recent_logs) > 0
    info["alive"] = alive

    verdict = "IN_PROGRESS"
    verdicts = {}
    if report:
        txt = open(report, encoding="utf-8", errors="replace").read()
        for m in re.finditer(
                r"\b(A\d+|B\d+|C1|D\d+|E1|F\d+|G\d+|R\d+|DEMO1|FIG1|FIG2)\b[^\n]{0,80}?\b(PASS|FAIL|BLOCKED|NOT APPLICABLE)\b",
                txt):
            verdicts[m.group(1)] = m.group(2)
        info["report_verdicts"] = verdicts
        npass = sum(1 for v in verdicts.values() if v == "PASS")
        nbad = sum(1 for v in verdicts.values() if v in ("FAIL", "BLOCKED"))
        info["pass_count"] = npass
        info["fail_blocked_count"] = nbad
        verdict = "COMPLETE" if (nbad == 0 and npass >= 31) else "NEEDS_WORK"
    elif not alive:
        verdict = "STALLED"

    try:
        sha = subprocess.run(["git", "-C", ROOT, "log", "-1", "--format=%H"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        info["head_sha"] = sha
    except Exception:
        info["head_sha"] = None

    info["verdict"] = verdict
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()

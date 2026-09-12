"""Time coreval, and optionally CDISC's engine, on the same study.

    python data-raw/benchmark/benchmark.py <studies-dir> [scale ...]
        [--engine <path-to-cdisc-rules-engine>] [--python <interpreter>]

Measures WALL CLOCK from outside the process and samples RSS across the whole
process tree, because both tools spend real time starting up and the engine
spawns workers. A number taken from inside R with system.time() excludes R's
own start-up and package load, which is around 35 seconds on a half-million-row
study, so it is not comparable and is not what this reports.

Build the studies first:

    python data-raw/benchmark/make_study.py bench-studies

Then:

    python data-raw/benchmark/benchmark.py bench-studies s10 s100

Needs psutil. The engine half needs a checkout of cdisc-org/cdisc-rules-engine
with its dependencies installed; without --engine only coreval is timed.
"""

import argparse
import io
import json
import os
import subprocess
import sys
import threading
import time

try:
    import psutil
except ImportError:
    sys.exit("psutil is required: pip install psutil")


def run(cmd, cwd, env, timeout=7200):
    """Wall clock and peak RSS of a command, including its children."""
    peak = 0
    started = time.time()
    proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    handle = psutil.Process(proc.pid)
    stop = threading.Event()

    def sample():
        nonlocal peak
        while not stop.is_set():
            try:
                rss = handle.memory_info().rss
                for child in handle.children(recursive=True):
                    try:
                        rss += child.memory_info().rss
                    except psutil.Error:
                        pass
                peak = max(peak, rss)
            except psutil.Error:
                return
            time.sleep(0.2)

    watcher = threading.Thread(target=sample, daemon=True)
    watcher.start()
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        out = "TIMEOUT"
    stop.set()
    return time.time() - started, peak / 1e6, out or ""


def time_coreval(study, package_root, rscript):
    script = os.path.join(package_root, "bench-coreval.R")
    io.open(script, "w", encoding="utf-8", newline="\n").write(
        'suppressMessages(devtools::load_all(%r, quiet = TRUE))\n'
        'res <- check_study(%r, standard = "SDTMIG", version = "3.4")\n'
        'cat("FINDINGS", nrow(res$findings), "CHECKS", attr(res, "checks_run"), "\\n")\n'
        % (package_root.replace("\\", "/"), study.replace("\\", "/"))
    )
    try:
        elapsed, peak, out = run([rscript, script], package_root, os.environ.copy())
    finally:
        if os.path.exists(script):
            os.remove(script)
    findings = next((l for l in out.splitlines() if l.startswith("FINDINGS")), out[-80:])
    return elapsed, peak, findings


def time_engine(study, engine_root, python_exe):
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    out_base = os.path.join(os.path.abspath(study), "..", "engine-report")
    cmd = [python_exe, "core.py", "validate", "-d", os.path.abspath(study),
           "-dep", os.path.join(os.path.abspath(study), ".env"),
           "-s", "SDTMIG", "-v", "3-4", "-of", "JSON", "-o", out_base,
           "-p", "disabled", "-l", "disabled"]
    elapsed, peak, _ = run(cmd, engine_root, env)
    detail = ""
    report = out_base + ".json"
    if os.path.exists(report):
        data = json.load(io.open(report, encoding="utf-8"))
        issues = sum(i.get("issues", 0) for i in data.get("Issue_Summary", []))
        detail = "self-reported %s, issues %d" % (
            data.get("Conformance_Details", {}).get("Total_Runtime", "?"), issues)
    return elapsed, peak, detail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("studies")
    ap.add_argument("scales", nargs="*", default=["s1", "s10", "s100"])
    ap.add_argument("--engine", help="path to a cdisc-rules-engine checkout")
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--rscript", default="Rscript")
    ap.add_argument("--package", default=os.getcwd())
    args = ap.parse_args()

    for scale in args.scales:
        study = os.path.join(args.studies, scale)
        if not os.path.isdir(study):
            print("%-6s missing, build it with make_study.py" % scale)
            continue
        rows = sum(
            sum(1 for _ in io.open(os.path.join(study, f), encoding="utf-8-sig")) - 1
            for f in os.listdir(study)
            if f.endswith(".csv") and not f.startswith("_")
        )
        print("\n=== %s: %d data rows" % (scale, rows))

        elapsed, peak, detail = time_coreval(study, args.package, args.rscript)
        print("  %-12s %8.1fs  peak %6.0f MB  %s" % ("coreval", elapsed, peak, detail))

        if args.engine:
            elapsed, peak, detail = time_engine(study, args.engine, args.python)
            print("  %-12s %8.1fs  peak %6.0f MB  %s" % ("CORE engine", elapsed, peak, detail))


if __name__ == "__main__":
    main()

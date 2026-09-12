"""Run CDISC's engine over chosen rules and record engine vs committed sheet.

    python tests/conformance/compare_engine.py [rule-id ...]

With no arguments it runs every rule the scoreboard marks FAIL. Writes
tests/conformance/engine_comparison.json: one entry per rule per test case,
holding what the engine reported and what the committed results.csv says.

Dev tooling only. Not part of the package, not run by R CMD check, and
Rbuildignored with the rest of tests/conformance.

Why this exists: a verdict of "the answer sheet is stale, not our bug" was
being carried in prose, from an engine run nobody could repeat. The rule here
is the same one the rest of this repository follows: a verdict needs a
mechanical proof. This produces one, as a file, on demand.

Setup, once (the clone is gitignored, so this stays out of the package):

    cd data-raw/upstream/cdisc-rules-engine
    python -m venv .venv
    .venv/Scripts/python -m pip install -e .        # POSIX: .venv/bin/python

A fixture with no .env cannot be run. That is not this script failing: CDISC's
own test.py requires one too, so for those rules the reference cannot
arbitrate at all. Those are reported as engine=null with a note, and must
never be counted as agreement. Reading "no disagreement" off a rule the engine
never ran is the vacuous-truth version of the silent-failure bug this package
keeps finding in itself.
"""

import collections
import csv
import glob
import io
import json
import os
import subprocess
import sys

ENGINE = os.path.join("data-raw", "upstream", "cdisc-rules-engine")
UPSTREAM = os.path.join("data-raw", "upstream", "cdisc-open-rules")
SCOREBOARD = os.path.join("tests", "conformance", "scoreboard.csv")
OUTPUT = os.path.join("tests", "conformance", "engine_comparison.json")
ROOT = {
    "published": "Published",
    "deprecated_dir": "Deprecated",
    "fda_business_rules_draft": "Unpublished/FDA Business Rules",
    "sdtmig_draft": "Unpublished/SDTMIG",
    "sendig_draft": "Unpublished/SENDIG",
}


def engine_python():
    for rel in (("Scripts", "python.exe"), ("bin", "python")):
        path = os.path.join(ENGINE, ".venv", *rel)
        if os.path.isfile(path):
            return path
    sys.exit("No engine venv. See the setup block at the top of this file.")


def records(path):
    """{dataset: [record, ...]} from a results.csv, or None if absent.

    Rows with a blank Variable are CDISC's placeholders ("this dataset was
    looked at and had nothing") and are not findings. A blank Record with a
    real Variable is a dataset-level finding and is kept as "".
    """
    if not os.path.isfile(path):
        return None
    rows = list(csv.DictReader(io.open(path, encoding="utf-8-sig")))
    found = collections.defaultdict(set)
    for row in rows:
        if (row.get("Variable") or "").strip():
            found[(row.get("Dataset") or "").strip()].add((row.get("Record") or "").strip())
    return {k: sorted(v, key=lambda s: (s == "", int(s) if s.isdigit() else 0))
            for k, v in found.items()}


def case_dirs(rule_dir):
    out = []
    for polarity in ("positive", "negative"):
        base = os.path.join(rule_dir, polarity)
        if not os.path.isdir(base):
            continue
        if os.path.isdir(os.path.join(base, "data")):
            out.append(base)
        else:
            out.extend(sorted(d for d in glob.glob(os.path.join(base, "*")) if os.path.isdir(d)))
    return out


def env_file(data_dir):
    direct = os.path.join(data_dir, ".env")
    if os.path.isfile(direct):
        return direct
    return next(iter(glob.glob(os.path.join(data_dir, "*.env"))), None)


def main():
    python = engine_python()
    board = {r["id"]: r for r in csv.DictReader(io.open(SCOREBOARD, encoding="utf-8-sig"))}
    # The scoreboard has no upstream folder, and a rule's folder is not always
    # its id: FDA.SENDIG.FB6507's data lives in FB6507, beside a same-named
    # directory holding only a rule.yml. Find the folder that has the cases.
    wanted = sys.argv[1:] or [k for k, v in board.items() if v["status"] == "FAIL"]
    report, scratch = {}, os.path.join("tests", "conformance", ".engine-out")
    os.makedirs(scratch, exist_ok=True)

    for rule_id in wanted:
        source = board[rule_id]["source"]
        root = os.path.join(UPSTREAM, ROOT[source])
        folder = next((c for c in (rule_id, rule_id.split(".")[-1])
                       if case_dirs(os.path.join(root, c))), rule_id)
        rule_dir = os.path.join(root, folder)
        ymls = glob.glob(os.path.join(rule_dir, "*.yml"))
        if not ymls:
            print("%-22s no rule.yml at %s" % (rule_id, rule_dir))
            continue

        cases = []
        for case in case_dirs(rule_dir):
            label = os.path.relpath(case, rule_dir).replace("\\", "/")
            data = os.path.join(case, "data")
            sheet = records(os.path.join(case, "results", "results.csv"))
            env = env_file(data)
            if env is None:
                cases.append({"case": label, "engine": None, "sheet": sheet,
                              "note": "fixture ships no .env; CDISC's own test.py requires one"})
                continue
            out = os.path.join(scratch, ("%s_%s" % (rule_id, label)).replace("/", "_"))
            run = subprocess.run(
                [python, "core.py", "validate", "-lr", os.path.abspath(ymls[0]),
                 "-d", os.path.abspath(data), "-dep", os.path.abspath(env),
                 "-of", "CSV", "-o", os.path.abspath(out),
                 "-p", "disabled", "-l", "disabled"],
                cwd=ENGINE, capture_output=True, text=True, timeout=1800,
                env={**os.environ, "PYTHONIOENCODING": "utf-8"})
            engine = records(out + ".csv")
            note = None
            if engine is None:
                note = "engine wrote no output: " + ((run.stdout or "") + (run.stderr or ""))[-200:]
            cases.append({"case": label, "engine": engine, "sheet": sheet, "note": note})

        ran = [c for c in cases if c["engine"] is not None]
        differ = [c for c in ran if c["engine"] != c["sheet"]]
        report[rule_id] = {"source": source, "folder": folder, "cases": cases,
                           "cases_engine_ran": len(ran), "cases_engine_differs": len(differ)}
        # Never collapse "ran and agreed" with "never ran" into one word.
        verdict = ("engine could not run any case" if not ran else
                   "engine differs from sheet on %d of %d" % (len(differ), len(ran)) if differ else
                   "engine agrees with sheet on all %d" % len(ran))
        print("%-22s %-26s %s" % (rule_id, source, verdict))

    json.dump(report, io.open(OUTPUT, "w", encoding="utf-8"), indent=1, sort_keys=True)
    never = sum(1 for v in report.values() if v["cases_engine_ran"] == 0)
    print("\n%d rules; the engine could not run any case for %d of them" % (len(report), never))
    print("wrote", OUTPUT)


if __name__ == "__main__":
    main()

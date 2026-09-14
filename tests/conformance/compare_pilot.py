"""Compare CDISC's engine and coreval on the same study, rule by rule.

    python tests/conformance/compare_pilot.py <engine report.json> <coreval out-dir>

The engine report is its raw JSON output (`-of json -rr`); the coreval
directory is what tests/conformance/pilot_study.R writes. Every rule the engine
reports on is put in exactly one category, and each disagreement is listed
with the records only one side flagged.

The categories are the point. "The two disagree" is not a verdict. A rule can
disagree because coreval is wrong, because the engine is wrong, because the
engine crashed, or because one side runs a rule the other deliberately does
not. docs/REAL-STUDY.md records which was which for the pilot.

Dev tooling only. Not part of the package, not run by R CMD check, and
Rbuildignored with the rest of tests/conformance.
"""

import collections
import csv
import io
import json
import os
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    report, cv_dir = sys.argv[1], sys.argv[2]
    eng = json.load(io.open(report, encoding="utf-8"))

    status = {r["core_id"]: r["status"] for r in eng["Rules_Report"]}
    crashes = collections.defaultdict(set)
    for x in eng["Issue_Summary"]:
        if "error" in (x.get("message") or "").lower():
            crashes[x["core_id"]].add(x["message"][:100])

    engine = collections.defaultdict(set)
    for x in eng["Issue_Details"]:
        row = x.get("row")
        engine[x["core_id"]].add(((x.get("dataset") or "").upper(),
                                  "" if row in (None, "") else str(row)))

    def read(name):
        return list(csv.DictReader(io.open(os.path.join(cv_dir, name), encoding="utf-8")))

    coreval = collections.defaultdict(set)
    for r in read("coreval_findings.csv"):
        rec = r["Record"]
        coreval[r["rule_id"]].add((r["Dataset"].upper(), "" if rec in ("", "NA") else rec))
    skipped = collections.defaultdict(set)
    for r in read("coreval_skipped.csv"):
        skipped[r["rule_id"]].add(r["reason"][:100])
    retired = {r["id"] for r in read("coreval_rules.csv") if r["source"] == "deprecated_dir"}

    cats = collections.defaultdict(list)
    for rid, st in sorted(status.items()):
        e, c = engine.get(rid, set()), coreval.get(rid, set())
        if st == "EXECUTION ERROR":
            key = "engine crashed; coreval " + ("found problems" if c else "found none")
        elif st == "SKIPPED":
            key = "engine: not applicable" + ("; coreval found problems" if c else "")
        elif rid in retired and not c:
            key = "retired rule: engine runs it, coreval does not by default"
        elif rid in skipped and not c:
            key = "coreval could not run it; engine ran"
        elif e == c:
            key = "agree" + (" (both found problems)" if e else " (both clean)")
        elif e and not c:
            key = "differ: only the engine found problems"
        elif c and not e:
            key = "differ: only coreval found problems"
        else:
            key = "differ: both found problems, not the same records"
        cats[key].append(rid)

    print("engine rules reported:", len(status))
    for key in sorted(cats):
        print("\n%s: %d" % (key, len(cats[key])))
        for rid in cats[key]:
            e, c = engine.get(rid, set()), coreval.get(rid, set())
            detail = ""
            if key.startswith("differ") or key.startswith("retired"):
                detail = "  engine %d, coreval %d, shared %d" % (len(e), len(c), len(e & c))
            elif key.startswith("engine crashed"):
                detail = "  " + "; ".join(sorted(crashes.get(rid, set())))
            elif key.startswith("coreval could not"):
                detail = "  " + "; ".join(sorted(skipped[rid]))
            print("   %s%s" % (rid, detail))

    not_in_engine = sorted(set(coreval) - set(status))
    if not_in_engine:
        print("\ncoreval found problems for rules the engine did not run:", ", ".join(not_in_engine))


if __name__ == "__main__":
    main()

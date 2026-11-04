"""Turn a CORE 1.0 engine report into the shape compare_pilot.py reads.

    python tests/conformance/core1_report.py <1.0 report.json> <out.json>
    python tests/conformance/compare_pilot.py <out.json> <coreval out-dir>

verisianHQ/cdisc-rules-engine writes its raw JSON report (`-of JSON -rr`) as
`results_data`: one entry per rule, each with one result per dataset. CDISC's
engine writes `Rules_Report`, `Issue_Summary` and `Issue_Details`, which is
what compare_pilot.py was written against. This writes those three from the
1.0 report, and keeps `results_data` as it is, since compare_pilot.py also
reads the per-dataset skips from it.

A rule's status is EXECUTION ERROR when any dataset errored, SKIPPED when
every dataset was skipped, and SUCCESS otherwise.

Dev tooling only. Not part of the package, not run by R CMD check, and
Rbuildignored with the rest of tests/conformance.
"""

import io
import json
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    report = json.load(io.open(sys.argv[1], encoding="utf-8"))
    rules, summary, details = [], [], []
    for rule in report["results_data"]:
        results = rule.get("results") or []
        statuses = [r.get("executionStatus") for r in results]
        if "execution_error" in statuses:
            status = "EXECUTION ERROR"
        elif statuses and all(s == "skipped" for s in statuses):
            status = "SKIPPED"
        else:
            status = "SUCCESS"
        rules.append({"core_id": rule["id"], "status": status})
        for result in results:
            if result.get("executionStatus") == "execution_error":
                text = "; ".join(e.get("message") or e.get("error") or "" for e in result.get("errors") or [])
                summary.append({"core_id": rule["id"], "message": "execution error: " + text})
            if result.get("executionStatus") != "success":
                continue
            for error in result.get("errors") or []:
                # "ae.xpt" -> "AE", the dataset name coreval reports.
                dataset = (error.get("dataset") or result.get("dataset") or "").rsplit(".", 1)[0]
                details.append({"core_id": rule["id"], "dataset": dataset.upper(), "row": error.get("row")})
    out = {
        "Rules_Report": rules,
        "Issue_Summary": summary,
        "Issue_Details": details,
        "results_data": report["results_data"],
    }
    json.dump(out, io.open(sys.argv[2], "w", encoding="utf-8"))
    print(len(rules), "rules,", len(details), "findings")


if __name__ == "__main__":
    main()

"""Build scaled but VALID SDTM studies for benchmarking.

    python data-raw/benchmark/make_study.py <output-dir> [scale ...]

Starts from a real CDISCPILOT-shaped fixture in the pinned rules clone
(AE 1,616 rows x 27 variables, VS 1,776 x 20, DM 100 x 22, SUPPAE 1,616 x 10,
plus three trial-design datasets) and scales it by REPLICATING SUBJECTS.

Replicating subjects, not rows, is the whole point. Every replica gets its own
USUBJID, so --SEQ stays unique within a subject and no duplicate-key violation
is manufactured. A benchmark study full of invented violations measures how
fast a tool writes findings, not how fast it checks data. Rows with no USUBJID
(the trial design datasets) are copied once.

Scales are given as subject multipliers. The defaults build:

    s1     100 subjects      5,115 rows
    s10  1,000 subjects     51,105 rows
    s100 10,000 subjects   511,117 rows
"""

import csv
import glob
import io
import os
import shutil
import sys

# One of CDISC's own fixtures, in the clone data-raw/ already needs.
BASE = os.path.join(
    "data-raw", "upstream", "cdisc-open-rules",
    "Published", "CORE-000042", "negative", "01", "data",
)

DEFAULT_SCALES = [("s1", 1), ("s10", 10), ("s100", 100)]


def build(out_dir, replicas):
    """Write one scaled copy of the base study. Returns its total row count."""
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)

    total = 0
    sources = sorted(glob.glob(os.path.join(BASE, "*.csv")))
    sources += glob.glob(os.path.join(BASE, ".env"))
    for src in sources:
        name = os.path.basename(src)
        if name == ".env":
            shutil.copy(src, os.path.join(out_dir, name))
            continue

        with io.open(src, encoding="utf-8-sig", newline="") as fh:
            reader = csv.DictReader(fh)
            fields = reader.fieldnames
            rows = list(reader)

        # Metadata files and trial design carry no subject, so one copy each.
        per_subject = rows and fields and "USUBJID" in fields and not name.startswith("_")
        if not per_subject:
            out_rows = rows
        else:
            out_rows = []
            for k in range(replicas):
                suffix = "" if k == 0 else "-R%d" % k
                for row in rows:
                    copy = dict(row)
                    copy["USUBJID"] = row["USUBJID"] + suffix
                    out_rows.append(copy)

        with io.open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=fields)
            writer.writeheader()
            writer.writerows(out_rows)
        total += len(out_rows)

    return total


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = sys.argv[1]
    if not os.path.isdir(BASE):
        sys.exit(
            "Base fixture not found: %s\n"
            "Clone cdisc-org/cdisc-open-rules into data-raw/upstream/ first." % BASE
        )

    scales = DEFAULT_SCALES
    if len(sys.argv) > 2:
        scales = [("s%s" % n, int(n)) for n in sys.argv[2:]]

    os.makedirs(root, exist_ok=True)
    for label, replicas in scales:
        out = os.path.join(root, label)
        rows = build(out, replicas)
        print("%-6s %6d subjects  %8d rows  -> %s"
              % (label, replicas * 100, rows, out))


if __name__ == "__main__":
    main()

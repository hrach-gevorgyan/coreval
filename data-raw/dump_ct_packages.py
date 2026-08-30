"""Dump the list of CDISC Controlled Terminology package dates to CSV.

Only the package TYPE and DATE, not the terminology itself: the full CT term
data in the cache is ~438 MB across 206 files, far too large to bundle in a
CRAN package (that would be a separate data package). The date list alone is
a few hundred bytes and is all the `valid_codelist_dates` operation needs -
it checks whether a study cites a CT version that CDISC actually published.

Reads the offline cache cdisc-org/cdisc-rules-engine commits to git; no CDISC
API is contacted. Build time only.

    python data-raw/dump_ct_packages.py
"""

import csv
import glob
import os
import re
import sys

CACHE_DIR = os.path.join(
    "data-raw", "upstream", "cdisc-rules-engine", "resources", "cache"
)
OUT = os.path.join("data-raw", "ct_packages.csv")


def main():
    files = glob.glob(os.path.join(CACHE_DIR, "*ct-*.pkl"))
    if not files:
        sys.exit("No CT package files found under %s" % CACHE_DIR)

    rows = []
    for path in files:
        base = os.path.basename(path)
        match = re.match(r"^(.*?)ct-(\d{4}-\d{2}-\d{2})\.pkl$", base)
        if not match:
            continue
        rows.append({"package_type": match.group(1).upper(), "package_date": match.group(2)})

    rows.sort(key=lambda r: (r["package_type"], r["package_date"]))

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=["package_type", "package_date"])
        writer.writeheader()
        writer.writerows(rows)

    types = sorted({r["package_type"] for r in rows})
    print("wrote %s: %d packages across %d types" % (OUT, len(rows), len(types)))
    print("types: %s" % ", ".join(types))


if __name__ == "__main__":
    main()

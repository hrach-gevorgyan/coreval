"""Dump each standard's DATASET LABELS to CSV for data-raw/dataset_labels.R.

Reads the offline, MIT-licensed cache that cdisc-org/cdisc-rules-engine
commits to git (resources/cache/standards_details.pkl) and flattens it to one
row per (standard, version, domain).

Why this is needed: the `domain_label` operation must return the label the
STANDARD gives a domain, not the label the study's own metadata happens to
carry. The reference reads it from exactly this cache
(operations/domain_label.py -> standard_metadata -> classes -> datasets ->
label). SENDIG calls LB "Laboratory" where SDTMIG calls it "Laboratory Test
Results", and CORE-000272 compares --CAT against that label, so taking the
study's own label answers a different question.

No CDISC API is contacted. Build time only; the package never needs Python.

    python data-raw/dump_dataset_labels.py
"""

import csv
import os
import pickle
import sys

CACHE = os.path.join(
    "data-raw", "upstream", "cdisc-rules-engine",
    "resources", "cache", "standards_details.pkl",
)
OUT = os.path.join("data-raw", "dataset_labels.csv")
PREFIX = "standards/"


def main():
    if not os.path.exists(CACHE):
        sys.exit(
            "Cache not found: %s\n"
            "Clone cdisc-org/cdisc-rules-engine into data-raw/upstream/ first." % CACHE
        )

    with open(CACHE, "rb") as fh:
        cache = pickle.load(fh)

    rows = []
    for key in sorted(cache):
        if not key.startswith(PREFIX):
            continue
        # "standards/sdtmig/3-4"        -> sdtmig, 3-4
        # "standards/tig/1-0/sdtm"      -> tig-sdtm, 1-0
        parts = key[len(PREFIX):].split("/")
        if len(parts) == 2:
            standard, version = parts
        elif len(parts) == 3:
            standard, version = "%s-%s" % (parts[0], parts[2]), parts[1]
        else:
            continue
        for cls in cache[key].get("classes") or []:
            for ds in cls.get("datasets") or []:
                name = (ds.get("name") or "").strip()
                label = (ds.get("label") or "").strip()
                if name and label:
                    rows.append({
                        "standard": standard,
                        "version": version,
                        "domain": name,
                        "label": label,
                    })

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["standard", "version", "domain", "label"])
        w.writeheader()
        w.writerows(rows)

    print("wrote %s: %d rows" % (OUT, len(rows)))
    print("standards: %s" % ", ".join(sorted({r["standard"] for r in rows})))


if __name__ == "__main__":
    main()

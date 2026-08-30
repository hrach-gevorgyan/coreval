"""Dump SDTM Model class-variable metadata to CSV for data-raw/model_variables.R.

Reads the offline, MIT-licensed cache that cdisc-org/cdisc-rules-engine
commits directly to git (resources/cache/standards_models.pkl). No CDISC API
is contacted; that project's API path is only used to refresh this cache.

    python data-raw/dump_model_variables.py

Writes data-raw/model_variables.csv. Build time only - the package itself
never needs Python.
"""

import csv
import os
import pickle
import sys

CACHE = os.path.join(
    "data-raw", "upstream", "cdisc-rules-engine",
    "resources", "cache", "standards_models.pkl",
)
OUT = os.path.join("data-raw", "model_variables.csv")

# The newest SDTM Model, used as a superset. A variable's class membership
# and datatype are stable across Model versions in a way per-IG variable
# metadata is not, so this is not versioned - the same simplification
# domain_classes.R documents.
MODEL_KEY = "models/sdtm/2-1"


def main():
    if not os.path.exists(CACHE):
        sys.exit(
            "Cache not found: %s\n"
            "Clone cdisc-org/cdisc-rules-engine into data-raw/upstream/ first."
            % CACHE
        )

    with open(CACHE, "rb") as fh:
        cache = pickle.load(fh)

    if MODEL_KEY not in cache:
        sys.exit("Model key %r not in cache. Available: %s"
                 % (MODEL_KEY, sorted(k for k in cache if "sdtm" in k)))

    model = cache[MODEL_KEY]
    rows = []
    for cls in model.get("classes") or []:
        class_name = cls.get("name", "")
        for var in cls.get("classVariables") or []:
            rows.append({
                "class": class_name,
                "variable": var.get("name", ""),
                "label": var.get("label", "") or "",
                "role": var.get("role", "") or "",
                "type": var.get("simpleDatatype", "") or "",
                "ordinal": var.get("ordinal", "") or "",
            })

    rows = [r for r in rows if r["variable"]]

    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh, fieldnames=["class", "variable", "label", "role", "type", "ordinal"]
        )
        writer.writeheader()
        writer.writerows(rows)

    classes = sorted({r["class"] for r in rows})
    templated = sum(1 for r in rows if r["variable"].startswith("--"))
    print("wrote %s: %d rows (%d '--' templates)" % (OUT, len(rows), templated))
    print("classes: %s" % ", ".join(classes))


if __name__ == "__main__":
    main()

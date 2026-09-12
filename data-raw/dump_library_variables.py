"""Dump CDISC Library variable metadata to CSV for data-raw/library_variables.R.

Reads the offline, MIT-licensed cache that cdisc-org/cdisc-rules-engine
commits directly to git (resources/cache/variables_metadata.pkl) and flattens
it to one row per (standard, version, domain, variable).

No CDISC API is contacted. The cache is a plain pickle in the cloned repo;
this script only reads it. Re-run only when that clone is refreshed.

    python data-raw/dump_library_variables.py

Writes data-raw/library_variables.csv. This runs at BUILD time only - the
package itself never needs Python.
"""

import csv
import os
import pickle
import sys

CACHE = os.path.join(
    "data-raw", "upstream", "cdisc-rules-engine",
    "resources", "cache", "variables_metadata.pkl",
)
OUT = os.path.join("data-raw", "library_variables.csv")

PREFIX = "library_variables_metadata/"

# Fields the rules actually reference, mapped to the column names used on the
# R side. `simpleDatatype` is the Library's own name for what CORE rules call
# library_variable_data_type.
FIELDS = [
    ("core", "core"),
    ("ordinal", "ordinal"),
    ("label", "label"),
    ("role", "role"),
    ("simpleDatatype", "type"),
]

# `ccode` is not a field on the variable - it is the last segment of the
# codelist link the Library attaches to it, e.g.
# "/mdr/root/ct/sendct/codelists/C66770" -> "C66770". Derived exactly as the
# reference engine's base_dataset_builder does: the FIRST codelist link, or
# "" when the variable has none. Only the presence of a codelist is a fact
# about the variable; which terms are in it is Controlled Terminology, which
# is far too large to bundle and stays out.
def codelist_ccode(meta):
    links = meta.get("_links") or {}
    codelists = links.get("codelist") or []
    if not codelists:
        return ""
    return str(codelists[0].get("href", "")).rsplit("/", 1)[-1]


def main():
    if not os.path.exists(CACHE):
        sys.exit(
            "Cache not found: %s\n"
            "Clone cdisc-org/cdisc-rules-engine into data-raw/upstream/ first."
            % CACHE
        )

    with open(CACHE, "rb") as fh:
        cache = pickle.load(fh)

    rows = []
    for key in sorted(cache):
        if not key.startswith(PREFIX):
            continue
        # "library_variables_metadata/sdtmig/3-4"        -> sdtmig, 3-4
        # "library_variables_metadata/tig/1-0/sdtm"      -> tig-sdtm, 1-0
        parts = key[len(PREFIX):].split("/")
        if len(parts) == 2:
            standard, version = parts
        elif len(parts) == 3:
            standard, version = "%s-%s" % (parts[0], parts[2]), parts[1]
        else:
            continue

        domains = cache[key]
        if not isinstance(domains, dict):
            continue
        for domain, variables in domains.items():
            if not isinstance(variables, dict):
                continue
            for variable, meta in variables.items():
                if not isinstance(meta, dict):
                    continue
                row = {
                    "standard": standard,
                    "version": version,
                    "domain": domain,
                    "variable": variable,
                }
                for src, dest in FIELDS:
                    value = meta.get(src, "")
                    row[dest] = "" if value is None else str(value)
                row["ccode"] = codelist_ccode(meta)
                rows.append(row)

    header = (
        ["standard", "version", "domain", "variable"]
        + [d for _, d in FIELDS]
        + ["ccode"]
    )
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=header)
        writer.writeheader()
        writer.writerows(rows)

    standards = sorted({r["standard"] for r in rows})
    print("wrote %s: %d rows" % (OUT, len(rows)))
    print("standards: %s" % ", ".join(standards))
    print("with a codelist: %d" % sum(1 for r in rows if r["ccode"]))


if __name__ == "__main__":
    main()

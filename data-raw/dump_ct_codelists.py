"""Dump CDISC Controlled Terminology codelists to CSV for data-raw/ct_codelists.R.

Reads the offline, MIT-licensed caches that cdisc-org/cdisc-rules-engine
commits directly to git (resources/cache/*ct-*.pkl) and flattens them to one
row per (package, codelist).

    python data-raw/dump_ct_codelists.py

Writes data-raw/ct_codelists.csv. Build time only; the package never needs
Python.

Why this is small enough to bundle
----------------------------------
The raw caches are 438 MB across 206 packages, which is why CT was left out of
the first release. But almost all of that is prose - definitions, synonyms and
per-term preferred terms - and conformance needs none of it. What a rule asks
is "is this value one of the terms of codelist X", so the fields kept here are:

  * the codelist's own C-code and submission value, for `level: codelist`
  * each term's submission value and C-code, for `level: term`
  * whether the codelist is extensible, so sponsor values in an extensible
    codelist are not reported as violations

That subset is 46 MB of CSV and compresses to about half a megabyte, because
consecutive CT releases are nearly identical and xz collapses the repetition.

`preferredTerm` is deliberately NOT kept. No bundled rule asks for
`returntype: pref_term`, and carrying it doubles both the file and its
in-memory size. A rule that ever needs it will be skipped with a reason, which
is the honest answer, rather than silently answered from data that isn't here.

Every package is kept, not just recent ones. Terminology changes between
releases - SEX gained INTERSEX and lost UNDIFFERENTIATED - so judging a study
against a version it does not declare would invent violations and hide real
ones. Keeping all 206 costs about 0.04 MB more than keeping three.
"""

import ast
import csv
import glob
import os
import pickle
import sys

CACHE_DIR = os.path.join(
    "data-raw", "upstream", "cdisc-rules-engine", "resources", "cache"
)
OUT = os.path.join("data-raw", "ct_codelists.csv")

# The terms of one codelist are joined with the ASCII Unit Separator, which
# cannot appear in a submission value, so the column can be split back apart
# unambiguously on the R side.
SEP = "\x1f"


def terms_of(codelist):
    """The codelist's terms, whether the cache stored a list or its repr."""
    terms = codelist.get("terms")
    if isinstance(terms, str):
        try:
            terms = ast.literal_eval(terms)
        except (ValueError, SyntaxError):
            terms = []
    return [t for t in (terms or []) if isinstance(t, dict)]


def main():
    files = sorted(glob.glob(os.path.join(CACHE_DIR, "*ct-*.pkl")))
    if not files:
        sys.exit(
            "No CT caches found in %s\n"
            "Clone cdisc-org/cdisc-rules-engine into data-raw/upstream/ first."
            % CACHE_DIR
        )

    rows = 0
    term_count = 0
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "package", "codelist_code", "codelist", "extensible",
                "term_values", "term_codes",
            ],
        )
        writer.writeheader()
        for path in files:
            package = os.path.basename(path)[: -len(".pkl")]
            with open(path, "rb") as pf:
                cache = pickle.load(pf)
            for codelist in cache.get("codelists") or []:
                terms = terms_of(codelist)
                term_count += len(terms)
                writer.writerow({
                    "package": package,
                    "codelist_code": codelist.get("conceptId", ""),
                    "codelist": codelist.get("submissionValue", ""),
                    "extensible": codelist.get("extensible", ""),
                    "term_values": SEP.join(
                        t.get("submissionValue", "") for t in terms
                    ),
                    "term_codes": SEP.join(t.get("conceptId", "") for t in terms),
                })
                rows += 1

    print("wrote %s: %d codelists from %d packages" % (OUT, rows, len(files)))
    print("  terms: %d" % term_count)


if __name__ == "__main__":
    main()

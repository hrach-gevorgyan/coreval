"""Vendor the JSONata evaluator and CDISC's JSONata utility functions.

    python data-raw/vendor_jsonata.py

96 rules are written as JSONata expressions rather than as the Check/Operations
structure the rest of the rules use, so evaluating them means running JSONata.
There is no R implementation of the language, and writing one is not on the
table: the expressions here run to 2744 characters and use transforms, the
descendant operator, higher-order functions and lambdas.

So the reference implementation ships, as JavaScript, run by QuickJSR's
embedded engine. Both files are copied from a pinned source and neither is
edited, apart from a copyright banner restored onto the minified build.

Why 1.8.7 and not the current 2.x
---------------------------------
jsonata 2.x is built on native `async`/`await`: 43 async functions and 102
awaits in the minified build. Resolving a promise needs the host to pump the
engine's job queue, and QuickJSR exposes no way to do that, so `evaluate()`
returns a promise that can never settle. 1.8.7 drives the same evaluator with a
generator trampoline and returns its result directly.

That is a real divergence from the reference, which uses jsonata-python 0.7.0,
a port of the 2.x-era JavaScript. It is measured rather than argued: all 96
rules, across every positive and negative fixture CDISC ships, return exactly
the paths their committed answer sheets name.

The two .jsonata files are CDISC's own, from the same engine repository and
under the same MIT licence as the rest of what coreval bundles. The expressions
call into them as `$utils`, and the engine assembles that prelude at run time
(jsonata_processor.py: get_all_custom_functions), so coreval assembles it the
same way rather than baking in a snapshot.
"""

import hashlib
import os
import shutil
import sys

ENGINE = os.path.join("data-raw", "upstream", "cdisc-rules-engine")
VENDOR = os.path.join("data-raw", "vendor")
DEST_JS = os.path.join("inst", "extdata", "js")
DEST_UTILS = os.path.join("inst", "extdata", "jsonata")

# Pinned. Change the version and the checksum together, then re-run the
# conformance sweep over the JSONata rules before believing the result.
JSONATA_VERSION = "1.8.7"
JSONATA_SHA256 = "87d190b5e329dc559f3809e8d8b47c037a69c479648b0d697eefdf1f2f128403"
JSONATA_URL = "https://cdn.jsdelivr.net/npm/jsonata@1.8.7/jsonata.min.js"

# The minified build carries no banner and the packaged LICENSE omits the
# copyright line it refers to. MIT requires the notice to travel with the
# software, so it is restored here, verbatim from the source file's own header
# at the tagged release (src/jsonata.js at v1.8.7).
BANNER = """/*!
 * JSONata %s -- bundled with coreval, unmodified apart from this banner.
 *
 * (c) Copyright IBM Corp. 2016, 2017 All Rights Reserved
 *   Project name: JSONata
 *   This project is licensed under the MIT License.
 *
 * Source: %s
 * The full MIT licence text is in inst/COPYRIGHTS.
 */
""" % (JSONATA_VERSION, JSONATA_URL)


def sha256(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main():
    src = os.path.join(VENDOR, "jsonata.min.js")
    if not os.path.isfile(src):
        sys.exit(
            "Missing %s.\nDownload the pinned build first:\n  curl -sS -o %s %s"
            % (src, src, JSONATA_URL)
        )
    got = sha256(src)
    if got != JSONATA_SHA256:
        sys.exit(
            "%s is not the pinned build.\n  expected %s\n  got      %s"
            % (src, JSONATA_SHA256, got)
        )

    os.makedirs(DEST_JS, exist_ok=True)
    with open(src, encoding="utf-8") as fh:
        body = fh.read()
    out = os.path.join(DEST_JS, "jsonata.min.js")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(BANNER + body)
    print("wrote %s (%d bytes, jsonata %s)" % (out, os.path.getsize(out), JSONATA_VERSION))

    utils_src = os.path.join(ENGINE, "resources", "jsonata")
    if not os.path.isdir(utils_src):
        sys.exit("No engine clone at %s" % utils_src)
    if os.path.isdir(DEST_UTILS):
        shutil.rmtree(DEST_UTILS)
    os.makedirs(DEST_UTILS)
    names = sorted(f for f in os.listdir(utils_src) if f.endswith(".jsonata"))
    if not names:
        sys.exit("No .jsonata utility functions at %s" % utils_src)
    for name in names:
        shutil.copyfile(os.path.join(utils_src, name), os.path.join(DEST_UTILS, name))
    print("copied %d utility function file(s) into %s: %s"
          % (len(names), DEST_UTILS, ", ".join(names)))


if __name__ == "__main__":
    main()

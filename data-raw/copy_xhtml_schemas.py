"""Copy the XHTML schema closure into inst/extdata/schema/xml/.

    python data-raw/copy_xhtml_schemas.py

Four rules ask `get_xhtml_errors` of a USDM narrative-content fragment, and
answering needs real schema validation, not just a well-formedness parse: the
findings CDISC's own sheets record include "Element 'usdm:tab': This element is
not expected" and "The attribute 'id' is required but missing", neither of
which a parser sees.

Copies only the transitive closure of xs:include/xs:import/xs:redefine from the
schema the reference maps the USDM namespace to (default_file_paths.py:
LOCAL_XSD_FILE_MAP), plus the W3C copyright module. The rest of the 86 files
upstream are for XHTML Basic, Print, RDFa and XForms, which USDM narrative
content does not use.

One edit is applied, to CDISC's own usdm-xhtml-ns.xsd: its schemaLocation for
xhtml-datatypes-1 is an http://www.w3.org URL, and libxml2 fetches it over the
network on every validation. coreval does not touch the network at run time, so
it is repointed at the copy sitting beside it. No W3C file is modified.

Licensing: the W3C XHTML Schema modules carry a perpetual grant to use, copy,
modify and distribute, conditioned on the copyright notice and that paragraph
appearing in all copies. xhtml-copyright-1.xsd carries them and is part of the
closure, so it ships verbatim; inst/COPYRIGHTS reproduces the notice as well.
"""

import os
import re
import shutil
import sys

SRC = os.path.join("data-raw", "upstream", "cdisc-rules-engine",
                   "resources", "schema", "xml")
DEST = os.path.join("inst", "extdata", "schema", "xml")
# Only the USDM namespace. The reference maps a second namespace to
# xhtml-1.1/xhtml11.xsd, but all four rules that use this operation declare the
# USDM one, and its closure already pulls in the XHTML modules they need.
ROOTS = [
    os.path.join("cdisc-usdm-xhtml-1.0", "usdm-xhtml-1.0.xsd"),
    # Not reachable by schemaLocation: the W3C modules cite it as
    # `xs:documentation source="xhtml-copyright-1.xsd"`, which a closure walk
    # over schema references does not follow. It is the file carrying the
    # copyright notice and permission paragraph that the W3C grant requires to
    # appear in all copies, so it is named here rather than derived.
    os.path.join("xhtml-1.1", "xhtml-copyright-1.xsd"),
]
# The URL libxml2 would otherwise fetch, and the copy to use instead.
REMOTE = "http://www.w3.org/MarkUp/SCHEMA/xhtml-datatypes-1.xsd"
LOCAL = "../xhtml-1.1/xhtml-datatypes-1.xsd"
REF = re.compile(r'schemaLocation\s*=\s*"([^"]+)"')


def closure():
    """Every file reachable from ROOTS, as paths relative to SRC."""
    seen, queue = set(), list(ROOTS)
    while queue:
        rel = os.path.normpath(queue.pop())
        if rel in seen:
            continue
        path = os.path.join(SRC, rel)
        if not os.path.isfile(path):
            sys.exit("Schema references a file that is not there: " + rel)
        seen.add(rel)
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        for loc in REF.findall(body):
            # A remote reference is resolved locally or not at all; see above.
            if loc.startswith(("http://", "https://")):
                continue
            queue.append(os.path.join(os.path.dirname(rel), loc))
    return sorted(seen)


def main():
    if not os.path.isdir(SRC):
        sys.exit("No engine clone at %s" % SRC)
    files = closure()
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    total, patched = 0, 0
    for rel in files:
        out = os.path.join(DEST, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(os.path.join(SRC, rel), encoding="utf-8") as fh:
            body = fh.read()
        if REMOTE in body:
            body = body.replace(REMOTE, LOCAL)
            patched += 1
        with open(out, "w", encoding="utf-8", newline="") as fh:
            fh.write(body)
        total += len(body.encode("utf-8"))
    print("copied %d files, %d bytes, into %s" % (len(files), total, DEST))
    print("repointed the remote schemaLocation in %d file(s)" % patched)
    if patched != 1:
        sys.exit("Expected exactly one file to carry the remote reference")


if __name__ == "__main__":
    main()

## Submission

Update to coreval, from 0.3.0 on CRAN to 0.4.0.

## Why this update

On 3 November 2026 CDISC released CORE 1.0, its conformance rules engine. With
it, the SDTM rules moved from CDISC's rules repository to one maintained by
Verisian (verisianHQ/core-contributor), and they now run under a different
engine whose semantics differ from the previous one in places. The rules CRAN's
0.3.0 bundles for SDTM are the ones CDISC no longer maintains. This release
checks an SDTM study with the CORE 1.0 rules, and keeps CDISC's rules for SEND,
TIG and USDM, where CDISC still maintains them.

It also fixes defects that made a check quietly report nothing, found by
checking CDISC's pilot submission with this package and with CORE 1.0's own
engine and comparing every finding. See NEWS.md for the full list.

Some behaviour changes on purpose, each listed in NEWS.md:

* `check_study()` and `check_dataset()` require `standard`, as CDISC's and
  Verisian's engines do. Without it every standard's rules ran, and an SDTM
  study was reported SEND and TIG problems. A call without it now stops with
  an error that says what to add.
* A folder holding a USDM study design document is checked only with
  `usdm = TRUE`, because some of its rules take minutes on one file.
* `standard = "TIG"` now needs the new `substandard` argument (`"SDTM"`,
  `"SEND"` or `"ADaM"`), as CDISC's own engine requires; a TIG rule's use case
  covers different datasets in each.
* An SDTM study is checked with the CORE 1.0 rules. CDISC's SDTM rules that
  CORE 1.0 does not carry run only with `include_deprecated = TRUE`.
* `check_dataset()` skips, with a reason, rules about the whole study and rules
  that read a dataset it was not given, where it used to answer them as if
  that dataset were empty.
* `check_dataset(x, domain = )` with a domain that contradicts the data's
  DOMAIN column is refused.
* The `rules_version` attribute names both rule repositories and their
  commits.

Nothing is deprecated and nothing is removed, though a call with no
`standard` now has to name one. Input that was never valid and
used to be accepted silently is now refused with an error that says what is
wrong: a transport file holding more than one dataset, a Dataset-JSON file with
neither rows nor a record count, and some CSV files with a row of the wrong
length.

## Test environments

* Local: Windows 11, R 4.6.1
* win-builder: R-devel and R-release
* GitHub Actions: ubuntu-latest, macOS, Windows (R release)

## R CMD check results

Local, Windows 11, R 4.6.1: 0 errors | 0 warnings | 0 notes.

GitHub Actions, R release on ubuntu-latest, macOS and Windows: 0 errors | 0 warnings.

win-builder, R-devel and R 4.6.2: 1 NOTE on each, the incoming-feasibility check.

* "Verisian" is flagged as possibly misspelled. It is the name of the company
  that maintains the CORE 1.0 rules repository, and is spelled correctly.

## Notes for the reviewer

The package bundles published conformance rules and the reference metadata
they need, extracted at build time from three MIT-licensed repositories, each
at a pinned commit: CDISC's cdisc-open-rules and cdisc-rules-engine, and
Verisian's core-contributor. A few small reference tables (the FDA guides list,
the FDA Data Standards Catalog, ISO 3166 and GENC country lists) come from
Verisian's fork of the engine, under the same MIT notice as CDISC's.
`inst/COPYRIGHTS` names each bundled file and the repository it came from, and
reproduces the three MIT notices, which differ between repositories. Both rules
commits are recorded in the package too, and written into every findings file.

No CDISC API is contacted at build time or at run time, and nothing is
downloaded. CDISC's own engine requires an API key for the CDISC Library; this
package does not, and takes its data only from files committed to those public
repositories under MIT.

Two bundled components are not from those repositories, and `inst/COPYRIGHTS`
describes the terms of each:

* `inst/extdata/schema/xml/xhtml-1.1/` is the W3C's XHTML Schema modules,
  redistributed verbatim to validate XHTML offline. They carry the W3C's own
  perpetual grant to use, copy, modify and distribute, conditioned on the
  copyright notice and that paragraph appearing in all copies. The file
  carrying them, `xhtml-copyright-1.xsd`, ships with them, and the notice is
  reproduced in `inst/COPYRIGHTS` as well.
* `inst/extdata/js/jsonata.min.js` is the JSONata reference implementation,
  (c) IBM Corp., MIT. Many of the bundled USDM rules are written in that query
  language and there is no R implementation of it, so it is evaluated in
  QuickJSR's embedded JavaScript engine. The upstream minified build carries
  no copyright banner and the packaged LICENSE omits the copyright line its
  own terms refer to, so the notice was taken from the tagged source header
  and restored onto the bundled file.

Both are reached only through `Suggests` (`xml2`, `QuickJSR`); without those
packages the rules needing them are skipped with a reason rather than
answered.

Examples and tests write only to `tempdir()`.

The conformance harness that compares this package against the rules' own
published expected results is not part of the build. It lives in
`tests/conformance/` and is excluded via `.Rbuildignore`, because it needs
clones of the rules repositories that are far too large to ship.

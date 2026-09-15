## Submission

Update to coreval. The previous version on CRAN is 0.1.0, published on
2026-09-12.

## Why this update follows so soon

I know updates are expected no more often than every one to two months, and I
would not ask for an exception without a reason. 0.1.0 has defects that make
checks quietly report nothing, which for a conformance checker means data with
problems is reported as clean. Anyone installing it today gets that version.

Since 0.1.0 the package has been checked against CDISC's own engine on a
complete real submission (CDISC's pilot study), rule by rule, which found and
fixed three defects in how real transport files are read. It was also run on
studies of up to 5.9 million rows, and fed 95 broken or malformed inputs, which
found cases where a damaged file was checked in part instead of refused. Those
are fixed too.

This release fixes several defects that made a check quietly report nothing,
adds CDISC Controlled Terminology support, reads the terminology version a
study declares in TS or in its Define-XML, adds support for CDISC's USDM
study-design model, and makes checking a large study about twenty times
faster, with a further halving of time and lower memory use on large studies.
See NEWS.md for the full list.

The interface only gains. `list_ct_packages()` is new, and `check_study()` and
`check_dataset()` take a new optional `ct_package` argument that defaults to
NULL. `check_study()` also gains `standard` and `version`, both optional.
Nothing existing changed its meaning, nothing is deprecated, and nothing is
removed, so code written against 0.1.0 runs unchanged. The one exception is
input that was never valid and used to be accepted silently: a misspelt
`use_case`, a non-logical `include_deprecated`, duplicate column names, and
damaged or truncated files are now refused with an error that says what is
wrong.

The installed size grows, from about 1.2 MB to about 1.9 MB. All of it is
bundled CDISC reference data and the two third-party files described below,
and it is what makes the package work offline: contacting CDISC's Library
would need an API key and a network call at check time.

## Test environments

* Local: Windows 11, R 4.6.1
* win-builder: R-devel and R-release
* GitHub Actions: ubuntu-latest, macOS, Windows (R release)

## R CMD check results

0 errors | 0 warnings | 1 note

* win-builder (R-devel and R-release): `Days since last update: 3`. This is
  the early update explained above.
* Local `R CMD check --as-cran`, and GitHub Actions on Linux, macOS and
  Windows: no notes.

## Notes for the reviewer

The package bundles CDISC's published conformance rules and the reference
metadata they need, extracted at build time from two MIT-licensed CDISC
repositories, each at a pinned commit. `inst/COPYRIGHTS` names each bundled
file, the repository and commit it came from, and reproduces both MIT notices,
which differ between the two repositories.

No CDISC API is contacted at build time or at run time, and nothing is
downloaded. CDISC's own engine requires an API key for the CDISC Library; this
package does not, and takes its data only from files committed to those public
repositories under MIT.

Two bundled files are not CDISC's and not MIT, and `inst/COPYRIGHTS` says so
for each:

* `inst/extdata/schema/xml/xhtml-1.1/` is the W3C's XHTML Schema modules,
  redistributed verbatim to validate XHTML offline. They carry the W3C's own
  perpetual grant to use, copy, modify and distribute, conditioned on the
  copyright notice and that paragraph appearing in all copies. The file
  carrying them, `xhtml-copyright-1.xsd`, ships with them, and the notice is
  reproduced in `inst/COPYRIGHTS` as well.
* `inst/extdata/js/jsonata.min.js` is the JSONata reference implementation,
  (c) IBM Corp., MIT. 96 of the bundled rules are written in that query
  language and there is no R implementation of it, so it is evaluated in
  QuickJSR's embedded JavaScript engine. The upstream minified build carries
  no copyright banner and the packaged LICENSE omits the copyright line its
  own terms refer to, so the notice was taken from the tagged source header
  and restored onto the bundled file.

Both are reached only through `Suggests` (`xml2`, `QuickJSR`); without those
packages the rules needing them are skipped with a reason rather than
answered.

Examples and tests write only to `tempdir()`.

The conformance harness that compares this package against CDISC's own
published expected results is not part of the build. It lives in
`tests/conformance/` and is excluded via `.Rbuildignore`, because it needs a
clone of CDISC's rules repository that is far too large to ship.

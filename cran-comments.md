## Submission

Update to coreval. The previous version on CRAN is 0.1.0.

This release fixes several defects that made a check quietly report nothing,
adds CDISC Controlled Terminology support, reads the terminology version a
study declares in TS or in its Define-XML, adds support for CDISC's USDM
study-design model, and makes checking a large study about twenty times
faster. See NEWS.md for the full list.

The interface only gains. `list_ct_packages()` is new, and `check_study()` and
`check_dataset()` take a new optional `ct_package` argument that defaults to
NULL. `check_study()` also gains `standard` and `version`, both optional.
Nothing existing changed its meaning, nothing is deprecated, and nothing is
removed, so code written against 0.1.0 runs unchanged.

The installed size grows, from about 1.2 MB to about 1.9 MB. All of it is
bundled CDISC reference data and the two third-party files described below,
and it is what makes the package work offline: contacting CDISC's Library
would need an API key and a network call at check time.

## Test environments

* Local: Windows 11, R 4.6.1
* win-builder: R-devel and R-release
* GitHub Actions: ubuntu-latest, macOS, Windows (R release)
* R-hub

## R CMD check results

0 errors | 0 warnings | 0 notes

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

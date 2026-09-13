## Submission

Update to coreval. The previous version on CRAN is 0.1.0.

This release fixes several defects that made a check quietly report nothing,
adds CDISC Controlled Terminology support, reads the terminology version a
study declares in TS or in its Define-XML, and makes checking a large study
about twenty times faster. See NEWS.md for the full list.

The interface only gains. `list_ct_packages()` is new, and `check_study()` and
`check_dataset()` take a new optional `ct_package` argument that defaults to
NULL. `check_study()` also gains `standard` and `version`, both optional.
Nothing existing changed its meaning, nothing is deprecated, and nothing is
removed, so code written against 0.1.0 runs unchanged.

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

Examples and tests write only to `tempdir()`.

The conformance harness that compares this package against CDISC's own
published expected results is not part of the build. It lives in
`tests/conformance/` and is excluded via `.Rbuildignore`, because it needs a
clone of CDISC's rules repository that is far too large to ship.

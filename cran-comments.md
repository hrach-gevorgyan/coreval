## Submission

Update to coreval. The previous version on CRAN is 0.1.0.

This release fixes a class of false positive, adds CDISC Controlled
Terminology support, and makes checking a large study substantially faster.
See NEWS.md for the full list.

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

## Submission

First submission of coreval to CRAN.

## Test environments

* Local: Windows 11, R 4.6.1 — 0 errors | 0 warnings | 0 notes
* win-builder: R-devel and R-release — *to be run before submission*
* Linux (GitHub Actions, ubuntu-latest): R release — *to be run before submission*
* macOS builder — *to be run before submission*

## R CMD check results

0 errors | 0 warnings | 0 notes

## Bundled third-party material

The package bundles CDISC conformance rule definitions and CDISC standards
metadata under `inst/extdata` (about 160 KB total). Both come from
MIT-licensed repositories published by CDISC — `cdisc-org/cdisc-open-rules`
and `cdisc-org/cdisc-rules-engine` — and are extracted at build time from a
pinned commit. `inst/COPYRIGHTS` names each bundled file, says which
repository it came from, and reproduces the MIT notice in full. The
`Copyright` field in DESCRIPTION points there.

Nothing is downloaded at build, install, check or run time.

## Notes for the reviewer

* No internet access is used anywhere in the package, its tests, its examples
  or its vignette.
* Nothing is written outside `tempdir()`.
* `writexl`, `xml2`, `knitr` and `rmarkdown` are Suggests and every use is
  guarded with `requireNamespace()`.
* The package is not affiliated with or endorsed by CDISC, and is not a
  CORE-certified conformance engine. This is stated in DESCRIPTION, the
  README and the vignette.

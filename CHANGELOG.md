# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Package skeleton passing `R CMD check` with 0 errors, 0 warnings, 0 notes
  on Windows, macOS, and Linux (GitHub Actions).
- `data-raw/extract_rules.R`: extracts the SDTMIG/ADaMIG rule set from
  [cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
  into `inst/extdata/rules.rds`, pinned to a specific upstream commit
  (`data-raw/UPSTREAM_SHA`).
- `list_rules()`: returns all bundled rules as a `data.table`, tagged by
  `source` (`published`, `deprecated_dir`, `fda_business_rules_draft`) and
  `status`.
- `rules_version()`: returns the pinned upstream commit SHA.

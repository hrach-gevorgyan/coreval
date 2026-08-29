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
- `read_study(path)`: reads a directory of XPT datasets, or a CORE test-case
  `data/` directory (`.env` + `_datasets.csv` + `_variables.csv` + one CSV
  per dataset), into a common internal representation. Character columns
  use `""` for blank/missing (matching how SAS XPT round-trips blanks, since
  it has no character `NA`); column types come from the source rather than
  being guessed from data.
- `rules_for_domain(domain, use_case = NULL)`: resolves a rule's
  `Scope > Classes` and `Scope > Domains` against an actual SDTM domain
  code, handling the `"ALL"`/`"NONE"` sentinels, Include vs Exclude, and
  `"XX--"` prefix wildcards (e.g. `SUPP--`, `AP--`).
- `sdtm_domain_classes()`: the bundled SDTMIG 3.4 domain -> observation-class
  reference table used by `rules_for_domain()`.

### Fixed

- YAML 1.1 boolean literals (bare `y`/`Y`/`yes`/`on`/`true`,
  `n`/`N`/`no`/`off`/`false`) in a condition's `value` field were silently
  coerced to logical `TRUE`/`FALSE` instead of staying the literal string
  they represent - corrupting extremely common SDTM Y/N flag checks
  (`DTHFL`, `*PRESP`, `*OCCUR`, ...). `data-raw/extract_rules.R` now
  preserves the original text and separately re-coerces the schema's actual
  boolean flags (`value_is_literal`, `negative`, etc.) back to logicals.

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
- `evaluate_rule(rule, dataset, domain)`: walks a rule's `Check` tree
  (arbitrary `all`/`any`/`not` nesting) and returns a per-row logical vector
  of violations. Resolves `value_is_literal` (defaulting to `FALSE`/column
  reference when absent, per the schema's most dangerous default) and `"--"`
  variable name templates (e.g. `--OCCUR` -> `AEOCCUR` for domain `AE`).
  Verified end-to-end against CDISC's own reference `results.csv` for two
  real rules (CORE-000001, `value_is_literal: true`; CORE-000025, absent).
- 17 operators: `empty`, `non_empty`, `exists`, `not_exists` (dataset-level,
  not per-row), `equal_to`, `not_equal_to`, `less_than`,
  `less_than_or_equal_to`, `greater_than`, `greater_than_or_equal_to`,
  `equal_to_case_insensitive`, `not_equal_to_case_insensitive`,
  `is_contained_by`, `is_not_contained_by`, `matches_regex`,
  `not_matches_regex`, `longer_than`. Covers 286 of the 365 rules with no
  `Operations`/`Match Datasets` block (209 of 332 Published-only).

### Fixed

- YAML 1.1 boolean literals (bare `y`/`Y`/`yes`/`on`/`true`,
  `n`/`N`/`no`/`off`/`false`) in a condition's `value` field were silently
  coerced to logical `TRUE`/`FALSE` instead of staying the literal string
  they represent - corrupting extremely common SDTM Y/N flag checks
  (`DTHFL`, `*PRESP`, `*OCCUR`, ...). `data-raw/extract_rules.R` now
  preserves the original text and separately re-coerces the schema's actual
  boolean flags (`value_is_literal`, `negative`, etc.) back to logicals.

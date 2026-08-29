# coreval 0.0.0.9000

* Package skeleton passing `R CMD check` with 0 errors, 0 warnings, 0 notes
  on Windows, macOS, and Linux (GitHub Actions).
* `data-raw/extract_rules.R`: extracts the SDTMIG/ADaMIG rule set from
  [cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
  into `inst/extdata/rules.rds`, pinned to a specific upstream commit
  (`data-raw/UPSTREAM_SHA`).
* `list_rules()`: returns all bundled rules as a `data.table`, tagged by
  `source` (`published`, `deprecated_dir`, `fda_business_rules_draft`) and
  `status`.
* `rules_version()`: returns the pinned upstream commit SHA.
* `read_study(path)`: reads a directory of XPT datasets, or a CORE test-case
  `data/` directory (`.env` + `_datasets.csv` + `_variables.csv` + one CSV
  per dataset), into a common internal representation. Character columns
  use `""` for blank/missing (matching how SAS XPT round-trips blanks, since
  it has no character `NA`); column types come from the source rather than
  being guessed from data.
* `rules_for_domain(domain, use_case = NULL)`: resolves a rule's
  `Scope > Classes` and `Scope > Domains` against an actual SDTM domain
  code, handling the `"ALL"`/`"NONE"` sentinels, Include vs Exclude, and
  `"XX--"` prefix wildcards (e.g. `SUPP--`, `AP--`).
* `sdtm_domain_classes()`: the bundled SDTMIG 3.4 domain -> observation-class
  reference table used by `rules_for_domain()`.
* `evaluate_rule(rule, dataset, domain)`: walks a rule's `Check` tree
  (arbitrary `all`/`any`/`not` nesting) and returns a per-row logical vector
  of violations. Resolves `value_is_literal` (defaulting to `FALSE`/column
  reference when absent, per the schema's most dangerous default) and `"--"`
  variable name templates (e.g. `--OCCUR` -> `AEOCCUR` for domain `AE`).
  Verified end-to-end against CDISC's own reference `results.csv` for two
  real rules (CORE-000001, `value_is_literal: true`; CORE-000025, absent).
* 21 operators implemented: `empty`, `non_empty`, `exists`, `not_exists`
  (dataset-level, not per-row), `equal_to`, `not_equal_to`, `less_than`,
  `less_than_or_equal_to`, `greater_than`, `greater_than_or_equal_to`,
  `equal_to_case_insensitive`, `not_equal_to_case_insensitive`,
  `is_contained_by`, `is_not_contained_by`, `matches_regex`,
  `not_matches_regex`, `longer_than`, `is_not_unique_set`, `is_unique_set`,
  `is_not_unique_relationship`, `is_unique_relationship`. The last four
  flag duplicate multi-column combinations and enforce one-to-one column
  relationships; their semantics are undocumented in the rule schema and
  were reverse-engineered from `cdisc-org/cdisc-rules-engine`'s own
  operator implementation, then verified against CDISC's reference
  `results.csv` for two real rules (CORE-186, CORE-132). 320 of 365
  no-`Operations`/`Match Datasets` rules are now executable (229 of 332
  Published-only).

* Date operators: `date_equal_to`, `date_not_equal_to`, `date_greater_than`,
  `date_less_than`, `date_greater_than_or_equal_to`,
  `date_less_than_or_equal_to`, `is_complete_date`, `is_incomplete_date`,
  `invalid_date`, `invalid_duration`. SDTM dates are legitimately partial
  (`"2024-03"`, `"2024---15"`), so these are backed by a partial-ISO-8601
  parser ported from `cdisc-org/cdisc-rules-engine`'s own date-precision
  logic, not `as.Date()`: two dates are compared by truncating both to
  their common (coarser) precision first, and `date_equal_to`/
  `date_not_equal_to` additionally require matching precision - `"2024"`
  and `"2024-01-01"` are never equal, even though truncating both to
  year-precision gives the same value.
* String/set operators: `contains`, `does_not_contain`, `starts_with`,
  `ends_with`, `has_equal_length`, `has_not_equal_length`,
  `is_contained_by_case_insensitive`, `is_not_contained_by_case_insensitive`,
  `prefix_matches_regex`, `not_prefix_matches_regex`,
  `suffix_matches_regex`, `not_suffix_matches_regex`, `shorter_than`,
  `contains_all`, `not_contains_all` (the last two are dataset-level, like
  `exists`/`not_exists` - they check the target column's full value set,
  not row by row).
* `tests/conformance/run_conformance.R`: the conformance harness. Runs every
  bundled rule against CDISC's own positive/negative reference test cases
  (from a local `cdisc-open-rules` clone) and reports a pass/fail/skipped
  scoreboard, broken down by rule type and skip reason. Not part of the
  package or `R CMD check` (needs network access to the upstream repo).
  Building it immediately surfaced two real evaluator bugs (see Bug fixes)
  that hand-picked test cases hadn't caught. Current state: 260 rules pass,
  51 fail, 196 skipped (mostly `Operations`/`Match Datasets`, not yet
  implemented) - 53.1% pass rate among Fully Executable rules.
* YAML 1.1 boolean literals (bare `y`/`Y`/`yes`/`on`/`true`,
  `n`/`N`/`no`/`off`/`false`) in a condition's `value` field were silently
  coerced to logical `TRUE`/`FALSE` instead of staying the literal string
  they represent - corrupting extremely common SDTM Y/N flag checks
  (`DTHFL`, `*PRESP`, `*OCCUR`, ...). `data-raw/extract_rules.R` now
  preserves the original text and separately re-coerces the schema's actual
  boolean flags (`value_is_literal`, `negative`, etc.) back to logicals.
* `resolve_condition_value()` returned `NULL` (-> the condition always
  evaluated to `NA`/false) whenever `value` wasn't marked literal and also
  wasn't the name of an existing column - e.g. `value: Y` with no column
  named `"Y"`. Per the reference engine's own resolution, this should fall
  back to the literal text instead. Found via the conformance harness,
  which is exactly what it's for: it turned ~50 silent false negatives into
  passes.
* A related bug in the same function: multi-element literal values (e.g.
  `is_not_contained_by: [Y, N]`, common and never marked
  `value_is_literal`) were being misidentified as a grouping operator's
  column-name list and resolved to `NULL`. Fixed by resolving the ambiguity
  correctly - grouping operators read their raw column names from the
  condition directly and never depend on this function's return value.
* `is_valid_date_str()` only checked the date regex's *shape*, not real
  calendar validity - `"2023-02-30"` matches the day pattern fine (nothing
  in the regex knows February doesn't have 30 days) but isn't a real date.
  The reference engine's `isoparse` rejects it for fully-specified dates;
  now matched explicitly with a leap-year-aware day-count check. Uncertain/
  partial dates (`"2024---15"`) skip this, matching upstream.

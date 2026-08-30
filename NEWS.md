# coreval 0.0.0.9000

* Rule extraction widened from SDTMIG-only to also pull SENDIG (base +
  SENDIG-AR/DART/GENETOX extensions) and TIG rules from the same upstream
  `cdisc-open-rules` clone (507 -> 756 bundled rules); ADaMIG's much larger
  `Unpublished/ADAMIG` draft folder was deliberately NOT pulled in - every
  one of its rules has test data but zero reference `results.csv`, so
  nothing there can be verified, unlike every other tier extracted.
* Added 19 SEND/SEND-extension domains (BW, BG, CL, FW, MA, OM, PM, TF, TX,
  POOLDEF, SJ, IC, PY, FM, FX, TT, TP, AC, GV) to `sdtm_domain_classes.rds`,
  machine-extracted from `cdisc-rules-engine`'s bundled `standards_details.pkl`.
* Added `inst/extdata/sdtmig_variables.rds` (per-SDTMIG-version, per-domain
  Core designation + ordinal, all 5 versions 3.1.2-3.4) and
  `inst/extdata/sdtm_model_variables.rds` (per SDTM Model observation class,
  the full set of variables the abstract Model allows), both machine-
  extracted from `cdisc-rules-engine`'s bundled, offline, MIT-licensed
  pickle caches - not a live API call. These back three new `Operations`
  types: `required_variables`, `expected_variables`, `get_model_column_order`.
* `read_study()` now captures a CORE test case's `.env` file
  (`PRODUCT`/`VERSION`) as `study$standard`, and no longer assumes every
  fixture is SDTMIG-flavored just because its rule looks that way (e.g.
  CORE-000355's EX fixture is actually SENDIG 3.1). Also fixed two crashes
  on real fixtures: format detection now checks for `_variables.csv`
  instead of `_datasets.csv` (some fixtures ship no `_datasets.csv`
  manifest at all), and a dataset with zero matching rows in
  `_variables.csv` no longer crashes the whole study read.
* `matches_regex`/`not_matches_regex` now anchor at the string's start
  (like Python's `re.match()`), not R's default unanchored `grepl()` search
  - verified across all 51 affected rules to be a strict improvement with
  no regressions.
* Added a `target_is_not_sorted_by` operator (partial-ISO-8601-aware pairwise
  date ordering within a group) and several grouping/presence operators:
  `has_same_values`, `present_on_multiple_rows_within`,
  `not_present_on_multiple_rows_within`, `inconsistent_enumerated_columns`,
  `does_not_have_next_corresponding_record`, `empty_within_except_last_row`,
  `does_not_equal_string_part`.
* Added support for `Sensitivity: Group` rules (e.g. CORE-000888,
  CORE-000993): one finding is now reported per violating group (from the
  rule's `Grouping_Variables` field) at the group's first violating row,
  instead of one per record. Along the way, fixed `contains`/
  `does_not_contain` to use exact set membership (not substring search)
  when the target is a `$`-bound grouped `distinct` Operations binding
  (a list of values per row) rather than a plain string.
* Added `URL`/`BugReports` fields to `DESCRIPTION` pointing at the GitHub
  repository, and dropped the unused `xml2` `Suggests` dependency (nothing
  in the package currently calls it).

* Every exported function (`evaluate_rule()`, `read_study()`,
  `check_study()`, `list_rules()`, `rules_version()`, `rules_for_domain()`,
  `sdtm_domain_classes()`) now has a runnable `@examples` block - each
  verified with `devtools::run_examples()`. `check_study()`'s example is
  wrapped in `\donttest{}` since it evaluates all bundled rules.
* Added `inst/WORDLIST` so `spelling::spell_check_package()` doesn't
  re-flag legitimate CDISC/SDTM domain terms and technical compounds.

* Nine correctness bugs found by an independent adversarial code review of
  every operator/operations/join implementation, each confirmed with a
  concrete reproducible failing example before being fixed:
  * `compare_op()` (`R/op_compare.R`): the four ordinal comparison
    operators (`less_than`, `less_than_or_equal_to`, `greater_than`,
    `greater_than_or_equal_to`) had no numeric/character coercion, so R
    silently did a lexicographic STRING comparison whenever a numeric
    target was compared against a numeric-looking string value (e.g. a
    quoted YAML literal `"65"`) - `greater_than(9, "65")` returned `TRUE`.
    Now coerces the string side to numeric first when it parses cleanly.
  * `is_not_unique_set` (`R/op_grouping.R`): the blank-value sentinel was
    the literal text `"NA"`, colliding with a genuine data value of "NA";
    and multi-column keys were pasted together with no separator,
    colliding across column boundaries (`("1","23")` vs `("12","3")`).
    Both now use the ASCII Unit Separator (`\x1f`).
  * `compute_dy()` (`R/operations.R`): a USUBJID with no matching `DM`
    record crashed the entire `dy` computation ("subscript out of bounds")
    instead of yielding `NA` for just that row - `[[` on an atomic named
    vector errors on a missing name, unlike list indexing.
  * `resolve_binding()` (`R/operations.R`): grouped-join keys were pasted
    with no separator, the same cross-column collision as above. Now uses
    `\x1f`.
  * `apply_match_dataset()` (`R/match_datasets.R`): a blank/NA join key
    matched another row's blank/NA key (base `merge()`'s default
    behavior), fabricating matches for a real SDTM data defect (e.g. two
    rows with a missing `USUBJID`). Rows with a blank key are now excluded
    from the merge and always get `NA` for the joined-in columns.
  * `op_date.R`'s timezone offset (e.g. `+02:00`) was parsed by the regex
    but never extracted or applied, so two identical instants recorded in
    different zones compared as unequal/misordered. Now converted to a
    true UTC adjustment before comparison.
  * `op_date.R`'s `"/"`-interval date format (e.g. `"2024-01/2024-06"`)
    cross-contaminated precision and value: a primary date missing a
    component fell back to the SECOND date's (interval) component instead
    of staying genuinely missing. Now the interval group is only used as a
    whole when the primary date matched nothing at all.
  * `op_date.R`'s ISO 8601 duration regex accepted an illegal comma
    SEPARATING components (`"P1Y,2M"`) - a comma is only legal as a
    decimal point WITHIN one component (`"P1,5Y"`). Fixed.
  * `assemble_findings()`'s `value_at()` (`R/results.R`) reported a missing
    numeric Output Variable as the literal text `"NA"` instead of `""`,
    breaking the package's own blank-value contract (numeric blank = `NA`
    internally, `""` when reported - matching how a missing character
    column already reports).

  All nine are covered by new regression tests
  (`test-op-compare.R`, plus additions to `test-op-grouping.R`,
  `test-operations.R`, `test-match-datasets.R`, `test-op-date.R`,
  `test-results.R`).

* A `Match Datasets` one-to-many join (e.g. CORE-000097: `SV` matched with
  `SE`, which has multiple time-windowed records per subject) was
  incorrectly deduplicated to "keep the first match per row." Confirmed
  against the reference engine's actual merge source (a plain,
  undeduplicated `pd.merge` with zero row-selection logic) and against the
  rule's own Check tree, which relies on the join staying fully exploded
  so its own date-range conditions (`SESTDTC <= SVSTDTC <= SEENDTC`) can
  filter down to the one matching record. `evaluate_rule()` and
  `assemble_findings()` now correctly collapse the exploded per-join-row
  results back to one outcome per original record (`.coreval_row_id`
  tracks the mapping), rather than picking an arbitrary first match.
  Verified end-to-end against CDISC's reference `results.csv` for
  CORE-000097 (previously a known, documented failure). Harness impact:
  PASS 349 -> 359, 71.7% pass rate among Fully Executable rules (344/480).
* Internal (non-exported) functions across `R/*.R` now have roxygen
  documentation (kept as source comments via `@noRd` - only the package's
  actual exported API gets a `man/*.Rd` page).

* `check_study(study, use_case = NULL)`: the main user-facing entry point.
  Evaluates every applicable, executable bundled rule against every domain
  in a study and returns `list(findings, skipped)` - a tidy long-format
  findings table matching CDISC's own `results.csv` shape (`rule_id`,
  `Dataset`, `Record`, `Variable`, `Value`), plus a table recording which
  rule/domain combinations couldn't be evaluated and why, so a clean
  findings table is never mistaken for "everything passed." Only the
  `"Record Data"` rule type is supported for now - `"Domain Presence
  Check"` and the metadata-check rule types check things this package
  doesn't model yet (domain/dataset presence, variable metadata) and are
  reported as skipped.
  `Output Variables` is handled exactly, including the schema's implicit
  fallback: when a rule's `Outcome` doesn't declare an explicit list (45%
  of rules don't), the reported columns are the `name` fields from the
  rule's own `Check` tree, in order of first appearance - confirmed
  against a real rule (CORE-000001) rather than assumed.
  `Sensitivity: Dataset` rules emit one row per Output Variable with
  `Record` blank and `Value` taken from the first violating record, vs.
  one row per (Record, Variable) for `Sensitivity: Record` - shapes
  confirmed directly against real reference output.
  Verified against CDISC's reference `results.csv` byte-for-byte
  (Dataset/Record/Variable/Value, not just which records violate) for a
  spot sample spanning both sensitivities and both Output Variables
  sources: 27 of 28 cases matched exactly. The one miss is a known,
  documented limitation, not a logic bug: a numeric value like `0.0` in
  the source CSV is reported back as `"0"`, since parsing it to a real
  number for comparisons loses the original text's formatting - fixing
  this needs `read_study()` to carry the raw source text alongside the
  parsed value specifically for reporting, not done yet.
  Fixed a real bug found by this same verification: `check_study()` was
  building findings from the pre-join dataset instead of the Match-
  Datasets-augmented one `evaluate_rule()` actually checked against,
  silently dropping any Output Variable that only exists on the matched
  side (e.g. `DM.DTHDTC`).

* `Match Datasets`: joins another domain's columns onto the dataset being
  checked before `Check` runs (e.g. pulling `DM.DTHDTC` in while checking
  `DS`). Handles the standard case only - a plain equi-join on `Keys`
  against a regular SDTM domain, left join so every row of the dataset
  being checked survives. A colliding column name (present in both
  datasets) is exposed as `{MatchedDomain}.{Column}` on the matched side -
  confirmed directly from the schema's own condition text (e.g.
  `SE.EPOCH`), not assumed. `RELREC`-based relationship joins, `SUPPxx`/
  `SQxx` pivot merges, and `Child` (parent-hierarchy) joins use genuinely
  different merge logic in the reference engine and raise a clear error
  rather than guess at them.
  Known limitation, left undebugged rather than forced: SE (Subject
  Elements) legitimately has multiple time-windowed records per subject,
  and this package's "keep first match per row" join isn't precise enough
  to reproduce CDISC's reference output there - the real engine likely
  needs a date-range-aware match. Harness impact: PASS 329 -> 349, 69.8%
  pass rate among Fully Executable rules (335/480).

* The `Operations` pipeline: pre-computes `$`-bound values (e.g. `$tv_visit`)
  before a rule's `Check` runs. `evaluate_rule()` now accepts either a
  single dataset (unchanged, backward compatible) or a full study object -
  needed because `Operations` routinely reads from a *different* domain
  than the one being checked (e.g. computing `$tv_visit` from `TV` while
  checking `SV`). 13 operation types implemented: `distinct`, `record_count`
  (both support optional grouping, e.g. per `USUBJID`, and a `filter`),
  `max_date`/`min_date`/`max`, `get_column_order_from_dataset`,
  `variable_exists`, `variable_count`, `study_domains`, `dataset_names`,
  `domain_is_custom`, `extract_metadata` (the `dataset_name` pseudo-column),
  and `dy` (SDTM study-day calculation from `DM.RFSTDTC`). The ~12 rules
  needing genuine CDISC Library metadata (`required_variables`,
  `codelist_terms`, `get_model_column_order`, etc.) are left unresolvable
  rather than faked - there is no bundled data for them.
  Verified against CDISC's reference `results.csv` for an ungrouped
  cross-dataset case (CORE-000036, `distinct`) and a grouped+filtered case
  (CORE-000214, `record_count`); the latter surfaced a real bug (see Bug
  fixes). Harness impact: PASS 260 -> 329, 65.6% pass rate among Fully
  Executable rules (315/480).

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
* `record_count` with both a `filter` and `group`: a group with zero rows
  matching the filter was missing from the result entirely (resolving to
  `NA`) instead of `0`. The reference engine explicitly left-joins filtered
  counts onto the *full* (unfiltered) group set and fills missing with 0;
  grouping only the filtered data (as an earlier version did) silently
  drops groups that exist but had no matches. Found by a unit test before
  it could reach real rule data.
* Fixed a real regression introduced mid-session: `startsWith()` on a
  numeric `value` (e.g. `ECDOSE less_than_or_equal_to 0`) errored once
  `$`-binding resolution was added, since it always called `startsWith()`
  without checking the value was a string first.

# Look up CORE rules

One way in for every question about the rule set: what rules exist, what
a particular one checks, and which of them apply to a domain.

## Usage

``` r
list_rules(
  id = NULL,
  domain = NULL,
  standard = NULL,
  version = NULL,
  use_case = NULL,
  include_deprecated = TRUE
)
```

## Arguments

- id:

  Return only these rules, e.g. `"CORE-000547"`. This is how you look up
  a rule id the report gave you.

- domain:

  Return only rules that apply to this domain, e.g. `"AE"`, resolving
  each rule's `Scope > Classes` and `Scope > Domains`.

- standard:

  Return only rules for this standard, e.g. `"SDTMIG"`. Matched exactly,
  so `"SENDIG"` does not pick up `"SENDIG-DART"`.

- version:

  The standard's version, e.g. `"3.4"` (or `"3-4"`). Only narrows
  alongside `standard`, since a bare version is ambiguous across
  standards.

- use_case:

  Optional use case (e.g. `"INDH"`). Rules with no Use Case constraint
  always pass.

- include_deprecated:

  Include superseded rules. `TRUE` here, unlike
  [`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md)
  and
  [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md),
  which default to `FALSE`. The difference is deliberate: **listing is
  not running**. This function is the catalog of what is bundled, so
  hiding a fifth of it would make `nrow(list_rules())` stop meaning "how
  many rules are there" - and `source` is right here to filter on.
  Checking is a different question, and there a superseded rule would
  report the same defect twice. Pass `FALSE` to see exactly what would
  run.

## Value

A
[`data.table::data.table()`](https://rdrr.io/pkg/data.table/man/data.table.html),
one row per rule: `id`, the one-line `issue` it reports, its fuller
`description`, the `guidance` sentence from the Implementation Guide it
enforces, the `legacy_ids` Pinnacle 21 uses for it, `standard` and
`standard_version`, `authority`, `rule_type`, `sensitivity`,
`executability`, `source` and `status`.

The commit the bundled rules came from is on the result as
`attr(x, "rules_version")`;
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
records it in every exported file.

## Details

The columns are the same whatever you ask for, so the result is safe to
filter, join and script against.

## What `source` tells you

Not every bundled rule carries the same weight:

- `"published"` - `Published/` upstream, fully tested. The trusted core.

- `"deprecated_dir"` - superseded by a published replacement. Not
  returned unless you ask for it, since running both reports the same
  defect twice.

- `"fda_business_rules_draft"` - FDA drafts that already ship test data.

## Examples

``` r
# Everything
nrow(list_rules())
#> [1] 1054

# What does the rule the report just named actually check?
list_rules(id = "CORE-000547")$issue
#> [1] "Variable value is not in correct ISO 8601 date or datetime format"

# What applies to AE under SDTMIG 3.4?
nrow(list_rules(domain = "AE", standard = "SDTMIG", version = "3.4"))
#> [1] 170

# Which snapshot of CDISC's rules is this?
attr(list_rules(), "rules_version")
#> [1] "bc4c2f3020ce3e99949ecaeffd277abb8e0622e0"
```

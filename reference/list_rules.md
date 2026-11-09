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
  include_deprecated = TRUE,
  substandard = NULL
)
```

## Arguments

- id:

  Return only these rules, e.g. `"CORE-000547"`. This is how you look up
  a rule id the report gave you. An id is found whatever `standard`
  says, so a rule written for TIG or SEND is returned too.

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
  hiding the retired rules would make `nrow(list_rules())` stop meaning
  "how many rules are there" - and `source` is right here to filter on.
  Checking is a different question, and there a superseded rule would
  report the same defect twice. Pass `FALSE` to see exactly what would
  run.

- substandard:

  For `standard = "TIG"` only: whether the tobacco study is `"SDTM"`
  (clinical), `"SEND"` (nonclinical) or `"ADaM"`, which decides the
  datasets a TIG rule's use case covers when `domain` is given. Optional
  here, unlike
  [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md):
  left out, the use cases of all three apply.

## Value

A
[`data.table::data.table()`](https://rdrr.io/pkg/data.table/man/data.table.html),
one row per rule: `id`, the one-line `issue` it reports, its fuller
`description`, the `guidance` sentence from the Implementation Guide it
enforces, its `legacy_ids` (the ids the CDISC Conformance Rules and FDA
Business Rules give it), `standard` and `standard_version`, `authority`,
`rule_type`, `sensitivity`, `executability`, `source` and `status`.

The commit the bundled rules came from is on the result as
`attr(x, "rules_version")`;
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
records it in every exported file.

## Details

The columns are the same whatever you ask for, so the result is safe to
filter, join and script against.

## What `source` tells you

Where a rule comes from, and what standing it has there:

- `"core_contributor"` - a CORE 1.0 SDTMIG or FDA Business Rule, from
  Verisian's core-contributor repository. These check an SDTM study.

- `"published"` - `Published/` in CDISC's cdisc-open-rules, fully
  tested.

- `"sendig_draft"`, `"sdtmig_draft"`, `"fda_business_rules_draft"` -
  drafts upstream that already ship test data.

- `"deprecated_dir"` - superseded by a published replacement. A check
  does not run it unless you ask, since running both reports the same
  defect twice.

## Examples

``` r
# Everything
nrow(list_rules())
#> [1] 1184

# What does the rule the report just named actually check?
list_rules(id = "CORE-000547")$issue
#> [1] "Variable value is not in correct ISO 8601 date or datetime format"

# What applies to AE under SDTMIG 3.4?
nrow(list_rules(domain = "AE", standard = "SDTMIG", version = "3.4"))
#> [1] 224

# Which snapshot of the rules is this?
attr(list_rules(), "rules_version")
#> [1] "cdisc-org/cdisc-open-rules af05dfd2b2bdc8a385ed9e74d64bc9f44e905d8f; verisianHQ/core-contributor a3b4d0b08e45f44bcd1aafe16687aa76fe9680e3"
```

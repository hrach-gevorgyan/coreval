# Check a whole study against CDISC Open Rules

Runs every rule that applies to every dataset in the study, including
the ones that compare datasets against each other. Use this once the
datasets exist as files; to check a single dataset while you are still
writing the code that builds it, see
[`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md).

## Usage

``` r
check_study(
  study,
  standard = NULL,
  version = NULL,
  use_case = NULL,
  max_records = 1000,
  include_deprecated = FALSE,
  ct_package = NULL
)
```

## Arguments

- study:

  A study folder path, or a study object from
  [`read_study()`](https://hrach-gevorgyan.github.io/coreval/reference/read_study.md).
  Passing the path is the usual way; reading first is only worth it when
  you want to check the same large study more than once without
  re-reading it, or to look at what was parsed.

- standard:

  The standard the data follows, e.g. `"SDTMIG"` or `"SENDIG"`.
  Overrides whatever the study declares about itself. Rules are written
  per standard, so this cuts the list sharply; leave it unset to run
  every standard's rules and see everything.

- version:

  The standard's version, e.g. `"3.4"`. Needs `standard` too, since a
  bare version is ambiguous across standards.

- use_case:

  Optional use case (e.g. `"INDH"`) to further filter which rules apply,
  as in
  [`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md).

- max_records:

  Most records to keep per rule, default 1000. A rule can flag every
  row - a missing `EPOCH` on a 200 000-row `LB` is 200 000 identical
  findings, more than Excel can hold. The true count is kept in
  `truncated` and the report shows it, so nothing is under-reported. Use
  `Inf` for every record.

- include_deprecated:

  Also run rules CDISC has deprecated. `FALSE` by default: a deprecated
  rule has a published replacement, so running both reports the same
  defect twice.

- ct_package:

  Which CDISC Controlled Terminology package the study follows, e.g.
  `"sdtmct-2026-03-27"`. Rules that ask whether a value is a legal term
  need this, and are skipped with a reason without it - coreval will not
  pick a version for you, because terminology changes between releases
  and judging a study against one it never declared would both invent
  violations and hide real ones. Every published package is bundled;
  [`list_ct_packages()`](https://hrach-gevorgyan.github.io/coreval/reference/list_ct_packages.md)
  shows them.

## Value

An object of class `coreval_result`, holding three tables. Because it
has a class, typing the result's name prints a readable report rather
than dumping the list, and provenance rides along as attributes:
`checks_run`, `domains` and `excluded_by_standard`.

- `findings` - what is wrong. One row per affected record, with
  `Dataset`, `Record`, `Variable`, `Value`, the `issue` in words, and
  its `triage`. `Not in dataset` under `Value` means the rule wanted a
  variable you do not have, which is usually the finding itself.

- `skipped` - what could not be checked, with a `reason` for each. Read
  this one: an empty `findings` table can mean clean data *or* rules
  that never ran, and they look identical otherwise. Reasons include a
  dataset you did not supply, a missing Define-XML, and - for 9 rules -
  CDISC's controlled terminology when no `ct_package` was given, which
  is not bundled. Nothing skipped is ever counted as a pass.

- `truncated` - rules that flagged more records than `max_records` kept,
  with how many they really found.

## Details

Findings come back one row per (dataset, record, variable), pointing at
the exact spot. Some rules ask about a dataset as a whole rather than a
particular row - those leave `Record` blank. A few ask about the study
as a whole, such as "is DM present at all?"; those are answered once and
reported under `Dataset = "STUDY"` rather than repeated for every
domain.

Rules comparing against a define.xml do run, as long as the study has
one and the `xml2` package is installed. Without both, they are skipped
with a reason instead of being run against columns that are not there,
which would report problems that do not exist. The same goes for any
rule needing an operator or join coreval does not implement yet.

## Progress

A large study takes long enough that silence looks like a hang, so an
interactive session shows a progress bar naming the domain being checked
and how far through the study it is:

      AE        4/7  |=====================       |  75%

The percentage is weighted by how many records each domain holds, not by
a plain count of rules, because a check against a 161,600-row `AE` costs
hundreds of times one against a 200-row `SJ`. It tracks elapsed time
closely but is still an estimate - rules differ in cost among themselves
too - so treat it as "roughly how far through", not a clock.

It is off in scripts and non-interactive runs, where it would only
clutter a log. Turn it on or off with `options(coreval.progress = TRUE)`
or `FALSE`.

## Examples

``` r
dir <- tempfile("coreval_study_")
dir.create(dir)
haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))

result <- check_study(dir)
result$findings
#>    Dataset Record            Variable
#>     <char>  <int>              <char>
#> 1:      DM     NA  $dataset_variables
#> 2:      DM     NA $expected_variables
#> 3:      DM     NA  $dataset_variables
#> 4:      DM     NA $required_variables
#> 5:   STUDY     NA                ADSL
#> 6:   STUDY     NA                  TO
#> 7:      DM     NA        dataset_name
#>                                                                                                                                                                          Value
#>                                                                                                                                                                         <char>
#> 1:                                                                                                                                                          ['USUBJID', 'AGE']
#> 2: ['RFSTDTC', 'RFENDTC', 'RFXSTDTC', 'RFXENDTC', 'RFICDTC', 'RFPENDTC', 'DTHDTC', 'DTHFL', 'AGE', 'AGEU', 'RACE', 'ARMCD', 'ARM', 'ACTARMCD', 'ACTARM', 'ARMNRS', 'ACTARMUD']
#> 3:                                                                                                                                                          ['USUBJID', 'AGE']
#> 4:                                                                                                      ['STUDYID', 'DOMAIN', 'USUBJID', 'SUBJID', 'SITEID', 'SEX', 'COUNTRY']
#> 5:                                                                                                                                                              Not in dataset
#> 6:                                                                                                                                                              Not in dataset
#> 7:                                                                                                                                                                          DM
#>                                                                  issue
#>                                                                 <char>
#> 1:              At least one expected variable is missing from dataset
#> 2:              At least one expected variable is missing from dataset
#> 3:              At least one required variable is missing from dataset
#> 4:              At least one required variable is missing from dataset
#> 5:                                         Dataset ADSL does not exist
#> 6: Required TO dataset for study of tobacco product(s) is not present.
#> 7:                       Dataset name does not begin with DOMAIN value
#>              triage     rule_id
#>              <char>      <char>
#> 1: missing optional CORE-000334
#> 2: missing optional CORE-000334
#> 3: missing required CORE-000355
#> 4: missing required CORE-000355
#> 5: missing optional CORE-000560
#> 6: missing required CORE-000590
#> 7:      wrong value CORE-000598
unlink(dir, recursive = TRUE)
```

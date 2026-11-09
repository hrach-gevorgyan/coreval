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
  ct_package = NULL,
  usdm = FALSE,
  substandard = NULL
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

  Required. The standard the data follows, e.g. `"SDTMIG"`, `"SENDIG"`
  or `"TIG"`;
  [`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md)
  shows the rest. Rules are written per standard, and a study checked
  against all of them gets SEND and TIG problems reported on SDTM data,
  so coreval will not run without it, as CDISC's and Verisian's engines
  will not. A CORE test case that declares its standard in a `.env` file
  needs no argument.

- version:

  The standard's version, e.g. `"3.4"`. Needs `standard` too, since a
  bare version is ambiguous across standards. A version older than any
  the rules are written for, such as SDTMIG 3.1.2, is checked against
  the oldest that has rules, and the report says so.

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

  Also run retired rules: those CDISC has deprecated, and, for an SDTM
  study, CDISC's SDTM rules that CORE 1.0 no longer carries. `FALSE` by
  default: a retired rule has a current replacement, so running both can
  report the same defect twice.

- ct_package:

  Which CDISC Controlled Terminology package the study follows, e.g.
  `"sdtmct-2026-03-27"`. Rules that ask whether a value is a legal term
  need this, and are skipped with a reason without it - coreval will not
  pick a version for you, because terminology changes between releases
  and judging a study against one it never declared would both invent
  violations and hide real ones. Every package CDISC's engine carries,
  from 2014 on, is bundled;
  [`list_ct_packages()`](https://hrach-gevorgyan.github.io/coreval/reference/list_ct_packages.md)
  shows them.

- usdm:

  Check a USDM study design document. `FALSE` by default, and only used
  when `study` is a folder path; see
  [`read_study()`](https://hrach-gevorgyan.github.io/coreval/reference/read_study.md).

- substandard:

  For `standard = "TIG"` only, and required there: whether the tobacco
  study is `"SDTM"` (clinical), `"SEND"` (nonclinical) or `"ADaM"`. A
  TIG rule's use case covers different datasets in each, so CDISC's
  engine will not check a TIG study without it, and neither will
  coreval.

## Value

An object of class `coreval_result`, holding three tables. Because it
has a class, typing the result's name prints a readable report rather
than dumping the list, and provenance rides along as attributes:
`checks_run`, `ran` (each rule and dataset checked, one row per check),
`domains`, `excluded_by_standard`, and `define_only` (`TRUE` when the
folder held a define.xml and no datasets, so only the rules comparing
the define with the study ran).

- `findings` - what is wrong. One row per affected record and variable,
  with `Dataset`, `Record` (its row in the file, or for a rule about the
  variables themselves, such as a type or label check, the variable's
  position), `USUBJID` and `SEQ` (its subject and `--SEQ`, blank where
  the dataset has none or the row is not a record), `Variable`, `Value`,
  the `issue` in words, its `triage` and `rule_id`. `Not in dataset`
  under `Value` means the rule wanted a variable you do not have, which
  is usually the finding itself.

- `skipped` - what could not be checked, with a `reason` for each. Read
  this one: an empty `findings` table can mean clean data *or* rules
  that never ran, and they look identical otherwise. Reasons include a
  dataset the study does not have, a missing Define-XML, and a
  controlled terminology version that neither the study nor `ct_package`
  names. Nothing skipped is ever counted as a pass.

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

result <- check_study(dir, standard = "SDTMIG")
result$findings
#>    Dataset Record USUBJID   SEQ                      Variable
#>     <char>  <int>  <char> <num>                        <char>
#> 1:      DM     NA    <NA>    NA   $missing_expected_variables
#> 2:      DM     NA    <NA>    NA   $missing_required_variables
#> 3:      DM     NA    <NA>    NA                 variable_name
#> 4:      DM     NA    <NA>    NA                variable_label
#> 5:      DM     NA    <NA>    NA        library_variable_label
#> 6:   STUDY     NA    <NA>    NA                            EX
#> 7:   STUDY     NA    <NA>    NA $missing_trial_design_domains
#> 8:   STUDY     NA    <NA>    NA                    define.xml
#> 9:   STUDY     NA    <NA>    NA                            TS
#>                                                                                                                                                                   Value
#>                                                                                                                                                                  <char>
#> 1: ['RFSTDTC', 'RFENDTC', 'RFXSTDTC', 'RFXENDTC', 'RFICDTC', 'RFPENDTC', 'DTHDTC', 'DTHFL', 'AGEU', 'RACE', 'ARMCD', 'ARM', 'ACTARMCD', 'ACTARM', 'ARMNRS', 'ACTARMUD']
#> 2:                                                                                                          ['STUDYID', 'DOMAIN', 'SUBJID', 'SITEID', 'SEX', 'COUNTRY']
#> 3:                                                                                                                                                              USUBJID
#> 4:                                                                                                                                                                     
#> 5:                                                                                                                                            Unique Subject Identifier
#> 6:                                                                                                                                                       Not in dataset
#> 7:                                                                                                                           ['TA', 'TD', 'TE', 'TI', 'TM', 'TS', 'TV']
#> 8:                                                                                                                                                       Not in dataset
#> 9:                                                                                                                                                       Not in dataset
#>                                                                                                                                issue
#>                                                                                                                               <char>
#> 1:                                                                                    Expected variable is missing from the dataset.
#> 2:                                                                                    Required variable is missing from the dataset.
#> 3:                                                                  The label of the variable must correspond to the label in the IG
#> 4:                                                                  The label of the variable must correspond to the label in the IG
#> 5:                                                                  The label of the variable must correspond to the label in the IG
#> 6: EX dataset is not present in the study. In case there is a valid reason for not having EX dataset, rule output must be explained.
#> 7:                                                                                     At least one Trial Design Dataset is missing.
#> 8:                                                                                                      Missing Define-XML document.
#> 9:                                                                                                               Missing TS dataset.
#>              triage     rule_id
#>              <char>      <char>
#> 1: missing optional CORE-000334
#> 2: missing required CORE-000355
#> 3:      wrong value CORE-000398
#> 4:      wrong value CORE-000398
#> 5:      wrong value CORE-000398
#> 6: missing required CORE-000739
#> 7: missing optional CORE-002056
#> 8: missing optional CORE-002084
#> 9: missing required CORE-002095
unlink(dir, recursive = TRUE)
```

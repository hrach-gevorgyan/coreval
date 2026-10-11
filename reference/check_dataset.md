# Check one dataset, without needing a study folder

For when you are writing the code that builds a domain and want to know
what is wrong with it right now. Give it the data frame you already have
open, or the path to a single file.

## Usage

``` r
check_dataset(
  x,
  domain = NULL,
  standard = NULL,
  version = NULL,
  use_case = NULL,
  max_records = 1000,
  include_deprecated = FALSE,
  ct_package = NULL
)
```

## Arguments

- x:

  A data frame (or
  [`data.table::data.table()`](https://rdrr.io/pkg/data.table/man/data.table.html)),
  or the path to one `.xpt`, `.sas7bdat` or `.csv` file.

- domain:

  Two-letter domain code, e.g. `"AE"`. Left as `NULL`, coreval takes it
  from your `DOMAIN` column, or the file name if there isn't one. For
  one file of a split dataset with no `DOMAIN` column, such as
  `ae1.xpt`, set it yourself.

- standard:

  The standard the data follows, e.g. `"SDTMIG"` or `"SENDIG"`. Rules
  are scoped to it, which is usually what you want - a SENDIG rule has
  nothing to say about an SDTM study.

  It is not free, though, and CDISC's coverage is uneven. The general
  "dates must be valid ISO 8601" rule (`CORE-000547`) is published for
  SENDIG and TIG but **not for SDTMIG**, whose only equivalents are
  `TSVAL`-specific or deprecated. So `standard = "SDTMIG"` can stop a
  malformed `RFSTDTC` being reported at all. The report says how many
  rules were set aside; leave `standard` unset to see everything.

- version:

  The standard's version, e.g. `"3-4"`.

- use_case:

  Optional use case (e.g. `"INDH"`), as in
  [`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md).

- max_records:

  Most records to keep per rule, default 1000. A rule that flags every
  row of a large dataset would otherwise produce more findings than
  anyone can read or Excel can hold. The true count is kept in
  `truncated`. Use `Inf` for every record.

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

An object of class `coreval_result`: a list of the three tables
`findings`, `skipped` and `truncated`, the same shape
[`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md)
returns, so
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
and
[`filter_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/filter_findings.md)
work on it unchanged. Because it has a class, typing the result's name
prints a readable report rather than dumping the list.

`skipped` carries a `reason` for every rule that did not run - a dataset
you did not supply, a missing Define-XML, or (for 9 rules) CDISC's
controlled terminology, if you did not say which package the study
follows - see `ct_package`. Nothing skipped is ever counted as a pass.

Provenance rides along as attributes: `checks_run` (how many rules were
evaluated), `domains`, and `excluded_by_standard` (how many rules the
`standard`/`version` filter set aside).
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
writes these into the file it saves.

## What it cannot check on its own

Plenty of CDISC rules compare one dataset against another - an adverse
event date against the subject's reference dates in `DM`, a visit
against the trial design. Hand over a single dataset and those questions
cannot be answered.

coreval does not guess. Those rules are skipped, and `$skipped` names
the dataset each one wanted. Running them anyway would compare your data
against columns that are not there and report problems that do not
exist.

Most rules still run on a single dataset. But the ones that cannot are
the cross-dataset checks, which are often the ones that matter.

**So a short `$findings` table here does not mean the data is clean.**
It is a quick first pass, not a verdict. Run
[`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md)
on the whole folder before drawing conclusions.

## See also

[`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md)
to check a whole study folder.

## Examples

``` r
ae <- data.frame(
  STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
  AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30") # 30 February is not a date
)
result <- check_dataset(ae)
result$findings[result$findings$Value == "2024-02-30", ]
#>    Dataset Record Variable      Value
#>     <char>  <int>   <char>     <char>
#> 1:      AE      2  AESTDTC 2024-02-30
#>                                                                issue
#>                                                               <char>
#> 1: Variable value is not in correct ISO 8601 date or datetime format
#>         triage     rule_id
#>         <char>      <char>
#> 1: wrong value CORE-000547

# Always look at what could not run:
nrow(result$skipped)
#> [1] 48
```

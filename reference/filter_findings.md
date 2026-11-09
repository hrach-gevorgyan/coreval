# Narrow a result to the findings you care about

Saves writing [`subset()`](https://rdrr.io/r/base/subset.html) over
`$findings` by hand, and - because it returns a result rather than a
plain table - what comes back still prints as a readable report.

## Usage

``` r
filter_findings(
  result,
  triage = NULL,
  dataset = NULL,
  rule = NULL,
  variable = NULL
)
```

## Arguments

- result:

  A result from
  [`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md)
  or
  [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md).

- triage:

  Keep only these triage levels. One or more of:

  - `"wrong value"` - the data contains something that breaks the rule,
    like a month of 13. Nothing about your study explains it away. Start
    here.

  - `"missing required"` - something the standard marks Required is
    absent.

  - `"missing optional"` - something Expected or Permissible is absent.
    Often legitimate: a screen-failure subject with no reference dates,
    a variable your raw data does not carry yet.

  These are coreval's own triage, not a CDISC severity: the rules carry
  no severity field, and this does not map onto anyone's scale.

- dataset:

  Keep only these datasets, e.g. `"AE"`.

- rule:

  Keep only these rule ids, e.g. `"CORE-000547"`.

- variable:

  Keep only findings naming these variables, including a finding that
  lists the variable as missing (a Required variable the dataset lacks).

## Value

A `coreval_result` holding the matching findings. `$skipped` is left
alone: what could not be checked does not become less true because you
narrowed what you are looking at.

## Examples

``` r
ae <- data.frame(
  STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
  AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30")
)
result <- check_dataset(ae, standard = "SDTMIG")

# Just the things that are definitely wrong:
filter_findings(result, triage = "wrong value")
#> 
#> ── coreval — AE ────────────────────────────────────────────────────────────────
#> 
#> (filtered - this is a subset of the full result)
#> 
#> 1 problem across 1 record  (154 checks ran)
#> 
#>   wrong value         1   the data breaks the rule - start here
#> 
#> [wrong value]
#> Value must be a valid ISO 8601 datetime or interval.
#>   1 record · AESTDTC
#>     row 2  01 seq 2  AESTDTC = "2024-02-30"
#>     CORE-002121  · also CG0011
#> 
#> ────────────────────────────────────────────────────────────────────────────────
#> 68 checks could not run.
#>   28 need other datasets (DM, DS, RELREC, SV, TA, TS, ...)
#>      → run check_study() on the whole folder to cover these
#>   22 ask what the whole study contains
#>   11 need a define.xml
#>      → put it in the study folder (reading it needs the xml2 package)
#>   2 need to know the controlled terminology version
#>      → pass ct_package ("sdtmct-..." or "sendct-..."; see list_ct_packages()), or for a study fill TSVCDREF and TSVCDVER in TS
#>   3 compare variable labels, and the data has none
#>      → give the variables labels: a data frame made in R has none until they are added
#>   2 for other reasons, see result$skipped
#> 
#> Scoped to SDTMIG: 66 rules written for other standards, or other versions of this one, were not run.
#> 
#> Fix what you can, then run this again.
#> To track the rest:  write_findings(result, "issues.xlsx")
```

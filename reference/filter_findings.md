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

  - `"missing optional"` - something Expected is absent, or a value is
    blank. Often legitimate: a screen-failure subject with no reference
    dates, a variable your raw data does not carry yet.

  These are coreval's own triage, not a CDISC severity: the rules carry
  no severity field, and this does not map onto anyone's scale.

- dataset:

  Keep only these datasets, e.g. `"AE"`.

- rule:

  Keep only these rule ids, e.g. `"CORE-000547"`.

- variable:

  Keep only findings naming these variables.

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
result <- check_dataset(ae)

# Just the things that are definitely wrong:
filter_findings(result, triage = "wrong value")
#> 
#> ── coreval — AE ────────────────────────────────────────────────────────────────
#> 
#> (filtered - this is a subset of the full result)
#> 
#> 2 problems across 2 records  (160 checks ran)
#> 
#>   wrong value         2   the data breaks the rule - start here
#> 
#> [wrong value]
#> The Study Day of Start of Observation (--STDY) is not present in the dataset
#>   when Start Date/Time of Observation (--STDTC) is present.
#>   1 record · AESTDTC
#>     AESTDTC = "2024-01-10"
#>     CORE-000328  · also FB3202
#> 
#> [wrong value]
#> Variable value is not in correct ISO 8601 date or datetime format
#>   1 record · AESTDTC
#>     row 2     AESTDTC = "2024-02-30"
#>     CORE-000547  · also SEND66, SEND67, SEND68, ...
#> 
#> ────────────────────────────────────────────────────────────────────────────────
#> 51 checks could not run.
#>   25 need other datasets (DM, POOLDEF, SUPPAE, SV, TA, TO, ...)
#>      → run check_study() on the whole folder to cover these
#>   16 ask what the whole study contains
#>   6 need a define.xml
#>   4 for other reasons, see result$skipped
#> 
#> No standard declared, so rules from every standard ran.
#>   Narrow with  standard = "SDTMIG"  (or "SENDIG", "TIG", ...)
#> 
#> Fix what you can, then run this again.
#> To track the rest:  write_findings(result, "issues.xlsx")
```

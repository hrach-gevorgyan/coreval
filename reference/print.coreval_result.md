# Print a coreval check result as a readable report

Describes each problem in the rule's own words, worst first, with the
rows and values that caused it. A whole-study result is grouped by
dataset, with a summary first, so you can see where the trouble is
before reading detail.

## Usage

``` r
# S3 method for class 'coreval_result'
print(x, n = 10, rows = 3, guidance = FALSE, ...)
```

## Arguments

- x:

  A result from
  [`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md)
  or
  [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md).

- n:

  Maximum problems to describe - per dataset, for a study result. The
  rest are counted, not listed. Default 10.

- rows:

  Maximum example records to show per problem. Default 3.

- guidance:

  Also print the sentence from the Implementation Guide that each rule
  enforces - the "why" behind it. Off by default: it roughly doubles the
  length of the report.

- ...:

  Ignored.

## Value

`x`, invisibly.

## Examples

``` r
ae <- data.frame(
  STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
  AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30")
)
check_dataset(ae)
#> 
#> ── coreval — AE ────────────────────────────────────────────────────────────────
#> 
#> 4 problems across 1 record  (159 checks ran)
#> 
#>   wrong value         2   the data breaks the rule - start here
#>   missing required    1   the standard requires it
#>   missing optional    1   often legitimate: not collected, screen failure, ...
#> 
#> [wrong value]
#> Study Day of Start of Observation (--STDY) variable is missing when Start
#>   Date/Time of Observation (--STDTC) is present.
#>   the dataset · AESTDTC
#>     AESTDTC = "2024-01-10"
#>     CORE-000328  · also FB3202
#> 
#> [wrong value]
#> Variable value is not in correct ISO 8601 date or datetime format
#>   1 record · AESTDTC
#>     row 2     AESTDTC = "2024-02-30"
#>     CORE-000547  · also SEND66, SEND67, SEND68, ...
#> 
#> [missing required]
#> Required variable is missing from the dataset.
#>   the dataset
#>     missing required variables: AEDECOD
#>     CORE-000355  · also CG0014, SEND12, TIG0299, ...
#> 
#> [missing optional]
#> Expected variable is missing from the dataset.
#>   the dataset
#>     missing expected variables: AELLT, AELLTCD, AEPTCD, AEHLT, AEHLTCD, AEHLGT, AEHLGTCD, AEBODSYS, ...
#>     CORE-000334  · also CG0016, TIG0301, SEND13, ...
#> 
#> ────────────────────────────────────────────────────────────────────────────────
#> 48 checks could not run.
#>   24 need other datasets (DM, POOLDEF, SUPPAE, SV, TA, TO, ...)
#>      → run check_study() on the whole folder to cover these
#>   14 ask what the whole study contains
#>   6 need a define.xml
#>   4 for other reasons, see result$skipped
#> 
#> No standard declared, so rules from every standard ran.
#>   Narrow with  standard = "SDTMIG"  (or "SENDIG", "TIG", ...)
#> 
#> Fix what you can, then run this again.
#> To track the rest:  write_findings(result, "issues.xlsx")
```

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
check_dataset(ae, standard = "SDTMIG")
#> 
#> ── coreval — AE ────────────────────────────────────────────────────────────────
#> 
#> 6 problems across 2 records  (154 checks ran)
#> 
#>   wrong value         1   the data breaks the rule - start here
#>   missing required    3   the standard requires it
#>   missing optional    2   often legitimate: not collected, screen failure, ...
#> 
#> [wrong value]
#> Value must be a valid ISO 8601 datetime or interval.
#>   1 record · AESTDTC
#>     row 2  01 seq 2  AESTDTC = "2024-02-30"
#>     CORE-002121  · also CG0011
#> 
#> [missing required]
#> Missing treatment-emergent flag (AETRTEM) for the Adverse Event.
#>   2 records · AETERM, AESTDTC
#>     row 1  01 seq 1  AETERM = "Headache", AESTDTC = "2024-01-10"
#>     row 2  01 seq 2  AETERM = "Rash", AESTDTC = "2024-02-30"
#>     CORE-002034  · also FB0101
#> 
#> [missing required]
#> Study Day of Start of Observation (--STDY) variable is missing when Start
#>   Date/Time of Observation (--STDTC) is present.
#>   the dataset · AESTDTC
#>     AESTDTC = "2024-01-10"
#>     CORE-000328  · also FB3202
#> 
#> [missing required]
#> Required variable is missing from the dataset.
#>   the dataset
#>     missing required variables: AEDECOD
#>     CORE-000355  · also CG0014
#> 
#> [missing optional]
#> EPOCH is missing for clinical subject-level observation.
#>   2 records · EPOCH
#>     not in the dataset: EPOCH
#>     CORE-000701  · also FB2201
#> 
#> [missing optional]
#> Expected variable is missing from the dataset.
#>   the dataset
#>     missing expected variables: AELLT, AELLTCD, AEPTCD, AEHLT, AEHLTCD, AEHLGT, AEHLGTCD, AEBODSYS, ...
#>     CORE-000334  · also CG0016
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

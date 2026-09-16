# Summarize a check result in a few lines

The short form of
[`print.coreval_result()`](https://hrach-gevorgyan.github.io/coreval/reference/print.coreval_result.md),
for when you have run a check inside a script, or just want to know
whether the last fix helped.

## Usage

``` r
# S3 method for class 'coreval_result'
summary(object, ...)
```

## Arguments

- object:

  A result from
  [`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md)
  or
  [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md).

- ...:

  Ignored.

## Value

A one-row
[`data.table::data.table()`](https://rdrr.io/pkg/data.table/man/data.table.html),
invisibly, with the counts it printed - so it can be logged or compared.

## Examples

``` r
ae <- data.frame(
  STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
  AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30")
)
summary(check_dataset(ae))
#> 4 problems across 2 records  (160 checks ran, 51 could not)
#>   wrong value       2
#>   missing required  1
#>   missing optional  1
```

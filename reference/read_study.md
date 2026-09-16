# Read a study into coreval's internal representation

Detects whether `path` is a directory of XPT datasets (a real study) or
a CORE test-case `data/` directory (`_variables.csv` + one CSV per
dataset, usually also `.env` and `_datasets.csv`), and reads either into
the same internal representation, so the evaluator never has to know
which one it got.

## Usage

``` r
read_study(path)
```

## Arguments

- path:

  Directory path.

## Value

A study object:
`list(datasets = <named list of domain -> list(data, meta, label)>, define, ct = NULL, standard = list(product, version))`.
`define` is the parsed Define-XML if one was found in `path` and the
`xml2` package is installed, and `NULL` otherwise; `ct` is always `NULL`
(controlled terminology is not bundled). Each `data` is a
[`data.table::data.table()`](https://rdrr.io/pkg/data.table/man/data.table.html);
each `meta` is a data.table with columns `variable`, `label`, `type`;
`label` is the dataset's own label (e.g. `"Adverse Events"`), or `NA` if
unavailable. `standard` is the study's declared standard/version (e.g.
`list(product = "SDTMIG", version = "3-4")`), read from a CORE test
case's `.env` file - both `NA` for a real XPT-based study (no `.env`).

## Details

Character columns use `""` for blank/missing (never `NA`) to match how
SAS XPT round-trips blanks; numeric columns use `NA`. Column types are
taken from the source (XPT's own types, or `_variables.csv`'s declared
`Char`/`Num`) rather than guessed from the data, so numeric-looking
identifiers (e.g. `"007"`) are never silently coerced.

## Examples

``` r
dir <- tempfile("coreval_study_")
dir.create(dir)
haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
study <- read_study(dir)
study$datasets$DM$data
#>    USUBJID   AGE
#>     <char> <num>
#> 1:       1    30
#> 2:       2    65
unlink(dir, recursive = TRUE)
```

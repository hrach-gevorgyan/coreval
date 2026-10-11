# Read a study into coreval's internal representation

Reads a study folder: SAS transport (`.xpt`) and SAS (`.sas7bdat`)
files, Dataset-JSON (`.json`, `.ndjson`), or a USDM study document, plus
a Define-XML when one is there. A CORE test-case `data/` folder
(`_variables.csv` and one CSV per dataset) is read too. All of them come
out in the same internal representation, so the evaluator never has to
know which one it got.

## Usage

``` r
read_study(path, usdm = FALSE)
```

## Arguments

- path:

  Directory path.

- usdm:

  Read a USDM study design document. `FALSE` by default: USDM is not
  what most studies are checked for, and some of its rules take minutes
  on one file, so it has to be asked for. Without it, a folder holding
  only a USDM document is refused with a message saying so, never read
  as empty.

## Value

A study object:
`list(datasets = <named list of domain -> list(data, meta, label)>, define, ct = NULL, standard = list(product, version))`.
`define` is the parsed Define-XML if one was found in `path` and the
`xml2` package is installed, and `NULL` otherwise; `ct` is always
`NULL`. Each `data` is a
[`data.table::data.table()`](https://rdrr.io/pkg/data.table/man/data.table.html);
each `meta` is a data.table with columns `variable`, `label`, `type`;
`label` is the dataset's own label (e.g. `"Adverse Events"`), or `NA` if
unavailable. `standard` is the study's declared standard/version (e.g.
`list(product = "SDTMIG", version = "3-4")`), read from a CORE test
case's `.env` file or a USDM document, and both `NA` for a folder of
datasets, which does not declare one.

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

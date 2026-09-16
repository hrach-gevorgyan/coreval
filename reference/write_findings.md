# Write conformance findings to a file

Saves the result of
[`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md)
to CSV or Excel, so findings can be shared with people who don't use R,
tracked in a spreadsheet, or attached to a data-review document.

## Usage

``` r
write_findings(result, path, tracking = TRUE)
```

## Arguments

- result:

  A result from
  [`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md)
  or
  [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md).

- path:

  Output file path. The extension decides the format: `.xlsx` for Excel,
  `.csv` (or anything else) for CSV.

- tracking:

  Add the empty `Status`/`Owner`/`Notes` columns. `TRUE` by default; set
  `FALSE` for a file you intend to read back into R.

## Value

The paths actually written, invisibly. One element for Excel (a single
workbook). For CSV, one path per file written: the findings, plus
siblings for `skipped` and `about`, plus one for `truncated` when any
rule flagged more records than were kept.

## Details

Both tables are always written, never just the findings. A short
findings table can mean clean data, or it can mean many rules were
skipped, and those two situations look identical if the skipped table is
dropped:

- **Excel** (`.xlsx`) - one workbook with a sheet per table: `findings`,
  `skipped`, `about`, and `truncated` when any rule matched more records
  than were kept.

- **CSV** (`.csv`) - one file per table, since CSV has no notion of
  sheets. Findings go to `path`; the others go to sibling files with a
  suffix before the extension, so `issues.csv` gives
  `issues_skipped.csv` and `issues_about.csv`.

Excel output needs the `writexl` package. It is a `Suggests`, so if it
isn't installed you get a clear message telling you to install it or use
`.csv` instead, rather than a failure part-way through writing.

## Columns for tracking

Three empty columns are added to the findings - `Status`, `Owner` and
`Notes` - for you to fill in by hand once the file is open. They exist
so a finding you have looked at and decided not to act on ("expected,
see protocol deviation log") can be recorded next to the finding itself,
rather than in a separate document nobody reads.

## Examples

``` r
dir <- tempfile("coreval_study_")
dir.create(dir)
haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
study <- read_study(dir)
result <- check_study(study)

out <- file.path(dir, "findings.csv")
written <- write_findings(result, out)
basename(written)
#> [1] "findings.csv"         "findings_skipped.csv" "findings_about.csv"  

unlink(dir, recursive = TRUE)
```

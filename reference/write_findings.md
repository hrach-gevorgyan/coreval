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

  Add the empty tracking columns. `TRUE` by default; set `FALSE` for a
  file you intend to read back into R.

## Value

The paths actually written, invisibly. One element for Excel (a single
workbook). For CSV, one path per file written: the findings, plus
siblings for `skipped`, `about` and `summary`, plus one for `truncated`
when any rule flagged more records than were kept.

## Details

Both tables are always written, never just the findings. A short
findings table can mean clean data, or it can mean many rules were
skipped, and those two situations look identical if the skipped table is
dropped:

- **Excel** (`.xlsx`) - four sheets laid out for a person to read:

  - `Problems`: one row per problem, definite errors first, then the
    ones touching most records. What is wrong and the rule's number, the
    variables it names (or the missing ones), and how many records it
    affects, or `whole dataset`.

  - `Records`: one row per affected record and problem, in the order of
    `Problems`, with `USUBJID`, `SEQ` and the values, such as
    `AESTDTC = "2024-02-30"`. A dataset with no subject gives the row
    instead.

  - `Not checked`: the checks that could not run, grouped by reason,
    with what to do about each, then when and how the check was run.

  - `Rules`: every rule, and whether it found problems, found none or
    could not run. A rule that found nothing appears nowhere else.

- **CSV** (`.csv`) - the tables as they are in R, for reading back into
  a program. Findings go to `path`; the others go to sibling files with
  a suffix before the extension, so `issues.csv` gives
  `issues_skipped.csv`, `issues_about.csv` and `issues_summary.csv` (one
  row per problem).

An existing file at `path`, or at a sibling path, is replaced.

In CSV files, a text value that begins with `=`, `+`, `-` or `@` and is
not a plain number is written with a leading `'`. Findings quote the
submission data, and a spreadsheet program opening the CSV would
otherwise run such a value as a formula. Excel files store every value
as text and need no such change. CSV files are written as UTF-8 with a
byte order mark, which Excel needs to show non-English text correctly.

Excel output needs the `writexl` package. It is a `Suggests`, so if it
isn't installed you get a clear message telling you to install it or use
`.csv` instead, rather than a failure part-way through writing.

## Columns for tracking

Empty columns are added for you to fill in by hand once the file is
open: `Status` and `Notes` on `Problems` and `Notes` on `Records` in
Excel, `Status`, `Owner` and `Notes` in CSV. They exist so a finding you
have looked at and decided not to act on ("expected, see protocol
deviation log") can be recorded next to the finding itself, rather than
in a separate document nobody reads.

## Examples

``` r
dir <- tempfile("coreval_study_")
dir.create(dir)
haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
study <- read_study(dir)
result <- check_study(study, standard = "SDTMIG")

out <- file.path(dir, "findings.csv")
written <- write_findings(result, out)
basename(written)
#> [1] "findings.csv"         "findings_skipped.csv" "findings_about.csv"  
#> [4] "findings_summary.csv"

unlink(dir, recursive = TRUE)
```

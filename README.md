# coreval <img src="man/figures/logo.png" align="right" height="132" alt="" />

<!-- badges: start -->
[![CRAN status](https://www.r-pkg.org/badges/version/coreval)](https://CRAN.R-project.org/package=coreval)
[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/license/mit)
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
<!-- badges: end -->

**Check your SDTM, SEND and USDM data against CDISC's rules, without leaving R.**

You've just written the code that builds a dataset. Before you export it and
send it off to a validation tool, coreval tells you what's wrong with it, in
plain words, in a few seconds, on your own machine.

It uses CDISC's own published conformance rules. It doesn't replace your
validated tool; it means that tool finds far less.

## What it looks like

```r
library(coreval)

dm <- data.frame(
  STUDYID = "STUDY1",
  DOMAIN  = "DM",
  USUBJID = c("STUDY1-001", "STUDY1-002", "STUDY1-003"),
  RFSTDTC = c("2024-01-15", "2024-13-01", "2024-02-03"),
  AGE     = c(34, 51, 47),
  AGEU    = c("YEARS", "YEARS", "")
)

check_dataset(dm)
```

```
── coreval — DM ────────────────────────────────────────────────────────────

6 problems across 4 records  (164 checks ran)

  wrong value         3   the data breaks the rule - start here
  missing required    1   the standard requires it
  missing optional    2   often legitimate: not collected, screen failure, ...

[wrong value]
AGEU is missing when AGE is provided.
  1 record · AGE, AGEU
    row 3     AGE = "47", AGEU = (empty)
    CORE-000189  · also CG0665, TIG0699

[wrong value]
Variable value is not in correct ISO 8601 date or datetime format
  1 record · RFSTDTC
    row 2     RFSTDTC = "2024-13-01"
    CORE-000547  · also SEND66, SEND67, SEND68, ...

  ... and 4 more here. See result$findings for all of them.
```

Each problem says what's wrong, which row, and the value that caused it. The
rule number is there if you want to look it up, along with the older IDs that
Pinnacle 21 uses for the same rule.

Problems are sorted so the ones that are **definitely wrong** come first. A
month of 13 is a bug. A blank value might be perfectly fine for your study,
so those come last.

## Install

```r
install.packages("coreval")
```

It needs R 4.1 or newer. A few extras switch on more checks, and coreval tells
you when a check was skipped because one is missing:

```r
install.packages(c("xml2", "jsonlite", "QuickJSR", "writexl"))
```

`xml2` reads Define-XML, `jsonlite` and `QuickJSR` read USDM study files, and
`writexl` saves results to Excel.

## The three things you'll use

**Check one dataset** while you're writing code. Give it a data frame or a file
(`.xpt`, `.sas7bdat`, `.csv`):

```r
result <- check_dataset(dm)
```

**Check a whole study** when you have the folder. This is the only way to run
the rules that compare one dataset with another, like an adverse event date
against the subject's reference dates in DM:

```r
result <- check_study("path/to/sdtm")
```

**Save what's left to fix** as a spreadsheet, with empty Status, Owner and
Notes columns for tracking:

```r
write_findings(result, "issues.xlsx")
```

## It tells you what it couldn't check

A clean report can mean two things: your data is fine, or half the rules never
ran. coreval never lets those look the same. Every result lists the checks it
had to skip and says why, for example because they need a dataset you didn't
provide:

```
60 checks could not run.
  33 need other datasets (AE, AG, CM, DD, DS, EX, ...)
     → run check_study() on the whole folder to cover these
  16 ask what the whole study contains
  7 need a define.xml
```

If nothing could be checked at all, it stops with an error instead of printing
a clean report.

## What it covers

coreval ships **1,054 CDISC conformance rules** for SDTM, SEND, the Tobacco
Implementation Guide, and USDM study designs. Most are published; some are
CDISC drafts, and retired rules are included but only run if you ask for them.

Where CDISC publishes a worked example for a rule, coreval was run against it,
and more than nine in ten come back with exactly the answer CDISC gives.
[docs/COVERAGE.md](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/COVERAGE.md)
goes through the rest, one by one.

It reads XPT, SAS, CSV and Dataset-JSON datasets, Define-XML, and USDM study
files. Nothing is downloaded and no account or API key is needed. The rules
are bundled with the package.

**What it doesn't do yet:**

- **ADaM.** CDISC publishes no worked examples for its ADaM rules, so there's
  no way to show they'd be right.
- **Medical dictionaries.** It can't check that a term exists in your licensed
  MedDRA or WHODrug dictionary.
- **Terminology without a version.** Rules about allowed values need to know
  which Controlled Terminology release your study uses. It's read from your TS
  dataset, or you can pass `ct_package = "sdtmct-2026-03-27"`.

## Learn more

- **Getting started guide:** `vignette("coreval")` walks through a real
  session, reading results, narrowing to one standard, and looking up a rule.
- **Every function** is documented: `?check_dataset`, `?check_study`,
  `?write_findings`, `?list_rules`, `?filter_findings`, `?read_study`,
  `?list_ct_packages`.
- [**docs/**](https://github.com/hrach-gevorgyan/coreval/tree/master/docs) has
  the detail: which rules pass and why, how CDISC's own engine behaves, speed
  benchmarks, and the design decisions.

## Please read this

coreval is an independent, personal open-source project. It is **not** a CDISC
product, not endorsed by CDISC, and not a certified CORE engine. It is not
validated software. A clean result here doesn't mean a submission will be
accepted, and it doesn't replace your organisation's own validation. Treat it
as a fast first check while you work.

Found a wrong or missing result? That's the most useful thing you can report.
[Open an issue](https://github.com/hrach-gevorgyan/coreval/issues), ideally
with a small dataset that shows it. Please read the
[Code of Conduct](https://github.com/hrach-gevorgyan/coreval/blob/master/CODE_OF_CONDUCT.md)
first.

## License

The package code is MIT. The bundled rules and standards data come from
CDISC's MIT-licensed [cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
and [cdisc-rules-engine](https://github.com/cdisc-org/cdisc-rules-engine)
repositories. Two other bundled pieces carry their own permissive licences: the
W3C's XHTML schemas, used to check narrative text in USDM files, and IBM's
JSONata, used to run some USDM rules. Every bundled file, where it came from
and its licence are listed in `inst/COPYRIGHTS`.

CDISC, CORE, SDTM, SEND, ADaM, Define-XML and TIG are trademarks of the
Clinical Data Interchange Standards Consortium, used here only to name the
standards this package reads.

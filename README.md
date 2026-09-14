# coreval <img src="man/figures/logo.png" align="right" height="132" alt="" />

<!-- badges: start -->
[![CRAN status](https://www.r-pkg.org/badges/version/coreval)](https://CRAN.R-project.org/package=coreval)
[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/license/mit)
[![Lifecycle: stable](https://img.shields.io/badge/lifecycle-stable-brightgreen.svg)](https://lifecycle.r-lib.org/articles/stages.html#stable)
<!-- badges: end -->

**Check your SDTM data against CDISC rules without leaving R.**

You just finished writing your DM code. You have a data frame. Check it:

```r
library(coreval)

check_dataset(dm)
```

```
── coreval — DM ────────────────────────────────────────────────────────────

9 problems across 6 records  (170 checks ran)

  wrong value         4   the data breaks the rule - start here
  missing required    2   the standard requires it
  missing optional    3   often legitimate: not collected, screen failure, ...

[wrong value]
Variable value is not in correct ISO 8601 date or datetime format
  2 records · RFSTDTC
    row 4     RFSTDTC = "2024-13-01"
    row 3     RFSTDTC = (empty)
    CORE-000547  · also SEND66, SEND67, SEND68, ...

[wrong value]
AGEU is missing when AGE is provided.
  1 record · AGE, AGEU
    row 3     AGE = "47", AGEU = (empty)
    CORE-000189  · also CG0665, TIG0699

  ... and 7 more here. See result$findings for all of them.

────────────────────────────────────────────────────────────────────────────
53 checks could not run.
  33 need other datasets (AE, AG, CM, DD, DS, EX, ...)
     → run check_study() on the whole folder to cover these
  18 need a define.xml
  2 for other reasons, see result$skipped

No standard declared, so rules from every standard ran.
  Narrow with  standard = "SDTMIG"  (or "SENDIG", "TIG", ...)

Fix what you can, then run this again.
To track the rest:  write_findings(result, "issues.xlsx")
```

It tells you **what's wrong in words**, which rows, which variables, and the
actual values. No export, no upload, no waiting, no looking rule numbers up in
a PDF.

### About that ordering

**CDISC Open Rules carry no severity field.** I checked the source. There is
nothing like Pinnacle 21's Notes / Minor / Major / Critical. That's P21's own
layer, not CDISC's, so coreval can't report a CDISC severity and won't invent
one.

What it does instead is separate the findings that are *definitely* wrong from
the ones that might be perfectly fine:

| | What it means |
|---|---|
| **wrong value** | Your data contains something that breaks the rule: a month of 13, a value outside its codelist, two variables contradicting each other. Nothing about your study explains these away. **Start here.** |
| **missing required** | Something the standard marks Required isn't there. |
| **missing optional** | Something Expected or Permissible is absent, or a value is blank. Often legitimate: a screen-failure subject with no reference dates, a variable your raw data doesn't carry yet. |

That last row is the point. An empty `RFSTDTC` is not the same kind of problem
as `RFSTDTC = "2024-13-01"`, and sorting by "how many rows are affected" puts
them in the wrong order. coreval sorts by this first, row count second, and
within a problem, it shows you the row with the real bad value before the row
that's merely empty.

This is coreval's own triage, not a regulatory grading. It's a `triage` column
on every finding, so you can sort by it in the spreadsheet too.

---

## The workflow this is built for

You're a programmer. You've just written the code that builds DM. You don't
want to export transport files and open Pinnacle 21 to find out you left a
month of 13 in a date.

```r
result <- check_dataset(dm)   # 1. see what's wrong, in plain language
                              # 2. fix what you can
result <- check_dataset(dm)   # 3. run it again, it takes a second

write_findings(result, "dm_issues.xlsx")   # 4. track what's left
```

Step 4 gives you a spreadsheet with the problem described in words, plus empty
`Status`, `Owner` and `Notes` columns to fill in, so "expected, see protocol
deviation log" gets recorded next to the finding instead of in some other
document.

Then the full run still happens: you or your study lead runs the whole study
through your qualified tool. **This doesn't replace that, and isn't trying
to.** It just means the expensive check finds far less, and you found the
obvious things in seconds instead of half an hour.

## Install

```r
install.packages("coreval")
```

Or the development version, if you want something that isn't in a release yet:

```r
# install.packages("pak")
pak::pak("hrach-gevorgyan/coreval")
```

Needs R 4.1 or newer. Only `data.table` and `haven` to run. Two optional extras:

```r
install.packages("xml2")     # to read Define-XML, and to check XHTML in USDM
install.packages("jsonlite") # to read Dataset-JSON and USDM
install.packages("QuickJSR") # to run the USDM rules written in JSONata
install.packages("writexl")  # to write .xlsx
```

---

## Checking one dataset

This is the one to reach for while you're writing code. Pass a data frame:

```r
ae <- data.frame(
  STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
  AESEQ   = c(1, 2),
  AETERM  = c("Headache", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30")
)

result <- check_dataset(ae)
```

Or a file. `.xpt`, `.sas7bdat` or `.csv`:

```r
result <- check_dataset("ae.xpt")
```

coreval works out the domain from your `DOMAIN` column, and falls back to the
file name only when the data has no `DOMAIN` column at all. That order matters
for a split dataset: `ae1.xpt` is checked as `AE` because its `DOMAIN` column
says so. On a file with no `DOMAIN` column, the name `ae1` is taken at face
value. If it guesses wrong, tell it:

```r
result <- check_dataset(ae, domain = "AE")
```

### The catch, and it's an important one

Plenty of CDISC rules compare **one dataset against another**: an AE date
against the subject's reference dates in DM, a visit against the trial design.
Hand coreval a single dataset and those rules simply cannot be answered.

coreval doesn't guess. It skips them, and tells you which dataset it wanted:

```r
head(result$skipped, 3)
#>       rule_id domain                                        reason
#> 1 CORE-000138     AE  needs DM, which was not supplied - check ...
#> 2 CORE-000139     AE  needs DM, which was not supplied - check ...
#> 3 CORE-000140     AE  needs TV, which was not supplied - check ...
```

Running them anyway would compare your data against columns that aren't there
and report problems that don't exist. Better to say nothing than to make
something up.

Most rules do still run. Measured across AE, DM, LB and VS, **76–84%** of the
applicable rules work on the dataset alone. But the ones that can't are the
cross-dataset checks, and those often matter most.

> **A short findings list here doesn't mean your data is clean.** It's a quick
> first pass while you code. Run the whole study before you draw conclusions.

---

## Checking a whole study

When you do have the full folder:

```r
result <- check_study("path/to/study/sdtm")
```

A **folder**, not a file. coreval reads everything in it, XPT, SAS, CSV or
Dataset-JSON, whichever you have, and reading it all at once is what makes the
cross-dataset rules possible. If there's a Define-XML in there, it finds it and
uses it.

Dataset-JSON is CDISC's successor to transport files, and both shapes of it are
read: one `.json` per dataset, or `.ndjson` with the metadata on the first line
and a row on each line after. A folder holding transport files *and* a
Dataset-JSON of the same data is read as XPT, on the grounds that a folder
holding both is a conversion in progress.

A **USDM** study is the other thing a folder can hold: one JSON document
describing a study design rather than a set of datasets. Its rules come in two
shapes and both run. 96 are written as JSONata expressions over the document
itself, and 157 are ordinary record checks over the document read as one table
per entity, flattened the way CDISC's own engine flattens it.

If you want to look at what was parsed, or check the same large study twice
without re-reading it, do the read yourself:

```r
study <- read_study("path/to/study/sdtm")
names(study$datasets)
#> [1] "AE" "CM" "DM" "EX" "LB" "VS"

check_study(study)
```

A study report is grouped by dataset, and tells you where the trouble is before
showing you any detail. The shape is what matters here. The counts depend on
your study:

```
── coreval ─────────────────────────────────────────────────────────────

27 problems across 12 records in 4 datasets  (689 checks ran)

  DM           9 problems    4 records
  AE           7 problems    4 records
  VS           7 problems    3 records
  STUDY        4 problems    1 record

── DM ──────────────────────────────────────────────────────────────────

SUBJID is not unique within study
  3 records · SUBJID
    not in the dataset: SUBJID
    CORE-000186
...
```

`print(result, n = 20)` shows more problems per dataset; `rows = 5` shows more
example records per problem.

---

## Reading the results

You get two tables. **Both matter.**

Printing the result gives you the readable report above. The raw rows are in
`result$findings`, ready to filter, count, or feed somewhere else:

### `result$findings`: what's wrong

```r
head(result$findings[, c("Dataset", "Record", "Variable", "Value", "triage", "rule_id")])
#>  Dataset Record Variable          Value           triage     rule_id
#>       AE      2  AESTDTC     2024-02-30      wrong value CORE-000547
#>       AE      2  RFSTDTC Not in dataset      wrong value CORE-000547
#>       AE      1   AESTDY Not in dataset missing optional CORE-000328
```

(`issue` is dropped from that view only so the table fits the page. It is
there on every row, and it is the column worth reading.)

One row per affected record, pointing at the exact spot:

| Column | What it tells you |
|---|---|
| `Dataset` | Which dataset (or `STUDY` for whole-study checks) |
| `Record` | Row number, counting from 1 |
| `Variable` | The variable being complained about |
| `Value` | What was actually in there |
| `issue` | **What's wrong, in words**. The rule's own description |
| `triage` | `wrong value`, `missing required` or `missing optional` |
| `rule_id` | The CDISC rule, if you need to look it up |

`Not in dataset` under `Value` means the rule wanted a variable you don't have
which is usually the point.

### `result$skipped`: what couldn't be checked

```r
head(result$skipped)
#>       rule_id domain                                    reason
#> 1 CORE-000916     AE  Match Datasets: unsupported join type...
```

**This is the one people skip, and it's the one that bites.** An empty findings
table means one of two things: your data is clean, or half the rules never ran.
Those look identical if you only read `findings`. coreval always shows you both.

### Saving it, and tracking what you didn't fix

```r
write_findings(result, "issues.xlsx")   # one workbook, several sheets
write_findings(result, "issues.csv")    # issues.csv + siblings
```

You get `findings`, `skipped`, an `about` sheet, and `truncated` if any rule
matched more records than were kept. Both tables get written every time, for
the reason above. `about` carries the provenance **with the file**: which
standard it was scoped to, how many checks ran, whether it was filtered before
export, and whether any counts were capped. A shared spreadsheet outlives the
console session that made it, and whoever opens it can't see what you saw.

Every findings column comes across: `Dataset`, `Record`, `Variable`, `Value`,
`issue`, `triage`, `rule_id`, followed by three empty ones, `Status`, `Owner`
and `Notes`, for you to fill in once it's open. Not every finding is a bug you'll fix: some are expected, some
belong to someone else, some are waiting on a data query. Those decisions belong
next to the finding, not in a separate document nobody opens.

```
Dataset  Record  Variable  Value        issue                          rule_id      Status   Owner  Notes
DM       4       RFSTDTC   2024-13-01   Variable value is not in ...   CORE-000547
DM       3       AGE       47           AGEU is missing when AGE ...   CORE-000189
```

Pass `tracking = FALSE` if you're reading the file back into R and don't want
the extra columns.

---

## The whole API

Six functions. Three of them do the work:

| | |
|---|---|
| `check_dataset(x)` | check one dataset: a data frame, or an `.xpt` / `.sas7bdat` / `.csv` |
| `check_study(path)` | check a whole folder |
| `write_findings(result, path)` | save to Excel or CSV, with tracking columns |

The other three are there when you need them:

| | |
|---|---|
| `list_rules()` | the rule set. Also `list_rules(id = ...)` to look up a rule the report named, and `list_rules(domain = "AE")` for what applies where |
| `filter_findings(result, ...)` | narrow a result by triage, dataset, rule or variable |
| `read_study(path)` | read a folder yourself, if you want to inspect it or check it twice without re-reading |

Plus `print()` and `summary()` on a result. `print()` is what you get by
typing the result's name; `summary()` you call yourself, and it returns a
one-row table you can rbind across datasets.

That's it. If you only ever learn `check_dataset()` and `write_findings()`,
you have most of the value.

---

## Recipes

**What does CORE-000547 actually mean?**

```r
rule <- list_rules(id = "CORE-000547")

rule$issue
#> [1] "Variable value is not in correct ISO 8601 date or datetime format"
rule$legacy_ids
#> [1] "SEND66, SEND67, SEND68, TIG0267, TIG0268, TIG0269"
rule$guidance
#> [1] "The SENDIG requires dates and times of day to be stored according to the
#>     international standard ISO 8601  (SENDIG v3.0 4.4)"
rule$standard
#> [1] "SENDIG, SENDIG-DART, SENDIG-GENETOX, TIG"
```

`list_rules()` always returns a data frame with one row per rule, so pick the
columns you want off it. (`t(rule)` gives the whole row as a column, which is
often easier to read for a single rule.)

Three things worth knowing here:

- **`legacy_ids`** are what Pinnacle 21 and the published Conformance Rules
  spreadsheets call the same rule. That's how you match a coreval finding to a
  P21 report, including to a severity CDISC itself doesn't publish. The
  console report shows them too: `CORE-000189 · also CG0665, TIG0699`.
- **`guidance`** is the sentence from the Implementation Guide the rule exists
  to enforce: the *why*, which no rule message carries. `print(result,
  guidance = TRUE)` shows it under each problem; it's off by default because it
  roughly doubles the report's length.
- Every bundled rule carries both.

**Just the things that are definitely wrong**

```r
filter_findings(result, triage = "wrong value")
```

Returns a result, so it prints as a report. Also takes `dataset`, `rule` and
`variable`.

**A three-line summary, for a script**

```r
summary(result)   # result <- check_dataset(dm), the DM frame from the top
#>   problems records wrong_value missing_required missing_optional
#> 1        9       6           4                2                3
#>   checks_run could_not_run capped_rules
#> 1        170            53            0
```

It returns a one-row data frame rather than printing, so it stacks: `rbind()`
one per dataset and you have a table of where the trouble is.

**Which rules even apply to AE?**

```r
list_rules(domain = "AE")
```

**Only the rules for my standard and IG version**

```r
result <- check_dataset(dm, standard = "SDTMIG", version = "3.4")
```

Rules are written per Implementation Guide version, so this cuts the list
sharply. For DM: 134 rules for SDTMIG generally, 96 for 3.2, 132 for 3.4.

It can cut too far. CDISC's coverage is uneven: the general "dates must be
valid ISO 8601" rule is published for SENDIG and TIG but **not** for SDTMIG,
so narrowing to SDTMIG can stop a real problem being reported. The report
always says how many rules it set aside. Leave `standard` unset if you would
rather see everything.

**Only the fully-vetted rules, no drafts**

```r
subset(list_rules(), source == "published")
```

**Which rule version am I running?**

```r
attr(list_rules(), "rules_version")
#> [1] "1fb7b81e40bdb6632375761c561fabd29676a477"
```

`write_findings()` records it in every exported file, so you rarely need to
ask.

That's the exact CDISC commit the bundled rules came from. Worth recording next
to your results.

**Just the AE findings**

```r
subset(result$findings, Dataset == "AE")
```

**What's failing most?**

```r
sort(table(result$findings$rule_id), decreasing = TRUE)
```

**How many records are actually affected?**

```r
nrow(unique(result$findings[, c("Dataset", "Record")]))
```

---

## What's covered, and how much is proven

CDISC publishes 1,348 rules. coreval ships the **1,054** that come with a
worked example to check against: the tabular SDTM/SEND/TIG rules, and the USDM
study-design rules. What is left out is ADaM, where CDISC ships 197 rules and
no reference results at all.

Every bundled rule falls into exactly one of four buckets:

| | rules | |
|---|---|---|
| **Confirmed** | **957** | Run against CDISC's own example data, and flagged the rows their answer sheet says. No more, no fewer. |
| Nothing to check against | 41 | CDISC ships no usable answer, or the rule needs something coreval does not do. |
| Blocked on data not shipped | 1 | The rule and the answer sheet are both fine. A piece of Define-XML detail is missing. |
| Still disagreeing | 55 | coreval flags different rows than the answer sheet says. |

**Of the rules anyone can confirm at all: 957 of 1,013, 94%.**

Those 55 deserve a word, because the obvious reading is wrong. 27 are
deprecated rules that never run by default. Of the 16 published ones, **all 16
were checked by installing CDISC's own engine and running it: coreval matched
the engine on every one, and the committed answer sheet differed from the
engine on every one.** The sheets in CDISC's repository were generated by an
earlier build of the engine and are not regenerated when it changes, so a
difference from a sheet is usually a versioning gap rather than a claim about
the rule.

[**docs/COVERAGE.md**](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/COVERAGE.md) has the rule-by-rule detail: which 55,
why each one, and the three mechanical signatures that prove a sheet stale.
[**docs/REFERENCE-BEHAVIOUR.md**](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/REFERENCE-BEHAVIOUR.md) records how the
reference actually behaves, since most surprises turn out to be the engine
doing something unexpected rather than coreval being wrong.

**Do not read 88% as a quality score.** CDISC's examples are mostly simple,
single-file datasets, so they exercise little of what a real submission does. A
bug that silently switched off a third of the rules on split-domain studies
moved that number by zero. It is a lower bound on defects, not a readiness
signal.

### Where it's weak

- **Terminology needs a version.** Nine rules ask whether a value is a legal
  term. Every published CT package is bundled, and the version is read from
  your TS (`TSVCDVER`), but if the study declares none, pass
  `ct_package = "sdtmct-2026-03-27"` or those rules skip and say so.
- **ADaM is absent**, and that is not a design choice. CDISC publishes 197
  ADaM rules and no reference results for any of them. Shipping them would mean
  shipping checks nobody has validated.
- **One tool, one opinion.** Run your qualified validator before you submit.
  This is the fast pass while you are still writing the code.

### Keeping up with CDISC

The rules are pinned to one exact commit of CDISC's repository, recorded in
`attr(list_rules(), "rules_version")` and written into every file
`write_findings()` saves. Nothing is downloaded at run time, so a result is
always traceable to the rule set that produced it.

## What this is, and isn't

I built coreval to stop wasting my own time, and I'm sharing it in case it saves
yours.

**It is an independent, personal open-source project.** Not a CDISC product, not
affiliated with CDISC, not endorsed by CDISC, and not a CORE-certified engine.

It is **not** qualified or validated software, and not a substitute for it. A
clean run here doesn't mean your submission will be accepted, and a finding here
doesn't mean it'll be rejected. It doesn't replace your organisation's own
validation procedures.

What it *is*: a fast local check that catches the obvious problems while you're
still writing the code, and that tells you when it couldn't check
something.

## Status

The seven exported functions are stable: `check_dataset()`, `check_study()`,
`read_study()`, `list_rules()`, `list_ct_packages()`, `filter_findings()` and
`write_findings()`. Their arguments and the shape of what they return will not
change without a deprecation cycle. See [NEWS.md](https://github.com/hrach-gevorgyan/coreval/blob/master/NEWS.md).

## Going deeper

| | |
|---|---|
| [docs/COVERAGE.md](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/COVERAGE.md) | which rules pass, which disagree, and why |
| [docs/REFERENCE-BEHAVIOUR.md](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/REFERENCE-BEHAVIOUR.md) | how CDISC's own engine behaves, with the evidence |
| [docs/BENCHMARKS.md](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/BENCHMARKS.md) | speed and memory against the reference, and how to reproduce it |
| [docs/DECISIONS.md](https://github.com/hrach-gevorgyan/coreval/blob/master/docs/DECISIONS.md) | why it is built this way, and what was tried and rejected |

## Contributing

Issues and pull requests welcome, especially a dataset that produces a wrong or
missing finding. That's the most useful bug report there is. Please read the
[Code of Conduct](https://github.com/hrach-gevorgyan/coreval/blob/master/CODE_OF_CONDUCT.md) first.

## License

Package code is MIT ([LICENSE.md](https://github.com/hrach-gevorgyan/coreval/blob/master/LICENSE.md)). The bundled rule definitions
and standards metadata come from two MIT-licensed CDISC repositories,
[cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules) and
[cdisc-rules-engine](https://github.com/cdisc-org/cdisc-rules-engine), and are
used under that licence. Both required notices, the exact commits each release
was built from, and a file-by-file breakdown are in `inst/COPYRIGHTS`, which
ships with the installed package. See also [NOTICE.md](https://github.com/hrach-gevorgyan/coreval/blob/master/NOTICE.md).

Nothing is downloaded. No CDISC Library API key, no account, no network, at
build time or at run time.

CDISC, CORE, SDTM, SEND, ADaM, Define-XML and TIG are trademarks of the
Clinical Data Interchange Standards Consortium, used here only to identify the
standards this package reads. Not affiliated with, endorsed by, or certified by
CDISC.

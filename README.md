# coreval

<!-- badges: start -->
[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Check your SDTM data against CDISC rules without leaving R.**

You just finished writing your DM code. You have a data frame. Check it:

```r
library(coreval)

check_dataset(dm)
```

```
── coreval — DM ────────────────────────────────────────────────────────────

9 problems across 6 records  (167 checks ran)

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
45 checks could not run.
  30 need other datasets (AE, AG, CM, DD, DS, EX, ...)
     → run check_study() on the whole folder to cover these
  15 need a define.xml

No standard declared, so rules from every standard ran.
  Narrow with  standard = "SDTMIG"  (or "SENDIG", "TIG", ...)

Fix what you can, then run this again.
To track the rest:  write_findings(result, "issues.xlsx")
```

It tells you **what's wrong in words**, which rows, which variables, and the
actual values. No export, no upload, no waiting, no looking rule numbers up in
a PDF.

### About that ordering

**CDISC Open Rules carry no severity field.** I checked the source — there's
nothing like Pinnacle 21's Notes / Minor / Major / Critical. That's P21's own
layer, not CDISC's, so coreval can't report a CDISC severity and won't invent
one.

What it does instead is separate the findings that are *definitely* wrong from
the ones that might be perfectly fine:

| | What it means |
|---|---|
| **wrong value** | Your data contains something that breaks the rule — a month of 13, a value outside its codelist, two variables contradicting each other. Nothing about your study explains these away. **Start here.** |
| **missing required** | Something the standard marks Required isn't there. |
| **missing optional** | Something Expected or Permissible is absent, or a value is blank. Often legitimate — a screen-failure subject with no reference dates, a variable your raw data doesn't carry yet. |

That last row is the point. An empty `RFSTDTC` is not the same kind of problem
as `RFSTDTC = "2024-13-01"`, and sorting by "how many rows are affected" puts
them in the wrong order. coreval sorts by this first, row count second — and
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
result <- check_dataset(dm)   # 3. run it again — it takes a second

write_findings(result, "dm_issues.xlsx")   # 4. track what's left
```

Step 4 gives you a spreadsheet with the problem described in words, plus empty
`Status`, `Owner` and `Notes` columns to fill in — so "expected, see protocol
deviation log" gets recorded next to the finding instead of in some other
document.

Then the full run still happens: you or your study lead runs the whole study
through your qualified tool. **This doesn't replace that, and isn't trying
to.** It just means the expensive check finds far less, and you found the
obvious things in seconds instead of half an hour.

## Install

```r
# install.packages("pak")
pak::pak("hrach-gevorgyan/coreval")
```

Needs R 4.1 or newer. Only `data.table` and `haven` to run. Two optional extras:

```r
install.packages("xml2")     # to read Define-XML
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

Or a file — `.xpt`, `.sas7bdat` or `.csv`:

```r
result <- check_dataset("ae.xpt")
```

coreval works out the domain from your `DOMAIN` column, or from the file name if
there isn't one. So a split dataset in `ae1.xpt` is still checked as `AE`. If it
guesses wrong, tell it:

```r
result <- check_dataset(ae, domain = "AE")
```

### The catch, and it's an important one

Plenty of CDISC rules compare **one dataset against another** — an AE date
against the subject's reference dates in DM, a visit against the trial design.
Hand coreval a single dataset and those rules simply cannot be answered.

coreval doesn't guess. It skips them, and tells you which dataset it wanted:

```r
head(result$skipped, 3)
#>       rule_id domain                                        reason
#> 1 CORE-000138     AE  needs DM, which was not supplied - check ...
#> 2 CORE-000140     AE  needs TV, which was not supplied - check ...
#> 3 CORE-000168     AE  needs SV, which was not supplied - check ...
```

Running them anyway would compare your data against columns that aren't there
and report problems that don't exist. Better to say nothing than to make
something up.

Most rules do still run — measured across AE, DM, LB and VS, **76–84%** of the
applicable rules work on the dataset alone. But the ones that can't are the
cross-dataset checks, and those often matter most.

> **A short findings list here doesn't mean your data is clean.** It's a quick
> first pass while you code. Run the whole study before you draw conclusions.

---

## Checking a whole study

When you do have the full folder:

```r
study  <- read_study("path/to/study/sdtm")
result <- check_study(study)
```

`read_study()` takes a **folder**, not a file, and reads everything in it — XPT,
SAS, CSV, whichever you have:

```r
names(study$datasets)
#> [1] "AE" "CM" "DM" "EX" "LB" "VS"
```

Reading everything at once is what makes the cross-dataset rules possible. If
there's a Define-XML in the folder, coreval finds it and uses it.

A study report is grouped by dataset, and tells you where the trouble is before
showing you any detail:

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

Printing the result gives you the readable report above. When you want the raw
rows — to filter, count, or feed somewhere else — they're in `result$findings`:

### `result$findings` — what's wrong

```r
head(result$findings)
#>   Dataset Record Variable      Value                                    issue     rule_id
#> 1      AE      3  AESTDTC 2013-02-30  Variable value is not in correct ISO ... CORE-000005
#> 2      DM      7     AGEU             AGEU is missing when AGE is provided.    CORE-000112
```

One row per problem, pointing at the exact spot:

| Column | What it tells you |
|---|---|
| `Dataset` | Which dataset (or `STUDY` for whole-study checks) |
| `Record` | Row number, counting from 1 |
| `Variable` | The variable being complained about |
| `Value` | What was actually in there |
| `issue` | **What's wrong, in words** — the rule's own description |
| `rule_id` | The CDISC rule, if you need to look it up |

`Not in dataset` under `Value` means the rule wanted a variable you don't have
— which is usually the point.

### `result$skipped` — what couldn't be checked

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
the reason above — and `about` carries the provenance **with the file**: which
standard it was scoped to, how many checks ran, whether it was filtered before
export, and whether any counts were capped. A shared spreadsheet outlives the
console session that made it, and whoever opens it can't see what you saw.

The file has three empty columns — `Status`, `Owner`, `Notes` — for you to fill
in once it's open. Not every finding is a bug you'll fix: some are expected, some
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

## Recipes

**What does CORE-000547 actually mean?**

```r
rule_info("CORE-000547")
#> issue      Variable value is not in correct ISO 8601 date or datetime format
#> legacy_ids SEND66, SEND67, SEND68, TIG0267, TIG0268, TIG0269
#> guidance   The SENDIG requires dates and times of day to be stored according
#>            to the international standard ISO 8601  (SENDIG v3.0 4.4)
#> standard   SENDIG, TIG
```

Three things worth knowing here:

- **`legacy_ids`** are what Pinnacle 21 and the published Conformance Rules
  spreadsheets call the same rule. That's how you match a coreval finding to a
  P21 report — including to a severity CDISC itself doesn't publish. The
  console report shows them too: `CORE-000189 · also CG0665, TIG0699`.
- **`guidance`** is the sentence from the Implementation Guide the rule exists
  to enforce — the *why*, which no rule message carries. `print(result,
  guidance = TRUE)` shows it under each problem; it's off by default because it
  roughly doubles the report's length.
- All 756 rules carry both.

**Just the things that are definitely wrong**

```r
filter_findings(result, triage = "wrong value")
```

Returns a result, so it prints as a report. Also takes `dataset`, `rule` and
`variable`.

**A three-line summary, for a script**

```r
summary(result)
#> 5 problems across 4 records  (111 checks ran, 21 could not)
#>   wrong value       2
#>   missing required  1
#>   missing optional  2
```

**Which rules even apply to AE?**

```r
rules_for_domain("AE")
```

**Only the rules for my standard and IG version**

```r
result <- check_dataset(dm, standard = "SDTMIG", version = "3.4")
```

Rules are written per Implementation Guide version, so this genuinely narrows
what runs — for DM: 132 rules for SDTMIG generally, 94 for 3.2, 130 for 3.4.

Worth knowing: this genuinely narrows what runs, and the report tells you how
many rules it set aside. CDISC's coverage is uneven — the general "dates must be
valid ISO 8601" rule is published for SENDIG and TIG but **not** for SDTMIG — so
narrowing can mean a real problem stops being reported. Leave `standard`
unset if you would rather see everything.

**Only the fully-vetted rules, no drafts**

```r
subset(list_rules(), source == "published")
```

**Which rule version am I running?**

```r
rules_version()
#> [1] "b540283d85e88fb8ee5f08ead5f03fac73eb1b8b"
```

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

## What's covered

756 rules for **SDTM**, **SEND** and **TIG**, bundled inside the package as
data. Nothing is downloaded — no internet, no API key, no account, and your
trial data never leaves your machine.

**ADaM isn't in yet, and that's not my choice.** CDISC publishes 197 ADaM rules,
but not one of them ships with reference results — there's no published expected
output to check an implementation against. Including them would mean asking you
to trust checks nobody has verified. The day CDISC publishes that reference data,
they go in.

Not every rule carries the same weight; `list_rules()` has a `source` column
telling you whether a rule is published, deprecated or draft. See
[NOTICE.md](NOTICE.md).

## How accurate is it?

CDISC publishes, for each rule, data that *should* trigger it, data that
*shouldn't*, and the exact records their own engine flags. coreval replays all of
it and compares record by record.

**On published rules that ship reference data: 488 of 511, about 95%.**

<details>
<summary>Why there's more than one number</summary>

| What's counted | Agreement |
|---|---|
| Published rules with reference data — **the meaningful one** | **488 / 511 (95%)** |
| All published rules, including those with nothing to compare against | 488 / 543 (90%) |
| Every bundled rule, including deprecated and draft | 597 / 722 (83%) |

**81 rules ship no reference data at all.** CDISC publishes the rule but no
examples, so there's nothing to compare against — they can't pass or fail.
Counting them as failures understates things; hiding them overstates. So both
are here.

**Deprecated and draft rules are a weaker pool.** Their examples predate CDISC's
current conventions — some number records from the spreadsheet header row, so
they expect a "record 5" in a four-row file. That's the example data being old,
not coreval being wrong.

**Most of the remaining disagreements are problems in the reference data**,
usually a file whose own stated values contradict its own rows — a sign the data
was edited after the expected results were generated.

</details>

**Please don't read 95% as a quality score.** CDISC's examples are mostly
simple, single-file datasets, so they don't exercise much of what real
submissions do. I once found a bug that silently switched off a third of the
rules on split-domain studies — it moved that number by exactly zero. It's a
floor, not a ceiling. Which is the same reason the advice stays: run your
qualified tool before you submit.

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
still writing the code, and that tells you honestly when it couldn't check
something.

## Status

Under active development, and the API may still change. Already useful for
finding real problems in real data. See [NEWS.md](NEWS.md).

## Contributing

Issues and pull requests welcome — especially a dataset that produces a wrong or
missing finding. That's the most useful bug report there is. Please read the
[Code of Conduct](CODE_OF_CONDUCT.md) first.

## License

Package code is MIT ([LICENSE.md](LICENSE.md)). Bundled rule definitions come
from [cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
and remain under CDISC's terms — see [NOTICE.md](NOTICE.md).

Not affiliated with, endorsed by, or certified by CDISC.

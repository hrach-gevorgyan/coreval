# coreval

<!-- badges: start -->
[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Check your SDTM data against CDISC rules without leaving R.**

You have a data frame. Check it:

```r
library(coreval)

check_dataset(ae)$findings
#>       rule_id Dataset Record Variable      Value
#> 1 CORE-000547      AE      2  AESTDTC 2024-02-30
```

There it is — 30 February, in row 2, in `AESTDTC`. No export, no upload, no
waiting for a report.

---

## Why you might want this

You know the loop:

> write code → export XPT → upload to Pinnacle 21 → wait → read report →
> find the line of code that caused it → fix → **do it all again**

You go round it many times, because fixing one thing uncovers the next. And
almost none of that time is spent *fixing* anything. It's spent **finding out
what's broken**.

coreval does the finding part on your machine, in seconds. You still run
Pinnacle 21 — you just arrive with far less for it to complain about.

**This does not replace Pinnacle 21 and isn't trying to.** Your qualified
validation run stays exactly where it is.

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

---

## Reading the results

You get two tables. **Both matter.**

### `result$findings` — what's wrong

```r
head(result$findings)
#>       rule_id Dataset Record Variable      Value
#> 1 CORE-000005      AE      3  AESTDTC  2013-02-30
#> 2 CORE-000005      AE      3  AEENDTC  2013-02-11
#> 3 CORE-000112      DM      7    AGEU
```

One row per problem, pointing at the exact spot:

| Column | What it tells you |
|---|---|
| `rule_id` | Which CDISC rule fired |
| `Dataset` | Which dataset (or `STUDY` for whole-study checks) |
| `Record` | Row number, counting from 1 |
| `Variable` | The variable being complained about |
| `Value` | What was actually in there |

`Not in dataset` in the `Value` column means the rule wanted a variable you
don't have — which is usually the point.

### `result$skipped` — what couldn't be checked

```r
head(result$skipped)
#>       rule_id domain                                    reason
#> 1 CORE-000916     AE  Match Datasets: unsupported join type...
```

**This is the one people skip, and it's the one that bites.** An empty findings
table means one of two things: your data is clean, or half the rules never ran.
Those look identical if you only read `findings`. coreval always shows you both.

### Saving it

```r
write_findings(result, "issues.xlsx")   # one workbook, two sheets
write_findings(result, "issues.csv")    # issues.csv + issues_skipped.csv
```

Both tables get written, every time, for the reason above. Hand the spreadsheet
to a colleague or attach it to your data-review documentation.

---

## Recipes

**Which rules even apply to AE?**

```r
rules_for_domain("AE")
```

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

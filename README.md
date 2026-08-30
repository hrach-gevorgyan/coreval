# coreval

<!-- badges: start -->
[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

### Catch CDISC conformance problems in seconds, without leaving R.

```r
study  <- read_study("study/sdtm")   # a folder of .xpt / .sas7bdat / .csv
result <- check_study(study)         # every applicable rule, every dataset
result$findings                      # a tidy data frame of what's wrong
```

---

## The problem this solves

If you prepare clinical trial data for submission, your day probably looks
something like this:

```
   write SAS/R code  ──▶  export XPT  ──▶  open Pinnacle 21  ──▶  upload
          ▲                                                          │
          │                                                          ▼
   fix the source  ◀──  copy issues to Excel  ◀──  read the report ──┘
```

Every trip round that loop costs you real time — exporting, uploading, waiting,
reading, mapping each finding back to the line of code that caused it. And you
go round it many times, because fixing one issue reveals the next.

**Most of that time isn't spent fixing data. It's spent finding out what's
broken.**

coreval collapses the discovery half of the loop into one function call that
runs where your code already lives:

```
   write SAS/R code  ──▶  check_study()  ──▶  fix  ──▶  (repeat, in seconds)
                                │
                                ▼
              only when it's clean, go to Pinnacle 21
```

### Roughly what that's worth

Plug in your own numbers — this is arithmetic, not a benchmark:

| | Your loop today | With a pre-check first |
|---|---|---|
| Time per round trip | ~20 min (export, upload, wait, read, transcribe) | seconds |
| Round trips per dataset while cleaning | ~5 | 1 formal run at the end |
| Datasets in a study | ~20 | 20 |

That's roughly **30 hours of round-trip overhead per study**, most of it
waiting and re-typing rather than thinking. If you run several studies a year,
the annual figure gets uncomfortable — and it's the most interruptible,
least interesting time in the whole process.

You won't remove that overhead entirely, and you shouldn't want to. But you can
stop paying it for the first eighty percent of issues, which are the obvious
ones: a date that runs backwards, a missing required variable, a code that isn't
in the codelist.

> **This does not replace Pinnacle 21, and it isn't trying to.** Your formal,
> qualified validation run stays exactly where it is. coreval is the quick check
> you run *before* it, so the formal run has less to find and you go round the
> expensive loop fewer times.

---

## What it is, and what it isn't

**coreval is an independent, personal open-source project.** It is not a CDISC
product, not affiliated with CDISC, not endorsed by CDISC, and not a
CORE-certified engine. I built it to stop wasting my own time, and I'm sharing
it in case it saves yours.

It is:

- A **fast, unqualified pre-check** you run while you're still writing the code.
- **Entirely local.** No internet, no API key, no account, no uploading trial
  data anywhere. The rules are bundled inside the package.
- **Honest about its limits.** A rule it can't evaluate is reported as *skipped,
  with a reason* — never quietly counted as a pass.

It is **not**:

- A qualified or validated system, and not a substitute for one.
- A regulatory guarantee. A clean run here does not mean a submission will be
  accepted, and a finding here does not mean it will be rejected.
- A replacement for your organisation's own validation procedures.

---

## Installation

```r
# install.packages("pak")
pak::pak("hrach-gevorgyan/coreval")
```

Requires R 4.1+. Only `data.table` and `haven` are needed to run it. Two
optional extras:

```r
install.packages("xml2")     # to read Define-XML
install.packages("writexl")  # to export findings to .xlsx
```

---

## Getting started, A to Z

### 1. Point it at your data

`read_study()` takes a **folder**, not a single file, and reads every dataset in
it. Transport files, SAS files and CSV all work, and it works out which it's
looking at.

```r
library(coreval)

study <- read_study("path/to/study/sdtm")

names(study$datasets)
#> [1] "AE" "CM" "DM" "EX" "LB" "VS"
```

This matters: rules routinely compare **across** datasets — an adverse event
date against the subject's reference dates in DM, a visit against the trial
design. Reading the whole folder at once is what makes those checks possible.

If a Define-XML file is in the folder, it's picked up automatically and used
for the rules that compare your data against what Define declares.

### 2. Run the checks

```r
result <- check_study(study)
```

One call. Every rule that applies to each dataset, plus the cross-dataset and
whole-study rules. On a normal study this takes seconds.

### 3. Read the findings

```r
head(result$findings)
#>       rule_id Dataset Record Variable      Value
#> 1 CORE-000005      AE      3  AESTDTC  2013-02-30
#> 2 CORE-000005      AE      3  AEENDTC  2013-02-11
#> 3 CORE-000112      DM      7    AGEU
```

One row per **(dataset, record, variable)**, so you can go straight to the
offending row in the source. Columns:

| Column | Meaning |
|---|---|
| `rule_id` | Which CDISC rule fired |
| `Dataset` | Which dataset — or `STUDY` for whole-study checks |
| `Record` | Row number in that dataset, counting from 1 |
| `Variable` | The variable the rule reports on |
| `Value` | What was actually there |

### 4. Always check what was *skipped*

```r
head(result$skipped)
#>       rule_id domain                                    reason
#> 1 CORE-000916     AE  Match Datasets: unsupported join type...
```

**This is the part people forget.** A short findings table can mean your data is
clean, or it can mean a lot of rules never ran. Those look identical if you only
read `findings`. coreval never hides this from you.

### 5. Export it

```r
write_findings(result, "issues.xlsx")   # one workbook, two sheets
write_findings(result, "issues.csv")    # issues.csv + issues_skipped.csv
```

Both tables are always written, for the reason above. Hand the spreadsheet to a
colleague, attach it to your data-review documentation, or track fixes in it.

---

## Common tasks

**Which rules will even apply to my AE dataset?**

```r
rules_for_domain("AE")
```

**Just the fully-vetted rules, ignoring drafts**

```r
rules <- list_rules()
subset(rules, source == "published")
```

**Which CDISC rule version am I running?**

```r
rules_version()
#> [1] "b540283d85e88fb8ee5f08ead5f03fac73eb1b8b"
```

The exact upstream commit the bundled rules came from — worth recording
alongside your results.

**Findings for one dataset only**

```r
subset(result$findings, Dataset == "AE")
```

**Which rules fired most often?**

```r
sort(table(result$findings$rule_id), decreasing = TRUE)
```

**How many distinct records are affected?**

```r
nrow(unique(result$findings[, c("Dataset", "Record")]))
```

---

## What's covered

Rules for **SDTM**, **SEND** and **TIG**, across their published versions —
756 rules bundled as data.

**ADaM is not included yet, and that's not a design choice.** CDISC publishes
197 ADaM rules, but every one of them currently ships without reference results
— there's no published expected output to verify an implementation against.
Shipping them would mean asking you to trust checks nobody has verified, which
is exactly what this package refuses to do elsewhere. **The moment CDISC
publishes reference data for ADaM, those rules go in.**

Not every bundled rule carries equal weight — `list_rules()` has a `source`
column saying whether a rule is published, deprecated or draft. See
[NOTICE.md](NOTICE.md).

---

## How well does it work?

coreval is tested by replaying CDISC's own reference test cases. For each rule
CDISC publishes datasets that *should* trigger it, datasets that *shouldn't*,
and the exact records their engine flags. Every bundled rule is run against all
of it and compared record by record.

On published rules that ship reference data to compare against, coreval agrees
with CDISC's own results on **479 of 502 — about 95%**.

<details>
<summary>The other numbers, and why there's more than one</summary>

| What's counted | Agreement |
|---|---|
| Published rules with reference data — **the meaningful number** | **479 / 502 (95%)** |
| All published rules, including those with nothing to compare against | 479 / 543 (88%) |
| Every bundled rule, including deprecated and draft | 588 / 722 (81%) |

**81 rules ship no reference data at all.** CDISC publishes the rule but no
examples, so there's nothing to compare against — they can't pass *or* fail.
Counting them as failures understates by ~10 points; hiding them overstates.
Both are shown.

**Deprecated and draft rules are a weaker pool.** Their examples predate CDISC's
current conventions — several number records from the spreadsheet header row, so
one expects a "record 5" in a four-row file. That's a problem with the example
data, not with coreval.

**Most remaining disagreements are problems in the reference data.** The usual
tell is that a file's own stated values contradict its own data, meaning the data
was edited after the expected results were generated.

</details>

**Please don't read that percentage as a quality score.** CDISC's examples are
almost all simple single-file datasets, so they don't exercise plenty of things
real submissions do. A real bug that silently switched off a third of the rules
on split-domain studies moved that number by exactly zero. It's a floor, not a
ceiling — which is also why the honest advice remains: run your qualified tool
before you submit.

---

## Status

Under active development; the API may still change. Useful today for finding
real problems in real data. See [NEWS.md](NEWS.md).

## Contributing

Issues and pull requests welcome — especially a dataset that produces a wrong or
missing finding, which is the most useful bug report there is. Please read the
[Code of Conduct](CODE_OF_CONDUCT.md) first.

## License

Package code is MIT ([LICENSE.md](LICENSE.md)). Bundled rule definitions come
from [cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
and remain under CDISC's terms — see [NOTICE.md](NOTICE.md).

Not affiliated with, endorsed by, or certified by CDISC.

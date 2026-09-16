# Getting started with coreval

If you build SDTM datasets, you know the loop: write code, export,
upload to a validation tool, wait, read the report, work out which line
of code caused each finding, fix, repeat.

Hardly any of that time is spent *fixing* things. It goes on **finding
out what’s broken**.

coreval does the finding part on your machine, in seconds. You still run
your qualified tool before you submit. You just arrive with a lot less
for it to find.

> coreval is a personal open-source project. It’s not a CDISC product,
> isn’t affiliated with or endorsed by CDISC, and isn’t qualified or
> validated software. Treat every result as a hint, not a verdict. Your
> qualified tool and your own review are still what decide whether data
> is good to go.

``` r

library(coreval)
```

## Start with one dataset

This is the one you’ll use most while writing code. You have a data
frame; check it.

Note row 2: `2024-02-30`. February never has 30 days.

``` r

ae <- data.frame(
  STUDYID = "DEMO", DOMAIN = "AE", USUBJID = c("S1", "S1", "S2"),
  AESEQ = c(1, 2, 1), AETERM = c("Headache", "Nausea", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30", "2024-01-12"),
  AEENDTC = c("2024-01-12", "2024-02-01", "")
)

result <- check_dataset(ae)
result
#> 
#> ── coreval — AE ────────────────────────────────────────────────────────────────
#> 
#> 5 problems across 3 records  (160 checks ran)
#> 
#>   wrong value         3   the data breaks the rule - start here
#>   missing required    1   the standard requires it
#>   missing optional    1   often legitimate: not collected, screen failure, ...
#> 
#> [wrong value]
#> Variable value is not in correct ISO 8601 date or datetime format
#>   2 records · AESTDTC, AEENDTC
#>     row 2     AESTDTC = "2024-02-30", AEENDTC = "2024-02-01"
#>     row 3     AESTDTC = "2024-01-12", AEENDTC = (empty)
#>     CORE-000547  · also SEND66, SEND67, SEND68, ...
#> 
#> [wrong value]
#> The Study Day of Start of Observation (--STDY) is not present in the dataset
#>   when Start Date/Time of Observation (--STDTC) is present.
#>   1 record · AESTDTC
#>     AESTDTC = "2024-01-10"
#>     CORE-000328  · also FB3202
#> 
#> [wrong value]
#> Study Day of End of Observation (--ENDY) variable is missing when End
#>   Date/Time of Observation (--ENDTC) is present.
#>   1 record · AEENDTC
#>     AEENDTC = "2024-01-12"
#>     CORE-000776  · also FB3203
#> 
#> [missing required]
#> At least one required variable is missing from dataset
#>   1 record
#>     missing required variables: AEDECOD
#>     CORE-000355  · also CG0014, SEND12, TIG0299, ...
#> 
#> [missing optional]
#> At least one expected variable is missing from dataset
#>   1 record
#>     missing expected variables: AELLT, AELLTCD, AEPTCD, AEHLT, AEHLTCD, AEHLGT, AEHLGTCD, AEBODSYS, ...
#>     CORE-000334  · also CG0016, TIG0301, SEND13, ...
#> 
#> ────────────────────────────────────────────────────────────────────────────────
#> 51 checks could not run.
#>   25 need other datasets (DM, POOLDEF, SUPPAE, SV, TA, TO, ...)
#>      → run check_study() on the whole folder to cover these
#>   16 ask what the whole study contains
#>   6 need a define.xml
#>   4 for other reasons, see result$skipped
#> 
#> No standard declared, so rules from every standard ran.
#>   Narrow with  standard = "SDTMIG"  (or "SENDIG", "TIG", ...)
#> 
#> Fix what you can, then run this again.
#> To track the rest:  write_findings(result, "issues.xlsx")
```

Each problem is described in words, with the rows and values that caused
it, and the rule number at the end in case you want to look it up.

The tag on each problem is worth understanding. CDISC Open Rules carry
no severity field - Pinnacle 21’s Notes/Minor/Major/Critical is P21’s
own layer, not CDISC’s - so coreval does not report one and will not
invent one. What it does instead is separate the findings that are
definitely wrong from the ones that may be fine:

- `wrong value` - the data contains something that breaks the rule, like
  a month of 13. Nothing about your study explains it away. Start here.
- `missing required` - something the standard marks Required is absent.
- `missing optional` - something Expected is absent, or a value is
  blank. Often legitimate: a screen-failure subject with no reference
  dates, a variable your raw data does not carry yet.

Problems are ordered by that first and by how many records they touch
second, and within a problem the record holding a real offending value
is shown before one that is merely empty. It is also a `triage` column
on every finding, so you can sort a spreadsheet by it.

The rows themselves, ready to filter or count, are in `result$findings`,
with the same description in an `issue` column:

``` r

result$findings[result$findings$Value == "2024-02-30", ]
#>    Dataset Record Variable      Value
#>     <char>  <int>   <char>     <char>
#> 1:      AE      2  AESTDTC 2024-02-30
#>                                                                issue
#>                                                               <char>
#> 1: Variable value is not in correct ISO 8601 date or datetime format
#>         triage     rule_id
#>         <char>      <char>
#> 1: wrong value CORE-000547
```

You can pass a file instead of a data frame: `.xpt`, `.sas7bdat` or
`.csv`:

``` r

result <- check_dataset("ae.xpt")
```

coreval works out the domain from your `DOMAIN` column, and falls back
to the file name only when the data has no `DOMAIN` column at all. That
order matters for a split dataset: `ae1.xpt` is checked as `AE` because
its `DOMAIN` column says `AE`. On a file with no `DOMAIN` column the
name `ae1` is taken at face value. If it guesses wrong, just say so:
`check_dataset(ae, domain = "AE")`.

### What it couldn’t check, and why that matters

Lots of CDISC rules compare **one dataset against another**: an adverse
event date against the subject’s reference dates in `DM`, a visit
against the trial design. Give coreval a single dataset and those
questions simply can’t be answered.

coreval won’t guess. It skips them and tells you what it wanted:

``` r

cross <- result$skipped[grepl("was not supplied", result$skipped$reason), ]
nrow(cross)
#> [1] 25
head(unique(cross$reason), 3)
#> [1] "needs DM, which was not supplied - check the whole study folder to run this rule"
#> [2] "needs TV, which was not supplied - check the whole study folder to run this rule"
#> [3] "needs SV, which was not supplied - check the whole study folder to run this rule"
```

If it ran those anyway, it would be comparing your data against columns
that aren’t there, and reporting problems that don’t exist. Saying
nothing is better than making something up.

Nine rules ask a different kind of question: is this value one of the
terms CDISC’s controlled terminology allows for this variable? `SEX` may
be `F`, `M`, `U` or `INTERSEX` and nothing else. Those need to know
which version of the terminology your study follows, because it changes
between releases - `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`.
So tell it:

``` r

check_study(dir, ct_package = "sdtmct-2026-03-27")
list_ct_packages("sdtm")   # every published version, pick the one you declare
```

Without it those rules are reported as skipped, by name, saying exactly
that - coreval will not pick a version for you, because judging your
data against terminology it never declared would invent violations and
hide real ones.

Most rules do still run. Across AE, DM, LB and VS, 76–84% of the
applicable ones work on a single dataset. But the ones that can’t are
the cross-dataset checks, and those are often the ones you care about.

**So a short findings list here doesn’t mean your data is clean.** It’s
a quick first pass, not a verdict.

## Then check the whole study

Once the datasets exist as files, point coreval at the folder. Here’s a
small one, built on the fly so this vignette runs without any data of
your own:

``` r

dir <- tempfile("coreval_demo_")
dir.create(dir)

dm <- data.frame(
  STUDYID = "DEMO", DOMAIN = "DM", USUBJID = c("S1", "S2", "S3"),
  RFSTDTC = c("2024-01-05", "2024-01-06", ""),
  AGE = c(34, 61, 47), AGEU = c("YEARS", "YEARS", ""),
  SEX = c("M", "F", "F")
)

haven::write_xpt(dm, file.path(dir, "dm.xpt"))
haven::write_xpt(ae, file.path(dir, "ae.xpt"))
```

Point it at the **folder**, not a file:

``` r

study_result <- check_study(dir)
```

coreval reads everything in there, and reading it all at once is the
point. now the cross-dataset rules have both halves to work with. If
there’s a Define-XML in the folder it finds it and uses it (that needs
the `xml2` package).

If you want to look at what was parsed, or check the same large study
more than once without re-reading it, do the read yourself and pass the
object instead:

``` r

study <- read_study(dir)
names(study$datasets)
#> [1] "AE" "DM"
```

## Reading the results

You get two tables back, and you want to look at both.

### What’s wrong

``` r

head(study_result$findings)
#>    Dataset Record            Variable
#>     <char>  <int>              <char>
#> 1:      AE     NA              AESTDY
#> 2:      AE     NA             AESTDTC
#> 3:      AE     NA  $dataset_variables
#> 4:      AE     NA $expected_variables
#> 5:      AE     NA  $dataset_variables
#> 6:      AE     NA $required_variables
#>                                                                                                                                                                    Value
#>                                                                                                                                                                   <char>
#> 1:                                                                                                                                                        Not in dataset
#> 2:                                                                                                                                                            2024-01-10
#> 3:                                                                                             ['STUDYID', 'DOMAIN', 'USUBJID', 'AESEQ', 'AETERM', 'AESTDTC', 'AEENDTC']
#> 4: ['AELLT', 'AELLTCD', 'AEPTCD', 'AEHLT', 'AEHLTCD', 'AEHLGT', 'AEHLGTCD', 'AEBODSYS', 'AEBDSYCD', 'AESOC', 'AESOCCD', 'AESER', 'AEACN', 'AEREL', 'AESTDTC', 'AEENDTC']
#> 5:                                                                                             ['STUDYID', 'DOMAIN', 'USUBJID', 'AESEQ', 'AETERM', 'AESTDTC', 'AEENDTC']
#> 6:                                                                                                        ['STUDYID', 'DOMAIN', 'USUBJID', 'AESEQ', 'AETERM', 'AEDECOD']
#>                                                                                                                                     issue
#>                                                                                                                                    <char>
#> 1: The Study Day of Start of Observation (--STDY) is not present in the dataset when Start Date/Time of Observation (--STDTC) is present.
#> 2: The Study Day of Start of Observation (--STDY) is not present in the dataset when Start Date/Time of Observation (--STDTC) is present.
#> 3:                                                                                 At least one expected variable is missing from dataset
#> 4:                                                                                 At least one expected variable is missing from dataset
#> 5:                                                                                 At least one required variable is missing from dataset
#> 6:                                                                                 At least one required variable is missing from dataset
#>              triage     rule_id
#>              <char>      <char>
#> 1:      wrong value CORE-000328
#> 2:      wrong value CORE-000328
#> 3: missing optional CORE-000334
#> 4: missing optional CORE-000334
#> 5: missing required CORE-000355
#> 6: missing required CORE-000355
```

One row per affected record, pointing straight at it:

| Column     | What it tells you                                       |
|------------|---------------------------------------------------------|
| `Dataset`  | which dataset, or `STUDY` for whole-study checks        |
| `Record`   | row number, counting from 1                             |
| `Variable` | the variable being complained about                     |
| `Value`    | what was actually in there                              |
| `issue`    | what’s wrong, in words                                  |
| `triage`   | `wrong value`, `missing required` or `missing optional` |
| `rule_id`  | the CDISC rule, if you want to look it up               |

One thing that surprises people: `Not in dataset` under `Value` means
the rule wanted a variable you don’t have, which is usually the finding.

It’s a plain data frame, so slice it however you like:

``` r

f <- study_result$findings
head(f[f$Dataset == "DM", ])
#>    Dataset Record           Variable
#>     <char>  <int>             <char>
#> 1:      DM      1             SUBJID
#> 2:      DM      2             SUBJID
#> 3:      DM      3             SUBJID
#> 4:      DM      3                AGE
#> 5:      DM      3               AGEU
#> 6:      DM     NA $dataset_variables
#>                                                                Value
#>                                                               <char>
#> 1:                                                    Not in dataset
#> 2:                                                    Not in dataset
#> 3:                                                    Not in dataset
#> 4:                                                                47
#> 5:                                                                  
#> 6: ['STUDYID', 'DOMAIN', 'USUBJID', 'RFSTDTC', 'AGE', 'AGEU', 'SEX']
#>                                                     issue           triage
#>                                                    <char>           <char>
#> 1:                      SUBJID is not unique within study missing optional
#> 2:                      SUBJID is not unique within study missing optional
#> 3:                      SUBJID is not unique within study missing optional
#> 4:                  AGEU is missing when AGE is provided.      wrong value
#> 5:                  AGEU is missing when AGE is provided.      wrong value
#> 6: At least one expected variable is missing from dataset missing optional
#>        rule_id
#>         <char>
#> 1: CORE-000186
#> 2: CORE-000186
#> 3: CORE-000186
#> 4: CORE-000189
#> 5: CORE-000189
#> 6: CORE-000334
sort(table(f$rule_id), decreasing = TRUE)[1:3]
#> 
#> CORE-000547 CORE-000334 CORE-000355 
#>          21           4           4
```

Slicing the data frame gives you rows.
[`filter_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/filter_findings.md)
gives you back a *result*, the same object narrowed. That is the
difference that matters: because a result is what
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
and [`summary()`](https://rdrr.io/r/base/summary.html) take:

``` r

worst <- filter_findings(study_result, triage = "wrong value")
nrow(worst$findings)
#> [1] 25
summary(worst)
#> 6 problems across 4 records  (386 checks ran, 45 could not)
#>   (filtered - a subset of the full result)
#>   wrong value       6
```

The two numbers there are counting different things, and the difference
is worth knowing: `findings` has a row per affected *record*, while
[`summary()`](https://rdrr.io/r/base/summary.html) counts distinct
*problems*: one rule going wrong in one dataset, however many records it
touched. A single missing variable in a 500-row dataset is one problem
and 500 rows.

`triage` has three levels, worst first: `"wrong value"` is a value that
contradicts the data around it, `"missing required"` a variable the
standard says must be there, `"missing optional"` one it merely expects.
You can also narrow by `dataset`, `rule` or `variable`, and combine
them.

### What couldn’t be checked

``` r

head(study_result$skipped)
#>        rule_id domain
#>         <char> <char>
#> 1: CORE-000019     AE
#> 2: CORE-000398     AE
#> 3: CORE-000494     AE
#> 4: CORE-000507     AE
#> 5: CORE-000594     AE
#> 6: CORE-000929     AE
#>                                                                                                                                                                                                                                               reason
#>                                                                                                                                                                                                                                               <char>
#> 1:                                                                                                        evaluation failed: compares variable labels, and this dataset has none at all (a data frame built in R has no labels until they are added)
#> 2:                                                                                                        evaluation failed: compares variable labels, and this dataset has none at all (a data frame built in R has no labels until they are added)
#> 3:                                                                                                            evaluation failed: rule type 'Define Item Metadata Check against Library Metadata' needs define.xml: no define.xml found in this study
#> 4:                                                                                                                     evaluation failed: rule type 'Variable Metadata Check against Define XML' needs define.xml: no define.xml found in this study
#> 5:                                                                                                        evaluation failed: compares variable labels, and this dataset has none at all (a data frame built in R has no labels until they are added)
#> 6: evaluation failed: needs controlled terminology, and this study does not say which version it follows: TS has no TSVCDVER naming a CDISC package that is bundled. Pass ct_package (e.g. ct_package = "sdtmct-2026-03-27"; see list_ct_packages())
```

**This is the table people skip, and it’s the one that bites.** An empty
findings table means one of two things: your data is clean, or a lot of
rules never ran. Those look identical if you only read the findings.
coreval always shows you both, with a reason for every rule it couldn’t
run.

### Saving it, and tracking what you didn’t fix

``` r

write_findings(study_result, "issues.xlsx")  # one workbook, a sheet per table
write_findings(study_result, "issues.csv")   # issues.csv + _skipped + _about
```

Both tables get written every time, for the reason just above. Excel
output needs the `writexl` package.

The saved file has three empty columns, `Status`, `Owner` and `Notes`,
for you to fill in once it is open. Not every finding is something you
will fix: some are expected, some belong to someone else, some are
waiting on a data query. Those decisions are worth recording next to the
finding rather than in a separate document. Pass `tracking = FALSE` if
you would rather not have them.

## The rule set

One function answers every question about the rule set.

``` r

rules <- list_rules()
nrow(rules)
#> [1] 1054
table(rules$source)
#> 
#>           deprecated_dir fda_business_rules_draft                published 
#>                      163                       27                      823 
#>             sdtmig_draft             sendig_draft 
#>                       11                       30

attr(rules, "rules_version")
#> [1] "1fb7b81e40bdb6632375761c561fabd29676a477"
```

That last one is the exact CDISC commit the bundled rules came from.
Worth writing down next to your results, though
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
already records it in every file it saves.

Not every rule carries the same weight. `source` separates fully-vetted
published rules from deprecated and draft ones;
[`?list_rules`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md)
says what each means.

Note the count above includes the deprecated ones.
[`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md)
is the catalog of what is *bundled*; a check excludes superseded rules,
because running one alongside its replacement reports the same problem
twice. Listing is not running.

Ask it what applies to a domain, or what a rule the report named
actually checks:

``` r

nrow(list_rules(domain = "AE"))
#> [1] 243

rule <- list_rules(id = "CORE-000547")
rule$issue
#> [1] "Variable value is not in correct ISO 8601 date or datetime format"
```

Two more columns are worth knowing. `legacy_ids` are the names Pinnacle
21 and CDISC’s older Conformance Rules spreadsheets use for the same
rule, which is how you match a finding here to a line in a P21 report.
`guidance` is the sentence from the Implementation Guide the rule exists
to enforce: the reason behind it.

``` r

rule$legacy_ids
#> [1] "SEND66, SEND67, SEND68, TIG0267, TIG0268, TIG0269"
```

`print(result, guidance = TRUE)` shows that sentence under each problem
in the report. It’s off by default because it roughly doubles the
length.

## Narrowing to your standard

With no standard given, coreval runs the rules for every standard it
has, and the report says so. Tell it which one your data follows and it
runs only those, and only for your version of the Implementation Guide:

``` r

result <- check_dataset(dm, standard = "SDTMIG", version = "3.4")
```

That cuts the list a lot, and it can cut too far. CDISC’s coverage is
uneven: the general “dates must be valid ISO 8601” rule is published for
SEND and the Tobacco Implementation Guide but not for SDTM, so narrowing
to SDTMIG stops a month of 13 being reported. The report always says how
many rules it set aside. Leave `standard` unset if you’d rather see
everything.

## USDM study designs

A USDM study file is a single JSON document describing a study design
rather than a folder of datasets. Put it in a folder and check the
folder, the same way as any other study. It needs the `jsonlite` and
`QuickJSR` packages.

``` r

result <- check_study("path/to/usdm")
```

Problems are reported against the part of the design they’re about, such
as `STUDYDESIGN` or `ENCOUNTER`, and the row within it.

## The whole API

Seven functions, and three of them do the work:

|  |  |
|----|----|
| `check_dataset(x)` | one dataset: a data frame, or an `.xpt`/`.sas7bdat`/`.csv` |
| `check_study(path)` | a whole folder |
| `write_findings(result, path)` | save to Excel or CSV |
| [`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md) | the rule set, one rule, or the rules for a domain |
| `filter_findings(result, ...)` | narrow a result |
| `read_study(path)` | read a folder yourself, when you want to inspect it |
| [`list_ct_packages()`](https://hrach-gevorgyan.github.io/coreval/reference/list_ct_packages.md) | the Controlled Terminology releases you can pass as `ct_package` |

Plus [`print()`](https://rdrr.io/r/base/print.html) and
[`summary()`](https://rdrr.io/r/base/summary.html) on a result.
[`print()`](https://rdrr.io/r/base/print.html) is what you get by typing
the result’s name; [`summary()`](https://rdrr.io/r/base/summary.html)
you call yourself, and it returns a one-row table you can rbind across
datasets.

## Two last things

**Nothing leaves your machine.** No internet, no API key, no account.
The rules and the standards metadata are bundled inside the package.

**Think of the accuracy number as a floor.** For most rules CDISC
publishes an answer sheet: some example data, and the exact rows a
correct implementation should flag. Every rule here is run against those
examples and compared row by row, and more than nine in ten come back
with exactly the answer CDISC gives.

But those examples are small and tidy, and real submissions are neither,
so agreement is a lower bound on correctness rather than a score. The
README lists what coreval doesn’t do yet. The advice does not change:
run your qualified tool before you submit.

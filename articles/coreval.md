# Getting started with coreval

coreval checks SDTM, SEND and USDM data against CDISC’s conformance
rules, inside R, on your own machine. This page shows the few steps you
need and then answers the questions people ask most. For how it all
works underneath, see
[`vignette("technical", package = "coreval")`](https://hrach-gevorgyan.github.io/coreval/articles/technical.md).

> coreval is a personal open-source project. It is not a CDISC product
> and is not validated software. Treat its findings as a fast first
> check, and run your qualified tool before you submit.

## Four steps

### 1. Install and load

``` r

install.packages("coreval")
install.packages(c("xml2", "writexl"))  # optional: define.xml and Excel output
```

``` r

library(coreval)
```

### 2. Check a dataset while you write it

Give
[`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md)
the data frame you just built. Row 2 below has `2024-02-30`, a date that
does not exist.

``` r

ae <- data.frame(
  STUDYID = "DEMO", DOMAIN = "AE", USUBJID = c("S1", "S1", "S2"),
  AESEQ = c(1, 2, 1), AETERM = c("Headache", "Nausea", "Rash"),
  AESTDTC = c("2024-01-10", "2024-02-30", "2024-01-12"),
  AEENDTC = c("2024-01-12", "2024-02-01", "")
)

result <- check_dataset(ae, standard = "SDTMIG", version = "3.4")
result
#> 
#> ── coreval — AE ────────────────────────────────────────────────────────────────
#> 
#> 8 problems across 3 records  (152 checks ran)
#> 
#>   wrong value         2   the data breaks the rule - start here
#>   missing required    4   the standard requires it
#>   missing optional    2   often legitimate: not collected, screen failure, ...
#> 
#> [wrong value]
#> --STDTC falls after --ENDTC.
#>   1 record · AESTDTC, AEENDTC
#>     row 2  S1 seq 2  AESTDTC = "2024-02-30", AEENDTC = "2024-02-01"
#>     CORE-000718  · also FB3209
#> 
#> [wrong value]
#> Value must be a valid ISO 8601 datetime or interval.
#>   1 record · AESTDTC
#>     row 2  S1 seq 2  AESTDTC = "2024-02-30"
#>     CORE-002121  · also CG0011
#> 
#> [missing required]
#> Missing treatment-emergent flag (AETRTEM) for the Adverse Event.
#>   3 records · AETERM, AESTDTC
#>     row 1  S1 seq 1  AETERM = "Headache", AESTDTC = "2024-01-10"
#>     row 2  S1 seq 2  AETERM = "Nausea", AESTDTC = "2024-02-30"
#>     row 3  S2 seq 1  AETERM = "Rash", AESTDTC = "2024-01-12"
#>     CORE-002034  · also FB0101
#> 
#> [missing required]
#> Study Day of Start of Observation (--STDY) variable is missing when Start
#>   Date/Time of Observation (--STDTC) is present.
#>   the dataset · AESTDTC
#>     AESTDTC = "2024-01-10"
#>     CORE-000328  · also FB3202
#> 
#> [missing required]
#> Required variable is missing from the dataset.
#>   the dataset
#>     missing required variables: AEDECOD
#>     CORE-000355  · also CG0014
#> 
#> [missing required]
#> Study Day of End of Observation (--ENDY) variable is missing when End
#>   Date/Time of Observation (--ENDTC) is present.
#>   the dataset · AEENDTC
#>     AEENDTC = "2024-01-12"
#>     CORE-000776  · also FB3203
#> 
#> [missing optional]
#> EPOCH is missing for clinical subject-level observation.
#>   3 records · EPOCH
#>     not in the dataset: EPOCH
#>     CORE-000701  · also FB2201
#> 
#> [missing optional]
#> Expected variable is missing from the dataset.
#>   the dataset
#>     missing expected variables: AELLT, AELLTCD, AEPTCD, AEHLT, AEHLTCD, AEHLGT, AEHLGTCD, AEBODSYS, ...
#>     CORE-000334  · also CG0016
#> 
#> ────────────────────────────────────────────────────────────────────────────────
#> 67 checks could not run.
#>   28 need other datasets (DM, DS, RELREC, SV, TA, TS, ...)
#>      → run check_study() on the whole folder to cover these
#>   22 ask what the whole study contains
#>   11 need a define.xml
#>      → put it in the study folder (reading it needs the xml2 package)
#>   2 need to know the controlled terminology version
#>      → pass ct_package ("sdtmct-..." or "sendct-..."; see list_ct_packages()), or for a study fill TSVCDREF and TSVCDVER in TS
#>   2 compare variable labels, and the data has none
#>      → give the variables labels: a data frame made in R has none until they are added
#>   2 for other reasons, see result$skipped
#> 
#> Scoped to SDTMIG: 69 rules written for other standards, or other versions of this one, were not run.
#> 
#> Fix what you can, then run this again.
#> To track the rest:  write_findings(result, "issues.xlsx")
```

A file works too: `check_dataset("ae.xpt", standard = "SDTMIG")`, or a
`.sas7bdat` or `.csv`.

### 3. Check the whole study

Once the datasets exist as files, point
[`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md)
at the folder. This is the only way to run the rules that compare one
dataset with another, such as an adverse event date against the
subject’s dates in DM.

``` r

result <- check_study("path/to/sdtm", standard = "SDTMIG", version = "3.4")
```

If the folder holds a `define.xml`, it is used automatically (with
`xml2` installed).

### 4. Save it for the team

``` r

write_findings(result, "issues.xlsx")
```

The workbook has four sheets: the problems, one row each; the affected
records, by subject and sequence number; the checks that could not run,
with what to do about them; and every rule with what happened to it.
`Status` and `Notes` columns are there for you to fill in.

## Reading the report

Every problem carries one of three tags:

| Tag | Means | What to do |
|----|----|----|
| `wrong value` | the data holds a value that breaks the rule | fix it, start here |
| `missing required` | something the standard requires is absent or blank | fix it |
| `missing optional` | something expected is absent | often fine: check whether it applies to your study |

The detail is in two tables:

``` r

# what is wrong: dataset, row, subject, variable, value
f <- result$findings
head(f[!is.na(f$Record), c("Dataset", "Record", "USUBJID", "SEQ", "Variable", "Value")])
#>    Dataset Record USUBJID   SEQ Variable          Value
#>     <char>  <int>  <char> <num>   <char>         <char>
#> 1:      AE      2      S1     2  AESTDTC     2024-02-30
#> 2:      AE      2      S1     2  AEENDTC     2024-02-01
#> 3:      AE      1      S1     1    EPOCH Not in dataset
#> 4:      AE      2      S1     2    EPOCH Not in dataset
#> 5:      AE      3      S2     1    EPOCH Not in dataset
#> 6:      AE      1      S1     1   AETERM       Headache

# what could not be checked, and why
head(unique(result$skipped$reason), 3)
#> [1] "needs TV, which is not in this study"                                                        
#> [2] "needs SV, which is not in this study"                                                        
#> [3] "evaluation failed: a date is not a real date (2024-02-30), and CORE 1.0 stops the rule on it"
```

`Record` is the row in the file. `USUBJID` and `SEQ` are the record’s
subject and `--SEQ`, which still find it after the data is sorted; they
are blank in a dataset without them, such as `TS`. Each finding also has
the `issue` in words, its `triage` and the `rule_id`. A blank `Record`
means the problem is about the dataset as a whole, such as a missing
variable. For a rule about the variables themselves, such as a wrong
type or label, `Record` is the variable’s position in the dataset, not a
row, and `Variable` and `Value` name the variable.

**Always look at `skipped`.** A short list of problems can mean clean
data, or it can mean many rules never ran. The skipped table tells you
which.

## Common tasks

### Show me only the real errors

``` r

errors <- filter_findings(result, triage = "wrong value")
errors
#> 
#> ── coreval ─────────────────────────────────────────────────────────────────────
#> 
#> (filtered - this is a subset of the full result)
#> 
#> 3 problems across 2 records in 2 datasets  (346 checks ran)
#> 
#>   wrong value         3   the data breaks the rule - start here
#> 
#>   AE           2 problems    1 record
#>   DM           1 problem     1 record
#> 
#> ── AE ──────────────────────────────────────────────────────────────────────────
#> 
#> [wrong value]
#> --STDTC falls after --ENDTC.
#>   1 record · AESTDTC, AEENDTC
#>     row 2  S1 seq 2  AESTDTC = "2024-02-30", AEENDTC = "2024-02-01"
#>     CORE-000718  · also FB3209
#> 
#> [wrong value]
#> Value must be a valid ISO 8601 datetime or interval.
#>   1 record · AESTDTC
#>     row 2  S1 seq 2  AESTDTC = "2024-02-30"
#>     CORE-002121  · also CG0011
#> 
#> ── DM ──────────────────────────────────────────────────────────────────────────
#> 
#> [wrong value]
#> AGEU must be populated when AGE is populated.
#>   1 record · AGE, AGEU
#>     row 3  S3  AGE = "47", AGEU = (empty)
#>     CORE-000189  · also CG0665
#> 
#> ────────────────────────────────────────────────────────────────────────────────
#> 81 checks could not run.
#>   21 need datasets this study does not have (CE, DS, EX, RELREC, SS, SUPPDM, ...)
#>   52 need a define.xml
#>      → put it in the study folder (reading it needs the xml2 package)
#>   4 need to know the controlled terminology version
#>      → pass ct_package ("sdtmct-..." or "sendct-..."; see list_ct_packages()), or for a study fill TSVCDREF and TSVCDVER in TS
#>   2 need the study tagging file (stf.xml)
#>      → put it in the study folder
#>   1 need variables the data does not have
#>   1 for other reasons, see result$skipped
#> 
#> Scoped to SDTMIG: 122 rules written for other standards, or other versions of this one, were not run.
#> 
#> Fix what you can, then run this again.
#> To track the rest:  write_findings(result, "issues.xlsx")
```

You can also narrow by `dataset`, `rule` or `variable`, and save the
narrowed result with
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md).
The saved file notes that it is a subset.

### My study is SDTMIG 3.3, or SEND

`standard` is required, and only the rules for that standard and version
run:

``` r

check_study("path/to/sdtm", standard = "SDTMIG", version = "3.3")
check_study("path/to/send", standard = "SENDIG", version = "3.1")
```

Leave `version` out and the rules for every version of that standard
run.
[`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md)
shows which standards and versions there are.

### It says terminology checks were skipped

Rules about allowed values (is `SEX` one of the permitted terms?) need
to know which Controlled Terminology release your study uses. coreval
reads it from `TSVCDVER` in your TS dataset (on rows whose `TSVCDREF` is
`CDISC`), or from the define.xml. If neither says, tell it:

``` r

list_ct_packages("sdtm")   # every release you can choose from
check_study("path/to/sdtm", standard = "SDTMIG", ct_package = "sdtmct-2026-03-27")
```

### Many checks say “was not supplied”

You checked one dataset, and those rules compare it with another one.
Run
[`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md)
on the folder that holds both.

### Stop my program when a dataset has errors

Put a check at the end of the code that builds a dataset:

``` r

r <- check_dataset(ae, standard = "SDTMIG", version = "3.4")
bad <- filter_findings(r, triage = "wrong value")
if (nrow(bad$findings) > 0) {
  print(bad)
  stop("AE has values that break CDISC rules")
}
```

### Find out what a rule checks

The report ends each problem with a rule id. Look it up:

``` r

rule <- list_rules(id = "CORE-000718")
rule$issue        # what it checks
#> [1] "--STDTC falls after --ENDTC."
rule$legacy_ids   # the same rule's id in CDISC's Conformance Rules or FDA lists
#> [1] "FB3209"
```

`print(result, guidance = TRUE)` adds the Implementation Guide sentence
behind each rule to the report.

### See every problem, not just the first ten

``` r

print(result, n = Inf)   # every problem in the report
result$findings          # every finding, as a table
```

A rule that flags a very large number of records keeps the first 1,000
and records the real count in `result$truncated`. Pass
`max_records = Inf` to keep them all.

### Check one file of a split dataset

`check_dataset("lb1.xpt", standard = "SDTMIG")` reads the domain from
the `DOMAIN` column. If the file has none, say which domain it is with
`domain = "LB"`.

### Check a big study faster

- Set `version` as well as `standard`: fewer rules run.
- Read once, check several times:

``` r

study <- read_study("path/to/sdtm")
r1 <- check_study(study, standard = "SDTMIG", version = "3.4")
```

A progress bar shows in interactive sessions. Turn it off with
`options(coreval.progress = FALSE)`.

### Check a USDM study design

Put the USDM JSON file in a folder of its own and ask for it. It needs
the `jsonlite` and `QuickJSR` packages, and no `standard`, since the
document is USDM.

``` r

check_study("path/to/usdm", usdm = TRUE)
```

## Questions people ask

**No problems were found. Is my data clean?** Not necessarily. Look at
`result$skipped` first. Checking one dataset on its own leaves out every
rule that compares datasets, and the terminology rules need a CT
release.

**What does `Not in dataset` mean in the `Value` column?** The rule
wanted a variable your dataset does not have. That is usually the
finding.

**What is a `Variable` starting with `$`?** Something the rule worked
out from your data, such as the list of STUDYID values in DM, shown so
you can see what your record was compared against.

**A warning says some files were not read.** A study folder is read from
`.xpt`, `.sas7bdat` and Dataset-JSON files. CSV files are skipped there,
since they carry no types or labels; check one with
[`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md).
If two files hold the same dataset, the warning says which one was used.

**Does anything leave my computer?** No. There is no internet access,
account or API key. The rules and terminology are bundled in the
package.

**Which rules version produced my results?**
`attr(list_rules(), "rules_version")`. It is also recorded in every file
[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
saves.

**A result looks wrong.** Please [open an
issue](https://github.com/hrach-gevorgyan/coreval/issues), ideally with
a small dataset that shows it. A wrong or missing finding is the most
useful thing you can report.

## All the functions

| Function | Use it to |
|----|----|
| `check_dataset(x, standard = )` | check one data frame or file |
| `check_study(path, standard = )` | check a whole study folder |
| `write_findings(result, path)` | save to Excel or CSV |
| `filter_findings(result, ...)` | narrow a result |
| [`list_rules()`](https://hrach-gevorgyan.github.io/coreval/reference/list_rules.md) | look up rules |
| [`list_ct_packages()`](https://hrach-gevorgyan.github.io/coreval/reference/list_ct_packages.md) | list Controlled Terminology releases |
| `read_study(path)` | read a folder once, to check it several times |

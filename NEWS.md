# coreval 0.0.0.9000

First development version. Not released yet, and the API may still change.

A personal open-source project — not affiliated with or endorsed by CDISC, and
not a CORE-certified engine. It's a quick local check to run *before* your
qualified validation tool, never instead of it.

## What you can do with it

* **Check one dataset** with `check_dataset()` — a data frame you already have
  open, or a single `.xpt`, `.sas7bdat` or `.csv` file. No study folder needed.
  This is the one for when you're mid-way through writing the code that builds a
  domain. coreval works out the domain from your `DOMAIN` column, or the file
  name. Rules that need a dataset you didn't supply are skipped and say so,
  rather than being run against columns that aren't there.
* **Check a whole study** with `read_study()` on a folder, then `check_study()`.
  It reads XPT, SAS and CSV, and picks up Define-XML (2.0 or 2.1) if it's there.
  Reading everything at once is what makes the cross-dataset rules work.
* **Read what's wrong in plain language.** Printing a result gives you a report
  grouped by problem, worst first, each described in words — "Variable value is
  not in correct ISO 8601 date or datetime format" — with the rows and values
  that caused it and the rule number at the end. The same description is on
  every row of `$findings` as an `issue` column, so a rule number is never the
  only thing you get.
* **Findings are triaged**, so the ones that are definitely wrong come first.
  CDISC Open Rules carry no severity field — Pinnacle 21's Notes/Minor/Major/
  Critical is P21's own layer, not CDISC's — so coreval does not report one and
  does not invent one. What it does is separate `wrong value` (your data breaks
  the rule: a month of 13, a value outside its codelist) from `missing required`
  and `missing optional` (often legitimate — a screen-failure subject, a
  variable your raw data does not carry yet). Sorting by row count alone put
  those in the wrong order. It is a `triage` column on every finding, so a
  spreadsheet can be sorted by it too.
* **A whole-study report is grouped by dataset**, with a summary of which
  dataset has the most problems before any detail, so you can see where the
  trouble is at a glance. `print(result, n = 20, rows = 5)` shows more.
* **Rules that only say "at least one variable is missing" now name which
  ones.** Both sets the rule compared are in the finding, so the difference
  between them is shown: `missing required variables: SUBJID, SITEID,
  COUNTRY`.
* **See what couldn't be checked**, always, in a second table with a reason for
  each. An empty findings table can mean clean data *or* rules that never ran,
  and those look identical otherwise.
* **Save it and track it** with `write_findings()` to Excel (one workbook, two
  sheets) or CSV (two files). The file carries empty `Status`, `Owner` and
  `Notes` columns for you to fill in, so "expected, see protocol deviation log"
  lives next to the finding instead of in another document. Both tables are
  written every time; pass `tracking = FALSE` to leave the extra columns out.
* **Look at the rules themselves** with `list_rules()`, `rules_for_domain()` and
  `rules_version()` — including which CDISC commit they came from and how much
  each rule can be trusted.
* A **Getting started** vignette walks through all of it, on a small study built
  as you read, so it runs without any data of your own.

## Speed

* Checking is **dramatically faster** - roughly 50x on large data. Four things
  were doing per-row work on whole columns: the date operators called
  `grepl()`/`regexpr()` once per value; findings were assembled one
  `data.table` per violating record; the code building reported values re-decided what kind
  of thing each variable was for every row; and the uniqueness operators
  answered "does this key repeat?" by building an interaction factor and
  sorting it, rather than by hashing.

  | rows | before | after |
  |---|---|---|
  | 10 000 | 37 s | 1.1 s |
  | 200 000 | ~12 min | 18 s |
  | 1 000 000 | ~1 hour | 71 s |

  Finding counts are identical at every size.
* Findings are **capped at 1000 records per rule** by default. A rule can flag
  every row - a missing `EPOCH` on a 200 000-row `LB` is 200 000 identical
  findings, beyond what anyone reads or Excel can hold. The true count is kept
  in the new `truncated` table and shown in the report ("1 000 000 records
  (first 1 000 kept)"), so nothing is under-reported. `max_records = Inf`
  keeps everything.
* A progress bar appears for long checks when running interactively, so a slow
  study no longer looks like a hang. `options(coreval.progress = FALSE)` turns
  it off; it is already off in scripts.

## Fixed

* **Factor columns no longer crash the check.** A factor is text to every rule
  but an integer vector underneath, so the whole run died with `'nzchar()'
  requires a character vector`. `read.csv(stringsAsFactors = TRUE)` and plenty
  of older code still produce factors, so they are converted rather than
  refused.
* **A trailing blank in `DOMAIN` no longer changes the answer.** `"AE "` was
  treated as a domain of that name: it scoped to a different rule set, and
  resolved `"--STDTC"` to `"AE STDTC"` - a column nothing has - so every
  `"--"` rule silently found nothing. (The padded value is still reported as
  a problem in its own right, by the rules that exist to catch exactly that.)
* **A dataset with no rows, or an all-blank `DOMAIN`, says which it is.** The
  old message claimed there was "no single DOMAIN value", which reads as "your
  column is inconsistent" to someone whose data simply has no rows yet.
* `days_in_month()` was wrong for vector input: it built its lookup table with
  `c(31, ifelse(leap, 29, 28), 31, ...)`, which produces one element per YEAR
  rather than one per month, so for n years the table was 11 + n long and every
  month from March on read the wrong slot. Correct for a single value and
  wrong for a column - which the old per-row date code hid completely.
  `"2003-11-31"` was rejected when checked alone and accepted when checked as
  part of a column.

## What's covered

* **756 rules** for SDTM, SEND and TIG, bundled inside the package. Nothing is
  downloaded — no internet, no API key, no account, and your data stays put.
* **Around 60 rule operators**, including comparison of partial dates (SDTM
  dates are legitimately incomplete, like `2024-03`), grouping and uniqueness
  checks, and set membership.
* **Cross-dataset joins** — RELREC relationships, SUPP/SQ supplemental
  qualifiers, and parent-child joins — plus the `Operations` pipeline that
  pre-computes values rules refer to.
* **CDISC Library variable metadata** for SDTM, SEND, ADaM and TIG, so rules
  comparing your variables against the standard's can actually run, and SEND
  studies are checked against SEND metadata rather than refused. Taken at build
  time from the offline cache CDISC's own engine ships with; no CDISC API is
  contacted, ever.

## How much you can trust it

* Checked by replaying CDISC's own reference test cases and comparing flagged
  records one by one. It currently agrees with CDISC on **488 of 511** published,
  fully executable rules that ship reference data — about 95%. The README
  explains the other denominators and why there's more than one.
* A rule that can't be evaluated is always reported as skipped, with a reason,
  never counted as a pass.

## What it can't do yet

* **No ADaM rules.** CDISC publishes 197 of them, but none currently ships
  reference results, so there's no published expected output to check an
  implementation against. Including them would mean asking you to trust checks
  nobody has verified. They go in as soon as that data exists.
* **No Controlled Terminology term lists.** That data runs to roughly 438 MB and
  belongs in a separate package. The CT package *dates* are bundled, so rules
  checking that a study cites a real terminology version do run.
* **Split domains** are handled for uniqueness — a value appearing once in each
  of two files is correctly reported as a duplicate. A few rules that expect
  findings merged under one dataset name, rather than reported per file, are
  still skipped.
* **Numbers are reported as parsed**, so a source value of `0.0` comes back
  as `0`.
* **Not a CORE-certified engine.** These figures describe agreement with CDISC's
  published reference data. They aren't certification.

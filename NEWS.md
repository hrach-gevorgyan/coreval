# coreval 0.2.0.9000 (development)

* **Fixed: `max` was a date operation, and should never have been.** The
  reference has four separate operations where coreval had two: `max`/`min` are
  plain aggregates over whatever the column holds, and only `max_date`/
  `min_date` parse ISO 8601. Both went through the date picker here, which
  validates against a date regex and yields nothing for anything else, so `max`
  over a text or numeric column produced no binding and the rule using it
  quietly found nothing.

  Exactly one bundled rule uses `max`, and its column is a date, so no shipped
  result was wrong. It is fixed because the next rule to use it might not be,
  and because a missing binding is the silent kind of failure. `min` now exists
  too.

* A rule can now scope by USDM entity (`Scope: Entities`). A scope key the
  resolver did not recognise was skipped, which meant every other test passed
  by default and the rule matched every dataset in the study rather than none.

* **Reads CDISC Dataset-JSON and Dataset-NDJSON.** These are the formats CDISC
  publishes as the successor to transport files, and `check_study()` now takes
  a folder of either. `jsonlite` is a `Suggests`, so the runtime dependencies
  are still `data.table` and `haven`; without it a Dataset-JSON study raises
  rather than reading as empty. Where a folder holds both, transport files win,
  since a folder holding both is a conversion in progress and the transport
  files are what a submission is made of.

  Verified by round-trip rather than against an answer sheet, because CDISC
  publishes no Dataset-JSON reference data: the same study written as XPT, as
  Dataset-JSON and as Dataset-NDJSON has to produce the same findings, on the
  same rows, from the same rules. A dropped row or a shifted column breaks that
  and keeps the count.

  Two kinds of broken file are refused rather than read. Rows that do not all
  match the declared column count are malformed, and a file whose `records`
  count disagrees with the rows it carries has been truncated. CDISC's own
  engine returns an empty dataset when a Dataset-JSON fails schema validation,
  which turns a broken file into a clean bill of health.

# coreval 0.2.0

* **Fixed: a malformed CSV lost records, or every column name.** Three separate
  ways, all silent, all found by reading the warnings the conformance sweep had
  been printing and nobody had opened:

  * A short last row was treated as a footer and discarded. CORE-000103's
    `pr.csv` holds three records and coreval saw two.
  * A row with more fields than the header made the reader abandon the header
    and name the columns after the first row's values, so the same fixture's
    `ce.csv` came back with columns called `1234.0` and `Fracture` and no
    `CETERM`, `CECAT` or `CESCAT`. Every rule about them found nothing and the
    dataset looked clean. Both rules reading it still passed, because finding
    nothing was what their answer sheet expected.
  * Separator detection could choose whitespace over the comma on a file whose
    fields carry trailing spaces, returning `V1`..`V13` from a ten-column file.

  The reader now pads a short row instead of dropping it, as the reference does
  through pandas, keeps the header as the header, and states the separator
  rather than letting it be guessed. A row with more fields than its header is
  still reported, since that file really is invalid.

* **A define.xml that cannot be read now says so.** It used to return the same
  nothing as a study with no define.xml at all, so a truncated or non-Define
  file was indistinguishable from one that was never supplied. Worse once the
  define became a source of the CT version: the rules that needed it skipped
  saying "this study does not say which terminology it follows, pass
  ct_package", which is true of the parsed result and useless to someone whose
  file simply stops mid-element. The warning now names the file and the reason,
  down to the line.

* **Define-XML now says which controlled terminology a study follows.** A
  Define-XML 2.1 records it in `def:Standards`, the same way TS records it in
  `TSVCDVER`, and coreval reads it instead of asking. TS still wins where both
  say; the define is used when TS is absent or cites no CDISC version.

  This is what CORE-000929 was actually blocked on. The rule compares the term
  codes in a variable's codelist against the `DOMAIN` codelist's, and that
  codelist has 150 terms in the 2020-12-18 terminology its fixture's define
  cites and 85 in the newest. Answered from the wrong release it flagged a
  clean `CM`.

* **The term codes inside a variable's Define-XML codelist are read**
  (`define_variable_codelist_coded_codes`). These come from the study's own
  define.xml and were previously refused as detail coreval does not read, which
  was the wrong diagnosis: nothing about them needs bundling.

* **Fixed: `is_contained_by` ignored a collection on the target side.** The
  operator handled a comparator that varies per row but not a target that is
  itself a set per row, so it compared the set against the values and reported
  a violation for every row. The reference treats a row as contained when ANY
  of its items is in the comparator, which reads as too weak and is what it
  does.

* Three more rule types run: `split_by`, `get_codelist_attributes` and the
  per-row form of `contains_all`/`not_contains_all`. The last was the reason
  CORE-000934 found nothing - the reference compares row by row when each row
  has its own collection, and coreval only had the dataset-level path, so its
  single verdict landed on row 1.

* **The controlled terminology version is read from TS.** Studies record it
  themselves - `TSVCDREF` names the publisher and `TSVCDVER` the version - so
  `check_study()` picks it up without being told. `ct_package` stays as the
  manual override. Rows citing someone other than CDISC are ignored, and where
  a real TS carries stale rows the version most rows agree on wins.

* **Controlled Terminology checks now run.** Nine rules ask whether a value is
  a legal term - `SEX` may be `F`, `M`, `U` or `INTERSEX` and nothing else -
  and they were skipped because CDISC's terminology caches are 438 MB. Almost
  all of that is definitions and synonyms no rule asks for; the submission
  values, C-codes and extensible flags that conformance actually needs are
  0.54 MB, so every published package is now bundled.

  Tell it which version your study follows:

  ```r
  check_study(dir, ct_package = "sdtmct-2026-03-27")
  list_ct_packages("sdtm")
  ```

  coreval will not choose for you. Terminology moves between releases - `SEX`
  gained `INTERSEX` and lost `UNDIFFERENTIATED` - so judging a study against a
  version it never declared would both invent violations and hide real ones.
  Without `ct_package` those rules are skipped saying exactly that. The table
  is read on first use, so a session that never runs one pays nothing.

* **Fixed: an Operations id without a `$` was treated as literal text.** Six
  rules (`CDISC.SDTMIG.CG0555`-`CG0560`) declare ids like `pkunit_terms` bare,
  so `PPORRESU is_not_contained_by pkunit_terms` compared the column against
  the *string* "pkunit_terms" - never contained by it, so every row whose
  `PPTEST` lacked "norm" was reported, in a clean dataset as much as a dirty
  one.

* **Fixed: an unimplemented Operations type reported nothing instead of
  saying so.** The dispatch fell through to no binding, so the rule's condition
  degraded to literal text and the rule quietly found nothing. CORE-000934 did
  this: CDISC's engine reports two rows on its own fixture and `check_study()`
  reported none. It now names the operation it cannot run.

* The progress bar now names the domain being checked and how far through the
  study it is, and its percentage is weighted by how many records each domain
  holds rather than by a plain count of rules. A check against a 161,600-row
  `AE` costs hundreds of times one against a 200-row `SJ`, so the old bar
  sprinted through the small domains and appeared to hang on the big one.

* The one-row-per-(record, variable) table that some rule types need is built
  column by column into a preallocated vector rather than as one table per
  variable stitched together. It is inherently large - 27 columns of a
  161,600-row AE is 4.4 million rows - and the old shape held every converted
  column and the finished table at the same time. R's reported high-water on a
  511,000-row study fell from 744 MB to 589 MB.

* Date columns are scanned once instead of two to four times. Validating a
  date, detecting its precision and parsing it each re-ran the same expensive
  regex over the same column; the components are now computed once and passed
  along. `--DY` comparisons were the worst case, scanning two columns four
  times.

* The per-rule synthetic datasets are built once per domain instead of once
  per rule. Those builders never depended on the rule, yet about 60 rules each
  asked for the identical answer, and computing one of them scans every
  variable against every record. Checking a 511,000-row study went from 77s to
  about 47s. The cache lives for one sweep only and holds 0.1 MB.

* The bundled rule table is built once per session instead of once per domain.
  It was 600 MB of the 2.9 GB a 51,000-row study allocated - a fifth of
  everything, none of it touching your data. Checking a 511,000-row study went
  from 113s to 77s.

* **Checking a large study is dramatically faster.** The cross-dataset match
  that joins a supplemental or related dataset to its parent looped over every
  child row and rescanned the whole parent each time. It was 90% of
  `check_study()`'s entire runtime and got worse than linearly with size. It is
  now a single grouped join per distinct `(RDOMAIN, IDVAR)` combination.

  On a CDISCPILOT-shaped study:

  | rows | before | after |
  |---|---|---|
  | 5,000 | 18.4s | 4.9s |
  | 51,000 | 122s | 11.1s |
  | 511,000 | ~21 min | 73s |

  The answers are unchanged: the new join was compared against the old one on
  173 fixture cases and is bit-identical, the conformance sweep is unmoved at
  697/54/46, and no failing rule's reported records changed either.

* **`domain_label` now means what the standard calls a domain**, not what your
  own dataset metadata happens to call it. The two differ: SENDIG calls `LB`
  "Laboratory" where SDTMIG calls it "Laboratory Test Results". CORE-000272
  asks whether `--CAT` equals that label, so on a SEND study coreval was
  answering a different question and missing the finding. Per-standard dataset
  labels are now bundled (483 of them, 4 standards). A domain no standard
  defines still falls back to your own label.

* **Fixed a false-positive class: a variable that isn't there is no longer
  treated as failing a date or uniqueness test.** Three operators were written
  as plain negations of their positive counterparts, which answer `FALSE` for a
  column the dataset does not have - so negating them answered `TRUE`.
  `is_incomplete_date` was the damaging one: CORE-000138/139 ask whether
  `DM.RFSTDTC` is an incomplete date while `--STDY` is populated, so on a study
  with no DM every record carrying a study day was reported. On a
  three-dataset test study that was 267 of 393 findings - noise that buries the
  real ones. `is_unique_set` and `is_unique_relationship` had the same shape.

  Found by running CDISC's own rules engine over the same data and comparing
  rule by rule: it reports nothing for those rules, coreval reported hundreds.
  The conformance pass rate did not move at all, in either direction.

* **Codelist checks against Define-XML now run.** coreval reads the codelist
  C-code a Define-XML file attaches to each variable, and bundles the code the
  CDISC Library expects for it, so a rule can tell you when your define
  declares the wrong codelist for a variable or declares none where the
  standard has one. One rule (SENDIG SEND49) moves from skipped to running.

  Only the *identity* of a codelist, never its terms: which values are legal
  for `SEX` is Controlled Terminology, around 438 MB, and still deliberately
  not bundled. Rules asking what is inside a codelist continue to skip with a
  reason.

* **Rules refreshed** from a newer upstream commit of CDISC's rule repository.
  One rule's scope changed (CORE-000892 now applies to Special Purpose domains
  rather than Findings), which changes the domains it runs on from 62 to 25.

* `write_findings()` names the offending argument when given a path that isn't
  a single string, instead of surfacing an error from inside `data.table`.

* Documentation fix: `findings` is one row per affected *record*. Three places
  called it "one row per problem", which is what `summary()` counts and a
  different number.

# coreval 0.1.0

First release. The API is settled for 0.1.x; anything that changes will go
through a deprecation cycle rather than disappearing.

A personal open-source project. Not affiliated with or endorsed by CDISC, and
not a CORE-certified engine. It's a quick local check to run *before* your
qualified validation tool, never instead of it.

## What you can do with it

* **Check one dataset** with `check_dataset()`: a data frame you already have
  open, or a single `.xpt`, `.sas7bdat` or `.csv` file. No study folder needed.
  This is the one for when you're mid-way through writing the code that builds a
  domain. coreval works out the domain from your `DOMAIN` column, or the file
  name. Rules that need a dataset you didn't supply are skipped and say so,
  rather than being run against columns that aren't there.
* **Check a whole study** with `check_study()` on a folder. It reads XPT, SAS
  and CSV, and picks up Define-XML (2.0 or 2.1) if it's there. Reading
  everything at once is what makes the cross-dataset rules work. `read_study()`
  is there when you want the parsed study itself, or want to check the same
  large study more than once without re-reading it.
* **Read what's wrong in plain language.** Printing a result gives you a report
  grouped by problem, worst first, each described in words, "Variable value is
  not in correct ISO 8601 date or datetime format", with the rows and values
  that caused it and the rule number at the end. The same description is on
  every row of `$findings` as an `issue` column, so a rule number is never the
  only thing you get.
* **Findings are triaged**, so the ones that are definitely wrong come first.
  CDISC Open Rules carry no severity field. Pinnacle 21's Notes/Minor/Major/
  Critical is P21's own layer, not CDISC's, so coreval does not report one and
  does not invent one. What it does is separate `wrong value` (your data breaks
  the rule: a month of 13, a value outside its codelist) from `missing required`
  and `missing optional` (often legitimate: a screen-failure subject, a
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
* **Save it and track it** with `write_findings()` to Excel or CSV. You get
  `findings`, `skipped`, an `about` sheet and - when a rule matched more
  records than were kept - `truncated`. The file carries empty `Status`,
  `Owner` and `Notes` columns for you to fill in, so "expected, see protocol
  deviation log" lives next to the finding instead of in another document.
  Pass `tracking = FALSE` to leave those out.
* **Provenance travels with the exported file.** `about` records which
  standard the run was scoped to, how many checks ran, whether the result was
  filtered before export, and whether any counts were capped. A shared
  spreadsheet outlives the console session that made it, and whoever opens it
  cannot otherwise tell that it is partial.
* **Cross-refer to Pinnacle 21.** Every rule now carries the legacy
  conformance-rule ids it descends from - `CG0665`, `SEND66`, `TIG0699`,
  `FB0801` - which are the ids P21 and the published Conformance Rules
  spreadsheets use. The report shows them next to the CORE id, so a finding
  here can be matched to a finding there, including to a severity CDISC itself
  does not publish. All 797 rules have at least one.
* **The "why", from the Implementation Guide itself.** Each rule carries the
  sentence it exists to enforce, with document and section: *"The SENDIG
  requires dates and times of day to be stored according to the international
  standard ISO 8601 (SENDIG v3.0 4.4)"*. `print(result, guidance = TRUE)` shows
  it under each problem - off by default, since it roughly doubles the report -
  and `list_rules()` always returns it.
* **One function for every question about the rule set.** `list_rules()` now
  answers all three: `list_rules()` for the catalog, `list_rules(id =
  "CORE-000547")` to look up a rule the report named, `list_rules(domain =
  "AE")` for what applies to a domain. The columns are the same whatever you
  ask, so the result is safe to filter, join and script against.
  `rule_info()`, `rules_for_domain()` and `rules_version()` are gone -
  the last is now `attr(list_rules(), "rules_version")`, and
  `write_findings()` records it in every exported file anyway.
* **`summary()`** gives the counts in three lines, for a script or a quick
  "did that fix help?", and returns them as a row you can log.
* **`filter_findings()`** narrows a result by triage, dataset, rule or
  variable, and returns a result - so it still prints as a readable report,
  and says it is a subset rather than passing for the whole picture.
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

## Fewer rules, better aimed

* **Rules are scoped to the standard your data follows.** `standard = "SDTMIG"`
  was accepted and silently ignored before, so an SDTM study was also measured
  against SENDIG rules - 73 of the 270 rules in scope for DM are SENDIG-only.
  Declaring it now halves the rules and more than halves the reported problems,
  losing no real coverage. Matched exactly, so a `SENDIG` study does not pick
  up `SENDIG-DART` rules.
* **Rules are scoped to the Implementation Guide VERSION too**, when you
  declare one: `check_dataset(dm, standard = "SDTMIG", version = "3.4")`. Rules
  are written per version - 408 SDTMIG rules exist for 3.2 against 445 for 3.4,
  and 86 apply to exactly one version - so without this a 3.2 study is measured
  against rules written for a guide it does not follow. `"3-4"` and `"3.4"` are
  both accepted, since CORE test cases write the first and the rules the
  second.
* **Deprecated rules are no longer run** unless you ask for them with
  `include_deprecated = TRUE`. A deprecated rule has a published replacement,
  so running both reports the same defect twice.
* Together these are why one problem could appear three times: once from the
  SDTMIG rule, once from its SENDIG equivalent, once from a deprecated
  predecessor. Declaring the standard now reports it once.
* When no standard is declared, every standard's rules still run - coreval does
  not guess - but the report **says so**, instead of quietly reporting SEND
  findings on SDTM data.

## Licensing and API

* **The MIT notice for the bundled CDISC material now ships with the package**,
  in `inst/COPYRIGHTS`. cdisc-open-rules is MIT licensed, and MIT requires the
  copyright and permission notice to accompany substantial portions of the
  work - coreval bundles 797 extracted rules and CDISC standards metadata, but
  the notice lived only in `NOTICE.md`, which is excluded from the build and so never
  reached anyone who installed the package. A test now guards it.
* **`check_study()` takes a folder path**, so `read_study()` is now optional:
  `check_study("study/sdtm")` instead of reading first. Reading yourself is
  still worth it to inspect what was parsed, or to check the same large study
  twice without re-reading it.
* `sdtm_domain_classes()` is no longer exported - a domain-to-class lookup
  table answers a question nobody working with their own data has.
* `evaluate_rule()` is no longer exported. It returned a raw logical vector,
  needed a rule record fetched from package internals, and had no story a user
  could follow now that `check_dataset()` exists.

## Coverage

* **41 more rules**, from `Unpublished/SDTMIG` and `Unpublished/SENDIG` -
  folders the extractor never opened. Both are SDTM- and SEND-shaped, so this
  engine can read their data, and only the ones CDISC already ships expected
  results for are taken (11 of 128, and 30 of 77). That is the whole remaining
  gap: of the 767 upstream rules in a readable format that CDISC ships results
  for, coreval now has 767.
* Still excluded, and why: **USDM** (259 rules) is a JSON study-design model,
  not tabular datasets - `read_study()` cannot read it at all.
  **Unpublished/ADAMIG** (93) ships test data but *no* expected results for a
  single rule, so nothing there can be verified. Another 292 readable rules
  have no expected results either.
* Two new operators, `contains_case_insensitive` and
  `does_not_contain_case_insensitive`.
* **13 TIG domains added to the domain-to-class table.** It claimed to cover
  TIG and did not: 42 of the 55 TIG domains happen to be shared with SDTM/SEND
  and resolved by accident, while `TO`, `PT`, `IN`, `RELREF` and nine others
  resolved to nothing. Every rule scoped to one failed its `Scope > Classes`
  check and was skipped as "no dataset matches the rule's scope" - with the
  right dataset sitting in the test case. Taken from the same CDISC cache as
  the rest of the table, and checked against the 42 shared domains first: no
  conflicts.

## What's covered

* **797 rules** for SDTM, SEND and TIG, bundled inside the package. Nothing is
  downloaded. No internet, no API key, no account, and your data stays put.
* **Around 60 rule operators**, including comparison of partial dates (SDTM
  dates are legitimately incomplete, like `2024-03`), grouping and uniqueness
  checks, and set membership.
* **Cross-dataset joins**: RELREC relationships, SUPP/SQ supplemental
  qualifiers, and parent-child joins, plus the `Operations` pipeline that
  pre-computes values rules refer to.
* **CDISC Library variable metadata** for SDTM, SEND, ADaM and TIG, so rules
  comparing your variables against the standard's can actually run, and SEND
  studies are checked against SEND metadata rather than refused. Taken at build
  time from the offline cache CDISC's own engine ships with; no CDISC API is
  contacted, ever.

## How much you can trust it

* Checked by replaying CDISC's own reference test cases and comparing flagged
  records one by one. It currently agrees with CDISC on **540 of 562** published,
  fully executable rules that ship reference data, about 96%. The README
  explains the other denominators and why there's more than one.
* A rule that can't be evaluated is always reported as skipped, with a reason,
  never counted as a pass.

## What it can't do yet

* **No ADaM rules.** CDISC publishes 93 of them, but none currently ships
  reference results, so there's no published expected output to check an
  implementation against. Including them would mean asking you to trust checks
  nobody has verified. They go in as soon as that data exists.
* **No Controlled Terminology term lists.** That data runs to roughly 438 MB and
  belongs in a separate package. The CT package *dates* are bundled, so rules
  checking that a study cites a real terminology version do run.
* **Split domains** are handled for uniqueness: a value appearing once in each
  of two files is correctly reported as a duplicate. A few rules that expect
  findings merged under one dataset name, rather than reported per file, are
  still skipped.
* **Numbers are reported as parsed**, so a source value of `0.0` comes back
  as `0`.
* **Not a CORE-certified engine.** These figures describe agreement with CDISC's
  published reference data. They aren't certification.

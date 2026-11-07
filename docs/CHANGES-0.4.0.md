# coreval 0.4.0: every change

The full list behind the short notes in `NEWS.md`, changes against 0.3.0.

* **Findings name the subject.** `result$findings`, the report and the files
  `write_findings()` writes gain `USUBJID` and `SEQ` (the record's `--SEQ`)
  beside `Record`, as both reference engines report them. A row number stops
  meaning anything once the data is sorted. They are blank where the dataset
  has no such variable, for a finding about the dataset as a whole, and for a
  rule about variable or dataset metadata, whose rows are not records.

* **The Excel file is laid out for a person.** It used to hold the raw
  tables. It now has four sheets:
  - `Problems`: one row per problem, definite errors first, with what is
    wrong, the variables it names (the missing ones for a "required variable
    is missing" rule) and how many records it affects. On CDISC's pilot study
    that is 142 rows.
  - `Records`: one row per affected record and problem, found by `USUBJID` and
    `SEQ`, reading `AETERM = "Nausea"; AESTDTC = "2024-02-30"`, with blanks
    shown as `(empty)` and absent variables as `(not in dataset)`.
  - `Not checked`: the checks that could not run, grouped by reason, with
    what to do about each, then when and how the check was run.
  - `Rules`: every rule, and whether it found problems, found none or could
    not run. A rule that ran and found nothing was listed nowhere before,
    which left "clean" and "never checked" looking alike. The result carries
    the list in `attr(result, "ran")`.
  The CSV files keep the raw tables for reading back into a program, plus a
  new `_summary.csv`.

* **A missing column is no longer a "wrong value".** Rules report neighbouring
  columns as context, so "AEDY is missing when AEDTC is present" came out as a
  wrong value and sat among the definite errors. A problem now counts as
  missing when the rule tests the absent column and judges no other value,
  read from the rule's own conditions. On CDISC's pilot study 14 of 103 moved.

* **The MedDRA release check no longer fails on ordinary data.** CORE-002041
  stopped with an error on any TS holding text in `TSVAL`, which is every TS,
  and was reported as a check that could not run.

* **Older versions are checked, with a note.** A version older than any the
  rules are written for, such as SDTMIG 3.1.2, used to stop with an error. It
  is now checked against the oldest version with rules, and the report and the
  file say so. A version newer than the rules is still refused.

* **Only the study's own rule numbers.** A rule serving several standards
  carries each one's number. The report and the file now show only those for
  the declared standard, so an SDTM study no longer lists SEND and TIG
  numbers beside CG ones.

* **More of "could not run" is explained.** The report groups three more
  reasons: variables the data does not have, reference data coreval does not
  include, and the study tagging file. On the pilot study most of what was
  "other reasons" now falls in a named group.

* **A CORE 1.0 finding names its variable.** Rules that check many variables
  at once reported `variable_name = "RFSTDTC", variable_value = "2024-13-01"`,
  with `Variable` set to `variable_value`, so a filter on the `Variable`
  column in Excel or R missed them. They now read
  `RFSTDTC = "2024-13-01"`, like every other rule.

* **`standard` is required.** `check_study()` and `check_dataset()` stop
  without it, as CDISC's and Verisian's engines do. Left out, every
  standard's rules ran: on CDISC's pilot SDTM study, 45 SEND and TIG rules
  added 26,678 problems, a third of the report. Add `standard = "SDTMIG"` (or
  `"SENDIG"`, `"TIG"`, ...) to existing calls. A USDM document, and a CORE
  test case with a `.env` file, declare their own and need nothing.
  `check_dataset(dm, "SDTMIG")`, where the second argument is the domain, says
  so and shows the fix.

* **CORE 1.0.** CDISC's CORE 1.0 (3 November 2026) moved the SDTMIG and FDA
  Business Rules to Verisian's repository, verisianHQ/core-contributor, and
  its engine; SENDIG, TIG and USDM stay with CDISC. coreval follows:
  - An SDTM study is checked with the 1.0 rules: 621, of which 130 are new.
    A SEND or TIG study is checked with CDISC's rules, as before, including
    CDISC's version of a rule both repositories carry.
  - A 1.0 rule runs the way 1.0's engine runs it where the two engines
    differ: patterns search anywhere in a value, a filter wildcard is `%`,
    text and numbers compare by value, and a few more.
  - CDISC's SDTM rules that 1.0 does not carry run on an SDTM study only with
    `include_deprecated = TRUE`.
  - `rules_version` now names both repositories and their commits.
  - Several checks quietly found nothing and now work: a list of columns
    where one was expected, a related record's variable as the thing checked,
    the dataset name in a Value Check with Dataset Metadata rule, and a
    written-out list read as its first item. Rules naming metadata coreval
    does not build yet are skipped with the reason instead.
  - New rule types for 1.0's rules: dataset contents against the define
    (class, IsNonStandard, whether the define's key variables identify each
    record), define items, values against the define's value-level metadata
    and against the Library's codelists, the study-wide variable length
    check, and the study tagging file (`stf.xml`, now read beside the
    define).
  - The FDA guides list and Data Standards Catalog, and the ISO 3166 and
    GENC country lists, are bundled from 1.0's engine for the rules that
    read them. Rules that need MedDRA, WHODrug, UNII, LOINC, SNOMED CT or
    MED-RT say which dictionary they need.
  - `contains` against a column now checks each record. Asked whether each
    COUNTRY was a valid code, it answered once for the whole dataset.
  - Checked against Verisian's engine on CDISC's pilot submission, rule by
    rule; docs/REAL-STUDY.md has the comparison. Where the two disagreed
    because coreval had 1.0's behaviour wrong, coreval now follows it:
    `type_insensitive: true` compares as text, so an IDVARVAL of "01" or
    "   2" differs from the parent's sequence number (CORE-000206); a
    comparison with the column each record names finds that column in any
    case; a complete date is a matter of shape; and a duration may carry one
    decimal anywhere.
  - SDTMIG 3.2 was checked against the 3.4 Library, and SUPP datasets had no
    Library variables at all.
  - Variable lengths are read from a transport file's header and from
    Dataset-JSON, for 1.0's length rules. CORE-002062 reported the longest
    value of every row in each finding: 644,030 numbers for one SUPPLB.

* **Findings that were not real.**
  - A stored SAS date keeps its declared numeric type, and a column with no
    values at all reads as empty text rather than a number, so the type
    rules no longer report either one.
  - A RELREC relationship linked records of different subjects whenever the
    subjects reused a RELID, so a findings-about record was compared with
    another subject's adverse event (CORE-000744, CORE-000757).
  - Checking one dataset on its own, a CORE 1.0 rule that reads values from
    another dataset treated the missing one as empty, so CORE-000172
    reported every record of an AE for a STUDYID "not in DM". Such a rule is
    now skipped, saying which dataset it needs.
  - Checking one dataset on its own, the rules about the study as a whole
    ran too, so a single DM was told its study had no define.xml and no
    trial design datasets. They are skipped there now.
  - A dataset with no records had every text column typed as a number, so
    the variable type rule reported each one.
  - CORE 1.0 checks a record with no partner in a joined dataset only where
    the rule asks for that; otherwise the record is left out, as 1.0's
    engine does. An AE for a subject missing from DM was reported by every
    rule comparing AE dates with DM's.
  - CORE 1.0's length checks, its prefix and suffix pattern checks and its
    string-part check answer "no problem" for a blank value, as 1.0's engine
    does (CORE-000180, CORE-000538). `prefix_equal_to` ignores case in 1.0,
    so a DOMAIN of "lb" is no longer reported (CORE-000598).
  - Two CORE 1.0 rules about Associated Persons datasets took in split
    datasets, so LBCH and LBHE were reported as badly named AP datasets
    (CORE-000778, CORE-000357).
  - In a bare CSV, text such as " 5" or "0x1A" was read as a number, so a
    leading space went unreported. Only plain numbers make a column numeric.
  - With a domain RELREC does not mention, or no RELREC at all, every record
    of that domain was reported.
  - A Define-XML 1.0 was read with every label blank, so the rule comparing
    labels with the define reported every labelled variable. CDISC's pilot
    submission uses Define-XML 1.0.
  - Less-than and greater-than compared text as text where the reference
    compares numbers, so "150" was less than "LOW".
  - A rule joining a dataset the study lacks compared against the missing
    columns' names: with no DM, every death in DS was reported by CORE-000034.
    Such a rule is now skipped, saying which dataset it needs.
  - An SDTM study checked with no standard declared was told that ADSL and the
    tobacco dataset TO were missing.
  - A few smaller cases: `has_same_values` ignored blanks, and
    `is_not_unique_relationship` against a missing column depended on row
    order.

* **TIG studies say which kind they are.** `check_study()` and
  `check_dataset()` take `substandard = "SDTM"`, `"SEND"` or `"ADaM"`, required
  with `standard = "TIG"`, as CDISC's engine requires it. A TIG rule's use case
  covers different datasets in each, and without it a TIG dataset was given
  the rules for both. `list_rules()` takes it too, optionally.

* **Problems that were never looked for.**
  - CORE-002123, the check that a value is a term of a non-extensible
    codelist, searched the codelist as text, so a wrong value that is part of
    a real term passed: SEX = "X" was found inside INTERSEX. It now asks
    whether the value is one of the terms, as CORE 1.0's engine does.
  - A rule with one row per value, such as CORE-002123, reported one finding
    per record, so a second bad value on the same record was dropped. Each
    variable's value is now its own finding.
  - A TIG study declared SEND or ADaM was checked against TIG's SDTM variable
    lists, labels and terminology, and was told its DM lacked RACE. The
    sub-standard now decides all three, as it does in CDISC's engine, and a
    CORE test case's own `SUBSTANDARD` is read.
  - A CORE 1.0 rule joining on a column the dataset lacks passed; 1.0's
    engine stops there, and the rule is now skipped with the reason
    (CORE-000270 on an AE with no VISITNUM).
  - CDISC's sort-order check flags the records CDISC's engine flags, which a
    test on 4,912 generated records confirms; comparing neighbouring pairs
    flagged both rows of a bad pair, and every row around a blank date. It
    also checks every sort column the rule names, not only the first.
  - CDISC's length checks skip a rule that measures a number, as CDISC's
    engine does, compare the lengths of two columns' values, and count a blank
    as length 0.
  - A CORE 1.0 rule finds a column whatever the case of its name, so a CSV
    with lower-case headers is checked.
  - A CORE 1.0 comparison with a computed value that came out empty is decided,
    as 1.0 decides it, rather than left unknown.
  - CORE 1.0 pairs blank text join keys, as its engine does.
  - A SEND study checked with `standard = "SENDIG"` was judged against SDTM
    terminology. The terminology now follows the standard.
  - A TS citing `TSVCDREF = "CDISC CT"`, which both engines accept, named no
    terminology, so every terminology rule was skipped.
  - CORE 1.0's `contains_all` gave its answer on the first record only, so
    CORE-002058 missed a TS whose CTAUG row was not the first.
  - A CORE 1.0 SUPP merge with a blank IDVAR, or a qualifier named like a
    parent variable, was answered; 1.0's engine stops there, and the rule is
    now skipped with the reason.
  - A blank sort date in a CORE 1.0 order check sorts first, as 1.0's engine
    sorts it, rather than being set aside (CORE-000535).
  - `check_dataset(x, domain = "AE")` on data whose DOMAIN column says DM ran
    AE's rules and none of DM's. It is refused now.
  - A stray copy such as `dm_old.xpt` beside `dm.xpt` was merged into DM
    without a word. It is named in a warning.
  - A one-column CSV with spaces in its values lost its header row.
  - A rule whose check names only a computed value reported nothing when it
    found something. CORE-000579 found an empty dataset and passed it, and
    three SEND TX rules found their problems and said nothing.
  - A CDISC rule whose check reads a column the dataset lacks answered "no
    violation". CDISC's engine skips such a rule, and now coreval does too,
    saying which column it needs; within an `any`, a branch on a missing
    column counts as no match, as it does there. `is_unique_set` keeps the
    columns that exist, as the engine does, rather than answering FALSE.
  - An operation grouping, filtering or collecting by a column its dataset
    lacks dropped the column, or the filter, or answered "no violation". It
    is now skipped with the reason, as both engines skip it. A grouping
    column written as `--TESTCD` was never matched at all, so CORE-001034
    counted repeats across every test at once.
  - A SAS transport file holding more than one dataset was read as one, with
    the second dataset's header and records as rows of rubbish, and the rules
    reported on them. It is now refused.
  - A single CSV given to `check_dataset()` dropped a short last row without
    a word, and a row with one value too many shifted every column. Both are
    refused, as a folder of CSVs already refused them.
  - A dataset split across files (LB1, LB2) was scoped, classed and looked up
    under its file name, and about a hundred rules per domain passed it by.
    Split files now get the rules of their domain.
  - Sponsor-defined domains got no class, so every class-scoped rule skipped
    them; Findings About domains (FA, SR) got none of the rules written for
    Findings.
  - SUPP qualifiers written the way SAS writes them ("       1"), or as "1.0",
    or for sequence numbers of 100,000 and more, joined nothing.
  - One word such as BLQ in a results column switched off every numeric
    comparison in it.
  - A folder holding any .xpt file ignored its .sas7bdat and Dataset-JSON files,
    and then reported their datasets as missing. Every dataset file is now read.
  - Date-time columns, from R or from a SAS DATETIME variable, were not read as
    ISO 8601, so the date rules found nothing in them.
  - An operation over a dataset the study lacks answered "no violation" for
    every row. It is now skipped with the reason.
  - Ten define-based presence rules for SEND could never fire.
  - A Dataset-JSON cell holding the word "study" made the whole folder read as
    an empty USDM study.
  - About a dozen rules stopped on any date-time column, each reported as
    skipped with "character string is not in a standard unambiguous format".
    A CSV folder described by a `_variables.csv` keeps such a column as a
    date-time; CDISC's ADaM examples lost CORE-000690, which finds two
    variables sharing one label, and ten others that way.
  - A folder holding a define.xml and no datasets was refused. It is now
    checked with the rules that compare the define with what the study
    contains, such as a define saying MI has data when there is no MI.

* **USDM is checked when you ask for it.** `check_study()` and `read_study()`
  take `usdm = TRUE`. Without it, a folder holding a USDM study design
  document stops with a message saying how to check it. Most studies are
  tabular, and a few USDM rules take minutes on one file.

* **CDISC's October 2026 rules.** The bundled rules are updated to CDISC's
  current release, and this one changes answers rather than wording: 103 rules
  check something different, 138 report different columns with each finding,
  and a few change which datasets they apply to. Findings on real data will
  move. Two rules CDISC gave test data for are now graded and pass, and a
  date "not equal" comparison follows CDISC's engine when both dates are
  blank: they count as equal, not different (CORE-000370, CORE-001044).
  - A finding now names what is missing. CDISC added a set-difference
    operation, so "a required variable is missing" reports which ones
    (CORE-000334, CORE-000355) instead of listing everything the rule
    compared.
  - A terminology lookup can answer from the version the study declares, and
    be narrowed to one codelist, which is how CORE-000929 now asks its
    question. A filter the bundled terminology cannot answer is refused
    rather than answered from the whole package.

* **A stray space in a CSV header is no longer part of the variable's name.**
  CDISC's own example data writes `DOMAIN ` and ` MHDY`. Untrimmed, the
  declared variable was invisible: a rule asking whether it exists reported a
  violation that CDISC's engine does not, and where `DOMAIN` itself went
  missing every dataset in the folder was classed wrongly, which silently
  changed which rules ran against it. Values keep their own whitespace.

* **Reports and exports.**
  - The report's headline and per-dataset counts say "or more" when a rule
    matched more records than `max_records` kept. They read as totals.
  - A grouped rule reporting several groups on one record was listed as
    truncated when nothing had been cut.
  - CSV exports no longer let a data value run as a spreadsheet formula, and
    are written so Excel shows non-English text correctly.
  - A value the rule requires, left blank, is "missing required", not "often
    legitimate".
  - `filter_findings(variable =)` finds a variable reported as missing. It also finds CORE 1.0's
    findings, which name the variable in a `variable_name` column.
  - A blank required value in CORE 1.0's output is "missing required", not
    "wrong value" (CORE-000356).
  - Rules over the variable metadata no longer count variables as records,
    and study-level findings are described as about the study.
  - `summary()` no longer says "across 0 records" for findings about a
    dataset or the study as a whole.
  - Saving to a CSV path used before removes a `_truncated.csv` left from the
    earlier run, which described caps that no longer applied.
  - Saving a value longer than Excel's 32,767-character cell limit stops
    with a message suggesting CSV, rather than an error from the Excel
    writer.
  - `print()` refuses a negative or missing `n` or `rows`.
  - The progress bar in an interactive session redraws one line, where it
    printed a new line for every rule.
  - The report's list of checks that could not run says how to switch on the
    terminology checks (`ct_package`, or TS), names the licensed dictionaries
    it cannot read, and says where a define.xml goes.
  - It suggests saving to Excel only when the writexl package is installed.
  - `list_rules(id = )` takes any case, and the older ids a report prints
    after "also" (CG0665, FB0801).
  - A DOMAIN column is found whatever the case of its name.
  - A folder holding datasets in more than one format gives one warning, not
    one per dataset.
  - A computed set holding one value is shown as a list, `['ARMCD']`, as the
    engines show it.
  - The negated prefix and suffix pattern checks no longer report a blank,
    as the plain pattern check does not.

* **Faster.** CDISC's pilot submission, checked with CORE 1.0's rules, takes
  about 27 seconds, where the first build running those rules took 288. A
  study ten times its size, about three million records, takes 184 seconds
  and 5 GB at most. USDM study documents are read in half the time.
  docs/BENCHMARKS.md has the measurements.

* **Two guides.** `vignette("coreval")` is now a short getting-started page:
  four steps, then answers to the tasks and questions that come up most.
  The new `vignette("technical")` is the full reference: which files are
  read and how, which rule set runs when, what each skip reason means, and
  every part of a result.

* **Stricter testing.** The conformance harness no longer counts a rule as
  passing when the only cases it could grade were the ones expecting nothing,
  and split fixtures are graded. See docs/COVERAGE.md for the current counts
  and every rule that moved.

* **CDISC's engine 1.0.0.** SEND, TIG and USDM follow CDISC's rules of 30 October
  2026 and its engine of 3 November, which took on much of what CORE 1.0 does.
  - `is_inconsistent_across_dataset` flags a whole group, not its minority, and
    honours `where_populated` and `where_populated_columns`.
  - `is_not_unique_relationship` finds nothing against a missing column, and a blank
    within a list of columns is a value of its own.
  - `type_insensitive: numeric` compares as numbers. It was read as "no" when the
    rules were bundled, for both rule sets.
  - `referenced_domain_variable_names` joins the variables of a split domain.
  - `domain_is_custom` asks about the associated domain of an AP dataset, and about
    SUPPQUAL for a SUPP dataset.
  - A child joined on plain keys keeps its own columns, so CORE-000916 reports a bad
    reference from RELREC to CO.
  - The sort check's `strict_incremental_ordering` treats any blank as null.
  - Terminology adds the packages of 25 September 2026.

* **A `.json` copy of an `.xpt` is no longer parsed.** Only the name it declares
  is read, so a package holding both formats reads as fast as the `.xpt` files
  alone. A copy damaged past its header used to stop the run, and is now set aside
  and named in the warning like any other.

* **An unreadable study start date no longer counts as an old MedDRA version.**
  CORE-002041 reported a blank, partial or mistyped SSTDTC as "not the latest
  version". It now shows as a check that could not run, naming the value, which is
  what CORE 1.0's engine does.

* **Findings of a pre-release audit, each reproduced before it was fixed.**
  - A rule that reports only identifiers is about those identifiers. A duplicate
    USUBJID, a subject not in DM and an over-long variable were filed as "missing
    optional", printed as often legitimate, and left out of a filter on wrong values.
  - An all-skipped run printed "Nothing to fix". It now says that no check ran.
  - 200000 was reported as `2e+05`, and a sequence of 100000 as `1e+05`.
  - `standard =` naming the study's own standard dropped the version it declares,
    so rules of every version ran.
  - `domain_is_custom` read one list for every version and standard. It reads the
    study's own guide, as both engines do: GF is custom in SDTMIG 3.2.
  - The strict sort check passed a sequence of 1.5 or `abc`, and sorted numbers as
    text.
  - CORE-000386 reported an overlap for a date with a missing month.
  - CORE-002062 counted all of a dataset's variables as one record of one subject,
    and the Excel Details column showed one variable's numbers without its name.
  - An `.xpt` of 2 GB or more could not be read.
  - `check_dataset()` on a TS now reads the terminology it names, and no longer
    blames TS when none was given.
  - A saved file names the version and terminology used, and no longer says it is
    the whole result when records were capped.
  - A text column compared with a numeric one follows each engine: 1.0 stops, and
    in CDISC's engine text never equals a number without `type_insensitive`.
  - 1.0's SUPP merge links on DOMAIN and RDOMAIN, compares text keys as numbers where
    both are, and no longer adds APID, POOLID or SPDEVID to the keys.
  - A 1.0 rule whose left-joined dataset is absent is skipped.
  - A missing target no longer skips CDISC's `is_unique_relationship`,
    `is_not_unique_relationship` or `is_inconsistent_across_dataset`.
  - A dataset that should exist is "missing required", whatever the rule reports.
  - `filter_findings(variable = )` finds lower-case names, the Rules sheet lists where
    a rule found something, the Records sheet numbers rows that read the same, and a
    capped rule about variables counts variables.
  - A `.json` file that is no dataset is named and left out, rather than stopping the
    read, and a data frame with no columns is refused.
  - A Domain Presence rule is asked of each dataset until one answers, as 1.0
    asks every dataset. CORE-000297, CORE-000777 and CORE-000677 read the dataset
    in hand, and a study whose first dataset lacked MIDS, RELMIDS or POOLID could
    never report them.
  - CORE-000783 looked its parent's variables up with the SUPP dataset's own
    class and lost AESEV; in a study check it never reported. 1.0 names the
    parent from the file, SUPPAE's is AE.
  - A 1.0 condition expands `--` from the file name, as 1.0 does. From DOMAIN, a
    SUPP-- or RELREC dataset with DM's columns from its merge read `--DY` as DMDY
    (CORE-000354, CORE-000529, CORE-000853).
  - CORE-000852 ordered a custom domain by the variable table, which has no class,
    and reported every custom dataset.
  - A 1.0 rule comparing a number with `distinct` of an absent dataset is skipped,
    as 1.0's engine stops: every VISITNUM was reported against a missing TV
    (CORE-000039, CORE-000140, CORE-000270, CORE-000842, CORE-000168).
  - CORE-000550 and CORE-001079 found nothing on SUPP-- datasets, which now take
    the Model's SUPPQUAL, and a dataset of no known class is skipped.
  - CORE-000370 reported a subject only when some other subject had a record.
  - `ct_package` of another family is refused, `list_ct_packages("sdtmct")` works,
    and an unknown family is an error.
  - An unreadable define.xml is reported as one: it was filed as "Missing Define-XML
    document" (CORE-002084) and every define rule said "no define.xml found".
  - `write_findings()` refuses what is not a result. An empty or broken `.json`
    dataset stops the read again; only valid JSON with no dataset keys is left out.
  - "must not be present" findings are wrong values and "must be present" ones
    missing required. An all-missing data frame column no longer stops CORE-000362.

# coreval, CDISC's engine and Verisian's engine compared

Three programs can run the CDISC Open Rules today. This page sets them side by
side: what each one is, where they give different answers, and where each one
is ahead. Each difference links to the document with the evidence.

| | CDISC's engine | Verisian's engine (CORE 1.0) | coreval |
|---|---|---|---|
| Repository | `cdisc-org/cdisc-rules-engine` | `verisianHQ/cdisc-rules-engine` | `hrach-gevorgyan/coreval` |
| Version compared | 0.17.1 for speed and rules; coreval follows 1.0.0 | 1.0.0 | development version after 0.3.0 |
| Language | Python, pandas and dask | Python, with a PostgreSQL database it starts itself | R, `data.table` |
| Standards | SENDIG, TIG, USDM (SDTMIG before CORE 1.0) | SDTMIG 3.2 to 3.4, FDA Business Rules | all of these |
| Rules from | `cdisc-org/cdisc-open-rules` | `verisianHQ/core-contributor` | both, pinned at a commit |
| Status | CDISC's reference engine | the reference engine for CORE 1.0's rules | independent, not validated, not certified |

Since CORE 1.0 (3 November 2026) the two engines are not rivals. They split
the work: Verisian's engine runs the SDTM rules, and CDISC's runs the rest.
coreval runs both rule sets, and for each one it follows the engine that rule
set was written for. The SDTM comparisons below are therefore against
Verisian's engine, and the SEND, TIG and USDM ones against CDISC's.

## Where the answers differ

### On a real study

CDISC's pilot submission (22 datasets, 294,677 records) was checked by
coreval and by Verisian's engine with the same settings, and every finding was
compared rule by rule. Of the 507 rules the engine reported on, 382 gave the
same answer from both tools and 114 were ones the engine considered not
applicable. That left 11 that differ, and every one of the 11 has a traced
cause. None of them is coreval missing a problem the engine finds.
[REAL-STUDY.md](REAL-STUDY.md) has the full account; in short:

| Kind of difference | Rules | Who is right |
|---|---|---|
| The engine stops at 50,000 findings per dataset; coreval keeps them all | CORE-000206, 000701, 000867 | both find the same problems |
| The same finding, numbered differently | CORE-002061, 002062, 002084 | both |
| The engine compares numbers from transport files with their conversion noise, so `8.55` and `8.549999999999999` differ | CORE-000542, 000168, 000270 | coreval |
| The engine looks up the Trial Design class under a name its own tables do not use, and on one rule crashes | CORE-002056, 000550 | coreval |

### On the rules' own examples

Both rule sets ship small worked examples with the records a correct
implementation should flag. coreval is run against every one of them.
[COVERAGE.md](COVERAGE.md) lists the current counts and every rule that does
not match, with the reason. The disagreements fall into a few groups:

- **Record numbering.** Verisian's engine numbers a record after its own joins
  and sorting, and its answer sheets carry that number. coreval reports the
  row in the file.
- **Answer sheets that are out of date.** Some of CDISC's sheets were written
  for an older version of the rule or the engine. Where CDISC's engine itself
  disagrees with its sheet, coreval follows the engine.
- **Defects in the engines.** At commit `8740d201`, CDISC's engine errored on
  the examples shipped with some of its rules (CORE-000929, CORE-001081), and
  one of its operators failed on blank values (CORE-001080, fixed since). These are listed in
  [REFERENCE-BEHAVIOUR.md](REFERENCE-BEHAVIOUR.md).

### Behaviour that differs on purpose

The two engines disagree with each other on some basic questions, and coreval
answers each rule the way its own engine would:

| Question | CDISC's engine | Verisian's engine |
|---|---|---|
| A check reads a column the dataset does not have | the rule errors and is skipped | the condition is false and the rule runs |
| Where a pattern must match | from the start of the value | anywhere in the value |
| The wildcard ending a filter value | `&` | `%` |

coreval adds one rule of its own: when you check a single dataset, a rule that
needs another dataset is skipped and says which one, rather than treating the
missing dataset as empty. The engines always treat the files they are given
as the whole study.

### Where the engines disagree with themselves

CDISC's engine reads a blank text value as missing from CSV or Dataset-JSON
and as an empty string from a transport file, and a few of its operators
answer the two differently, so one study can get different findings as CSV
and as XPT. coreval answers as the engine does for CSV, the form of every
rule's worked example. [REFERENCE-BEHAVIOUR.md](REFERENCE-BEHAVIOUR.md) lists
the operators, and the CORE 1.0 behaviours coreval does not follow on
purpose.

## Where each one is ahead

### The engines

- **Dictionaries.** Both engines take MedDRA, WHODrug, LOINC, SNOMED CT, UNII
  and MED-RT when you supply them. coreval cannot read them and skips those
  rules.
- **They are the reference.** When coreval and an engine disagree and nothing
  else settles it, the engine is right by definition.
- **Excel input.** CDISC's engine also reads Excel workbooks. Verisian's reads
  XPT and SAS datasets by default. coreval reads XPT, SAS, Dataset-JSON, CSV
  and USDM.
- **Define-XML schema validation**, in both engines. coreval reads the
  define but does not validate it against its schema.
- **Newest rules.** CDISC's engine can download today's rules from the CDISC
  Library with an API key. coreval's rules are fixed when the package is built.
- **Several processes.** Both engines run 10 worker processes by default.
  coreval uses one.

### coreval

- **Inside R.** It checks a data frame you have open, while you write the code
  that builds it. The engines check a folder of files from the command line.
- **Speed.** On the pilot study coreval took 33 seconds and Verisian's engine
  181 seconds, each for the whole command, on the same machine. On a 511,000-row
  test study, before CORE 1.0, CDISC's engine took 1,689 seconds with its ten
  worker processes and coreval 77 seconds in one. [BENCHMARKS.md](BENCHMARKS.md) has the method and the
  caveats; one study shape on one machine is not a general claim.
- **Memory.** On that 511,000-row study, before CORE 1.0: 833 MB against
  about 5 GB. With the CORE 1.0 rules, CDISC's pilot study peaks at about
  810 MB.
- **Install.** Two R packages and under 2 MB of bundled data. Each engine needs
  26 Python packages, and CDISC's needs a metadata cache of about 480 MB as well.
- **Offline.** No API key, no download, no cache to fill. Everything is
  bundled, including every Controlled Terminology release.
- **It says what it could not check.** Every skipped rule comes back with a
  reason in plain words, next to the findings. An empty report never hides
  rules that did not run.
- **True counts.** It keeps 1,000 records per rule by default, all of them
  with `max_records = Inf`, and always reports how many there really were.
  Verisian's engine stops at 50,000 findings per dataset.
- **Numbers read cleanly.** Values from transport files are rounded to 15
  significant digits, so conversion noise is not reported as a mismatch.
- **Both rule sets in one tool**, chosen for you by the standard.
- **Built for review.** Problems are sorted so definite errors come first, and
  the Excel export has `Status` and `Notes` columns for tracking.

### Level

All three read Define-XML 2.0 and 2.1, split datasets and Associated Persons
domains, report each finding against its dataset, record, variable and value,
and write CSV and Excel.

## Choosing

Use **coreval** while building datasets, to find problems early and often,
in R.

Use **the engines** before submission: Verisian's for SDTM and CDISC's for
SEND, TIG and USDM. They are the reference, and they check the dictionaries.

Use your organisation's **qualified tool** for the submission itself. None of
these three is validated software.

## Versions

The comparisons on this page were made with:

| | |
|---|---|
| CDISC's engine | 0.17.1, commit `8740d201` for the speed and rule comparisons; coreval's behaviour follows 1.0.0 (`data-raw/UPSTREAM_SHA_ENGINE`) |
| Verisian's engine | 1.0.0, commit `4a734105540a83f1df80d061df5049bd4b6bda4d` |
| core-contributor rules | `a3b4d0b08e45f44bcd1aafe16687aa76fe9680e3` |
| coreval | commit `e987c78` for the pilot study |

All three projects move. Each linked document says how to repeat its
measurement.

# coreval vs CDISC's CORE engine: measured

Everything here was produced by installing `cdisc-org/cdisc-rules-engine` at the
commit `cdisc-open-rules` pinned at the time (`8740d201`, engine version 0.17.1) and running
it against the same data as coreval. Nothing is estimated.

The engine was installed into a throwaway virtualenv. coreval itself still
has no Python at build or run time; the scripts under `data-raw/` are
maintainer tooling and never ship.

## Rule coverage

| | count |
|---|---|
| Rules in the engine's bundled `rules.pkl` | 981 |
| of those, USDM (study-definition JSON, not tabular datasets) | 257 |
| tabular rules (SDTM/SEND/TIG) | 724 |
| Rules coreval bundled from cdisc-open-rules when this was measured | 1,054 |
| **Overlap** | **980** |
| Tabular engine rules coreval lacks | **1** (`CORE-000845`) |
| coreval rules absent from the engine's cache | 74 |

`CORE-000845` is not a coreval omission: it is `Published` in the engine's
cache but has no folder in `cdisc-open-rules` at the pinned commit at all. The
engine's cache came from the CDISC Library API, coreval extracts from the public
rules repository, and the two disagree. The 74 the other way are draft and
unpublished rules the repo ships and the cache does not.

This table compares CDISC's engine with CDISC's rule set, before CORE 1.0
moved the SDTM rules to Verisian's repository. The SDTM rules now come from
there, and are compared with CORE 1.0's own engine in [REAL-STUDY.md](REAL-STUDY.md).

The comparison above is for tabular data. USDM study designs are read too, and
their rules are compared separately.

## Performance

### How these numbers were obtained

Every timing below is WALL CLOCK measured from outside the process by a
`psutil` wrapper (`data-raw/benchmark/benchmark.py`), which also samples RSS
across the whole process tree every 0.15-0.2s for the peak. Numbers taken from
inside R with `system.time()` are marked as such and are LOWER than the
external ones, because they exclude R start-up and package load - about 35s of
the 511k figure. Prefer the external numbers.

The engine additionally self-reports `Total_Runtime` in its JSON output; where
that exists it is quoted alongside, and it agrees with the external
measurement to within about 1%.

Machine: 20 logical cores, Windows 11. coreval runs in one process. The engine
parallelises by default (10 worker processes, `--pool-size`), and 13-15
processes were seen running.

### The test studies

Built from `Published/CORE-000042/negative/01`, a CDISCPILOT-derived fixture
(AE 1,616 rows x 27 vars, VS 1,776 x 20, DM 100 x 22, SUPPAE 1,616 x 10, plus
three trial-design datasets). Scaled by REPLICATING SUBJECTS with fresh
`USUBJID` values - not by duplicating rows - so `--SEQ` stays unique per
subject and neither engine sees a manufactured duplicate-key violation.

| label | subjects | data rows | on disk |
|---|---|---|---|
| s1 | 100 | 5,115 | ~1 MB |
| s10 | 1,000 | 51,105 | ~9 MB |
| s100 | 10,000 | 511,117 | 93 MB CSV / 126 MB XPT |

Generator: `data-raw/benchmark/make_study.py`. To reproduce any number here:

```bash
python data-raw/benchmark/make_study.py bench-studies
python data-raw/benchmark/benchmark.py bench-studies s10 s100     --engine ../cdisc-rules-engine
```

### Measured

Measured before CORE 1.0, with CDISC's SDTM rules, at coreval 0.2.x. The
CORE 1.0 rules ask more of an SDTM study; the pilot study below has current
numbers.

| study | coreval | peak | CORE engine | peak |
|---|---|---|---|---|
| s1 (5,115 rows) | 4.9s* | - | 31.8s | 2,648 MB |
| s10 (51,105 rows) | 11.8s | 276 MB | 86.1s | 4,053 MB |
| s100 (511,117 rows) | **77.4s** | 833 MB | **1,689s** (self-reported 1,671.6s) | ~5,000 MB |

`*` s1 coreval is `system.time()` only; the rest are external.

At s100 that is **21.8x**, on one core against the engine's ten workers, in about a sixth of
the memory. Finding counts are comparable, so neither tool is skipping work:
coreval 767,917 findings uncapped (`max_records = Inf`), the engine 728,033
issues with no limit set.

coreval's own `max_records = 1000` default changes nothing about the time
(113.5s capped vs 109.7s uncapped, before the optimisations below) -
truncation happens after evaluation, not instead of it.

### Against coreval 0.1.0, the released version

Measured by checking out the `v0.1.0` tag into a worktree and running the
IDENTICAL call on the identical data - `check_study(dir)` with no
standard/version filter, because 0.1.0 does not accept those arguments. Same
harness, same machine.

| rows | coreval 0.1.0 | current | gain |
|---|---|---|---|
| 5,115 | 9.5s / 284 MB | 2.6s / 247 MB | 3.7x |
| 51,105 | 63.9s / 775 MB | 6.5s / 282 MB | 9.8x |
| 511,117 | **829.4s / 5,583 MB** | **40.0s / 1,016 MB** | **20.7x, 5.5x less memory** |

Findings are identical at every scale (5,132 / 9,167 / 18,817), so none of the
speed came from doing less work. The gap widens with size because the old
child-dataset join was superlinear.

Worth recording: coreval 0.1.0 at 511k rows (829s) was already faster than the
CORE engine on the same study (1,404s on XPT). The engine was never the thing
to beat on speed.

### The engine's invocation, in full

    python core.py validate -d <study> -dep <study>/.env -s SDTMIG -v 3-4 \
      -of JSON -o <out> -p disabled -l disabled

Run from a source checkout of the engine at commit `8740d201` (the commit then
`cdisc-open-rules` pins), engine version 0.17.1, in a venv with its 26
dependencies. No `-ct` and no external dictionaries, which is the
configuration coreval can match; with CT the engine would find more than
coreval can.

**Caveats that are still open.** These numbers come from ONE study shape on
ONE machine, run from source rather than CDISC's packaged binary. The s100 run
was given CSV input with `_datasets.csv` and `_variables.csv`; the same study
as XPT took the engine 1,404 s (above). Do not quote the 21.8x as a general claim about the
two tools.

### An engine limitation worth recording

The s100 run logged, three times, a failure to cache an operation result for
key `operations/CORE-000201/$dm_usubjid/DM/distinct/AE/USUBJID` with the
message "value too large. Continuing with operation result."

`InMemoryCacheService.add()` guards with `get_data_size(data) > self.max_size`
but the `LRUCache` behind it measures with a DIFFERENT function
(`getsizeof=cust_asizeof`, pympler), so a value can pass the guard and then be
rejected by the cache. The operation is recomputed instead of reused. With
10,000 subjects the distinct-`USUBJID` list is what tripped it. It is a real
scaling wrinkle in the engine, though with only three occurrences it does not
by itself explain 28 minutes.

## Where coreval's time and memory actually went

Allocation profiling (`Rprof(memory.profiling = TRUE)`) on s10, whose data is
about 15 MB:

| | allocated, before | after |
|---|---|---|
| total | 2,890 MB | 2,020 MB |
| `evaluate_check` / `evaluate_condition` | 863 MB | 734 MB |
| `prepare_dataset_for_rule` | 805 MB | 693 MB |
| `rules_for_domain` to `build_rules_table` | **600 MB** | cached away |
| date parsing (`detect_precision`, ...) | ~360 MB | ~360 MB |

Two fixes came out of this and are in the package:

1. **`apply_child_match` was a row-by-row join.** For every child row it
   rescanned the whole parent with `as.character()` comparisons, built a
   one-row `data.table`, `cbind()`ed it, then `rbindlist()`ed n one-row
   tables. Profiling put **90% of `check_study()`'s entire runtime** in this
   one function; actual rule evaluation was 3%. Now one keyed join per
   distinct `(RDOMAIN, IDVAR, blank-IDVARVAL)` group.

   | the merge alone | old | new |
   |---|---|---|
   | 1,616 child x 1,616 parent | 3.11s | 0.02s |
   | 16,160 x 16,160 | 60.38s | 0.07s |

2. **`build_rules_table()` was rebuilt per domain.** A pure function of the
   bundled rules, called once per domain, building one one-row `data.table`
   per rule
   objects each time. Now cached, and callers get a copy so the cache cannot
   be corrupted.

### Churn buys speed, not headroom

Worth stating plainly because the intuition is wrong. Cutting allocation by
30% cut wall clock by 32% but peak memory by only 10% (926 MB to 833 MB at
s100). Peak is set by the largest LIVE object at one moment; collecting
garbage sooner does not shrink it.

So churn work makes coreval faster. It does NOT make bigger studies fit.

## Scale: what a real study looks like

The test studies are small. Two published anchors:

* **FDA** requires datasets larger than **5 GB** be split into pieces no
  larger than 5 GB (Study Data Technical Conformance Guide). So single SDTM
  datasets legitimately reach that size.
* **Pinnacle 21 Community** documents a 1 GB default heap and states the
  maximum single dataset at that heap is "on average around two million
  records", processing one dataset at a time, all in memory with no database
  or temp files.

Converting 5 GB into rows using the real XPT files generated here:

| shape | vars | bytes/row | rows at 5 GB |
|---|---|---|---|
| AE-like | 27 | 476 | 10.5M |
| DM-like | 22 | 138 | 36.1M |
| VS-like | 20 | 163 | 30.7M |
| SUPPQUAL | 10 | 114 | 43.9M |

A large cardiovascular or vaccine trial runs 15,000-45,000 subjects. LB at
30-60 analytes across 10-25 visits is 300-1,500 rows per subject, so 6-30M
rows; questionnaire-heavy studies can exceed that in QS alone. Realistic
large single domain: **1-10M rows**. Realistic large submission:
**10-50M rows**.

s100 is 511k rows, so real large studies are **20-100x** bigger than anything
measured here.

### coreval's memory ceiling

Staged measurement at s100 (511k rows):

| stage | peak | bytes/row |
|---|---|---|
| R + package load (fixed) | 150 MB | - |
| + `read_study`, all 7 domains resident | 298 MB | **290** |
| + full `check_study` | 833 MB | 1,636 |

The resident data is efficient - 290 bytes/row, better than the ~500
bytes/record implied by P21's documented limit, and coreval holds every domain
at once where P21 holds one. The cost is in evaluation.

Extrapolating the 833 MB linearly:

| study | est. peak |
|---|---|
| 2M rows (P21 stated limit) | ~3.3 GB |
| 10M rows | ~16 GB |
| 50M rows | ~82 GB |

So coreval runs out of machine somewhere around 5-10M rows. Raising that
ceiling needs the LIVE working set down - loading only the columns in-scope
rules reference, and holding one domain plus its join partners rather than the
whole study - not more churn work.

## Scale: CDISC's pilot study, up to 5.9 million rows

The test studies above are built from a small fixture. This one starts from a
complete real submission, CDISCPILOT01 (22 datasets, 294,677 rows; see
[REAL-STUDY.md](REAL-STUDY.md) for where to get it), and repeats every
subject-keyed dataset k times under new `USUBJID`s. Trial design datasets stay
single. At k = 20 QS alone is 2.4 million rows.

```bash
Rscript tests/conformance/pilot_scale.R <folder of pilot .xpt files> <k>
```

Time is `system.time()` around `check_study()` only. Peak is the operating
system's peak working set for the whole R process, study included. Same
machine as above, one process.

Since CORE 1.0 an SDTM study is checked with 1.0's rules, which ask more, and
several of the new ones look at every value of a dataset rather than every
record. Measured with `standard = "SDTMIG"` at the commit that made `standard`
required, 3,199 checks running at every scale:

| k | rows | time | peak | findings |
|---|---|---|---|---|
| 1 | 294,677 | 27 s | 807 MB | 48,276 |
| 10 | 2,945,870 | 184 s | 4,998 MB | 82,283 |

Every measurement below ran with no standard, so every standard's rules ran,
SEND and TIG ones included. At commit `2f963fe` that was 3,809 checks: 27 s,
720 MB and 72,546 findings at k = 1, 190 s, 4,363 MB and 122,170 findings at
k = 10. The 610 SEND and TIG checks cost almost no time; the peak at k = 10 is
higher now, by 635 MB, and has not been traced.

Commit `e987c78`, measured again on the same machine with the machine
otherwise idle, took 26 s at k = 1 and 189 s and 4,077 MB at k = 10, with the
same findings: the later commits did not make it faster. 4,081 checks ran
there. The 272 that no longer run are CDISC rules reading a column the dataset
lacks, which CDISC's engine skips too (docs/REFERENCE-BEHAVIOUR.md, item 13);
they reported nothing on this study. An earlier record of 62 s and 393 s for
that commit was taken while other work was running on the machine, and is
withdrawn. k = 20 (5,891,640 rows) took 794 s with a peak of 8,024 MB at
`e987c78`, measured under the same load, and has not been measured since.

With CDISC's rules, before CORE 1.0, the same study took 32 s, 226 s and
451 s (table below). The first build running 1.0's rules took 288 s at k = 1
(commit `71e04ea`), and 1,061 s at k = 10 with the first fixes below already
in. What the profile showed there:

- **Four checks worked row by row.** Durations, 1.0's date test, the substring
  test and the IG domain lookup each ran once per row, though a column repeats
  few values. Each now runs once per distinct value. Together they were 210 of
  259 profiled seconds at k = 1.
- **The RELREC join grew with the square of the study.** For each RELREC row
  it re-read the whole key column of the dataset being joined, so CORE-000766
  took 25 s at k = 4 and 2.4 s at k = 1. Keys are now indexed once per column:
  2.8 s at k = 4.
- **The one-row-per-value table was rebuilt for every rule.** It is now built
  once per dataset and handed to each rule as a new table over the same
  columns, which copies nothing; only the current dataset's is kept. At k = 10
  that took 599 s to 438 s and the peak from 4.4 GB to 4.1 GB. Keeping a copy
  per rule had been tried before and turned down, because the copies raised
  the peak by 1.5 GB.

### Against coreval 0.3.0 on the pilot study

Measured 2026-11-06, on `standard = "SDTMIG"`, in three alternating runs on one
machine. Both versions were loaded from source, so only the difference between them
means anything.

| | 0.3.0 | now |
|---|---|---|
| reading | 2 s | 2 s |
| checking | 19 s | 27 s |
| **total** | **21 s** | **29 s** |
| checks run | 2,499 | 3,200 |
| finding rows | 12,158 | 46,984 |
| problems | 52 | 142 |
| peak memory while checking | 378 MB | 653 MB |

CDISC's folder holds every dataset twice, as `.xpt` and as Dataset-JSON, and reading
it costs about 0.2 s more than the `.xpt` files alone. coreval reads what each JSON
file declares ahead of its rows and sets aside a copy that loses to a `.xpt`. Parsing
all 22 took 5 s. It cannot go by file name: `ae.json` might declare a dataset with
no `.xpt`, and leaving it out would drop that dataset without a word.

Checking is 8 s slower. Rules added since 0.3.0 account for 5 s of it, timed
rule by rule. The other 3 s were not split further; four times as many finding rows
are built in it. Time per check barely moved, 7.6 ms against 8.4 ms. The extra time buys more checks and more problems
found, not slower ones.

### With CDISC's rules, before CORE 1.0

All 4,001 checks run at every scale.

| k | rows | before | after | findings |
|---|---|---|---|---|
| 1 | 294,677 | 78 s, 644 MB | 32 s, 567 MB | 40,355 |
| 10 | 2,945,870 | 452 s, 3,833 MB | 226 s, 2,997 MB | 70,779 |
| 20 | 5,891,640 | 892 s, 7,054 MB | 451 s, 5,412 MB | 88,739 |

"Before" is commit `50c0649`. At k = 3 the two versions return identical
findings and identical skip lists, compared with `identical()`.

What the per-rule profile showed, and what changed:

- **Date work was done per row.** The three study-day rules (CORE-000436,
  CORE-000529, CDISC.SENDIG.71) took 40% of the whole check at k = 10, each
  spending most of its time building a date-time for every row. A column holds
  far fewer distinct dates than rows, so date parsing, validation and
  precision now run once per distinct value and are indexed back out. Each of
  those rules went from about 18 s to about 3 s on a 600,000-row LB.
- **The Match Datasets join copied the table six times.** The dataset, its
  blank-key and valid-key halves, the merge, the bind and the reorder were all
  alive at once, so joining DM onto a 186 MB QS peaked at 1.7 GB. The join now
  works out the matching row numbers first and builds the result once, reusing
  the original columns when no row gains a partner: 0.3 GB.
- **Two per-row loops over IDVAR.** Looking up "the value of the column IDVAR
  names" and "which IDVARs name a real column of their RDOMAIN" called a
  closure per row. Both now work per distinct column name. CORE-000712 on
  SUPPLB went from 9.9 s to 1.7 s.

What still sets the peak is the Value Check with Variable Metadata rule type
(CORE-000867 and its kind). CDISC defines it over one row per (record,
variable) pair, so a 1.2 million-row QS with 16 columns becomes 19.5 million
rows, about 1.3 GB, before the check runs. With the CORE 1.0 rules the pilot
at k = 10 (2.9 million rows) peaks at about 5 GB, so a 10 million-row study
needs in the order of 17 GB of free memory.

## Footprint

| | engine | coreval |
|---|---|---|
| Runtime dependencies | 26 packages (dask, fastparquet, pyreadstat, redis, ...) | 2 (`data.table`, `haven`) |
| Installed size | 328 MB of packages + 463 MB metadata cache | under 2 MB of bundled data |
| Network needed to refresh rules | yes (`update-cache`, CDISC Library API key) | no - rules ship as data |

## Agreement across every non-passing rule

This section predates CORE 1.0 and grades CDISC's rule set as it stood then.
192 test cases of the 93 non-passing rules could be run by both. 50 more could
not: 48 ship no `.env`, which CDISC's own `test.py` also requires.

**Engine against its own committed answer sheets:** on the pinned commits
(`cdisc-open-rules` 1fb7b81e and `cdisc-rules-engine` 8740d201, both 2026-09-02)
the two disagree on **95 of those 192 cases**.

Read that as a versioning gap, not a verdict on the rules. The `results.csv`
files in the rules repository were generated by an earlier build of the engine,
neither repository pins the other, and the sheets are not regenerated when the
engine changes. Several of the reference-behaviour entries in
[REFERENCE-BEHAVIOUR.md](REFERENCE-BEHAVIOUR.md) are exactly this: a sheet that
predates a deliberate change to an operator. It says nothing about whether a
rule expresses the right conformance requirement.

The number is bound to those two commits and will move when either moves.
Reproduce it with `tests/conformance/compare_engine.py`, which runs the engine
over each case and writes `engine_comparison.json` beside it; both the script
and the artifact are in the repository. CDISC's own `test.py` shows the same
thing from the other direction, since it regenerates each case's `results.csv`
in place and leaves the difference in `git diff`.

Counted by rule rather than by case, across all 55 non-passing rules: the
engine can run 41 of them and disagrees with its own committed sheet on **all
41**. The remaining 14 ship no `.env`, so the engine cannot run them and
neither can `test.py`. Those are held separate rather than counted as
agreement.

**coreval against the live engine:** 156 cases match exactly. Every case that
did not was re-measured individually, and none survived as a coreval defect:

| first pass called it a difference | what it actually was |
|---|---|
| 7 cases | dataset-level findings. The engine reports one row with a blank `Record`; the first comparison dropped blank records entirely. `check_study()` collapses these correctly - verified on CORE-000031, reported as one dataset-level row, matching the engine. |
| 1 case (CORE-001078) | the harness called `evaluate_rule()`, which returns the raw per-record vector before group collapsing. `check_study()` returns AE records 4 and 7 - exactly the engine's answer. |
| 3 cases (CORE-000929, -000934, -001080) | Controlled Terminology. coreval skips them with a reason; a real gap, not a wrong answer. |
| 1 case (CORE-000272) | a real coreval defect, since fixed - see `domain_label` below. |
| 4 cases (CORE-000292, CORE-000777) | placement. The engine attributes the finding to `STUDY`, coreval to the domain. |
| 2 cases (CORE-000468) | coreval matches the **answer sheet** where the live engine does not. On negative/01 the sheet and coreval both say `TS[49]`; the engine reports nothing. |

### A caveat on this table's provenance

The per-case coreval column in the sweep has at least one entry that cannot be
reproduced: it recorded `AE[5,6]` for CORE-001078 where re-running the same
code gives `AE[4,5,6,7]`. The cause was not identified. Every divergent case
was therefore re-measured directly, one at a time, and those measurements are
what the table above reports - not the sweep's own column. The
engine-versus-sheet numbers are unaffected, since both sides of that
comparison are files read off disk.

The lesson is the one this repository keeps relearning: a harness that loops
over hundreds of cases is itself code that can be wrong, and a number it
produces is worth less than a number you can reproduce by hand.

## Agreement on the fixture study

On the three-dataset fixture study, of the 13 rules the engine reports issues
for:

* **11 coreval also reports**, once deprecated rules are included
  (`include_deprecated = TRUE` - coreval hides them by default because a
  deprecated rule has a published replacement, so running both double-reports).
* **2 coreval does not**: CORE-000929 and CORE-001081. Both are rules the
  engine itself logs as `EXECUTION ERROR`, so it did not evaluate them either.
  coreval skips them with a reason.

Of the rules coreval reported and the engine ran clean: 2, and they were a real
coreval defect.

## Two coreval defects this comparison found

Neither was findable from the conformance fixtures; both needed the real engine.

**`is_incomplete_date` treated an absent column as an incomplete date.** Three
operators were plain negations of their positive counterparts, which answer
`FALSE` for a column the dataset does not have - so the negations answered
`TRUE`. CORE-000138/139 ask whether `DM.RFSTDTC` is an incomplete date while
`--STDY` is populated, so on a study with no DM every record carrying a study
day was flagged: **267 findings out of 393**. The engine runs both rules on the
same data and reports nothing, which is correct. `is_unique_set` and
`is_unique_relationship` had the same shape.

**`domain_label` returned the study's own dataset label, not the standard's.**
SENDIG calls `LB` "Laboratory" where SDTMIG calls it "Laboratory Test Results".
CORE-000272 asks whether `--CAT` equals that label and its fixture declares
SENDIG, so coreval compared against the wrong string and reported nothing.
Per-standard dataset labels are now bundled.

Both moved the conformance sweep by zero in one direction or one rule in the
other - which is the point: the fixtures do not exercise these shapes.

## Pros and cons

### Where the engine is ahead

* **External dictionaries.** WHODrug, MedDRA, LOINC, MEDRT, UNII, SNOMED.
  coreval has none.
* **Input formats.** The engine also reads XLSX. coreval reads XPT, sas7bdat,
  CSV, Dataset-JSON, NDJSON and USDM documents.
* **It is the reference.** Where they disagree and no third source settles it,
  the engine is by definition right.
* **XML schema validation** of Define-XML (`-vx`), which coreval does not do.
* **Rule currency.** `update-cache` pulls today's rules from the CDISC Library;
  coreval's are pinned at build time.
* **Parallelism.** It runs 10 worker processes by default. coreval is single-process.

### Where coreval is ahead

* **Speed**: 21.8x on the 511k-row study, single-process against 10 workers.
* **Memory**: 833 MB against ~5 GB on that study.
* **Install**: two R packages against 26 Python ones; under 2 MB against ~790 MB.
* **Offline by construction.** No API key, no cache to populate.
* **It says what it could not check.** Every skipped rule comes back with a
  reason, in the result object, beside the findings.
* **Runs on a data frame you already have open**, not only a folder of files.
* **Deprecated rules off by default**, so one defect is not reported three
  times by a rule, its replacement and its predecessor.
* **Tracking columns** (`Status`, `Notes`) written into the export.

### Where they are level

Define-XML 2.0/2.1 parsing, split datasets, Associated Persons domains,
per-record findings with dataset/record/variable/value, CSV and Excel output.

## What these numbers do not cover

* One study shape, one machine, one invocation, engine run from source rather
  than CDISC's packaged binary.
* The engine ran with no CT package and no dictionaries, the configuration
  coreval can match. With `-ct` it finds more than coreval can.
* Engine version 0.17.1 at commit `8740d201`. Both projects move.
* The scale tested (511k rows) is 20-100x smaller than a real large submission.

## Corrections to earlier versions of this document

Recorded because they were quoted before they were checked:

* **"13x faster than the engine"** - wrong. It came from a 3-dataset fixture
  where Python start-up dominated. At s10 the engine was FASTER than coreval
  (86.1s vs 121.7s) before the join fix.
* **"the engine cannot finish 511k rows in 35 minutes"** - wrong. It was
  killed prematurely. It finishes in 28.1 minutes and says so itself.
* **"coreval did 511k rows in about 21 minutes before the fix"** - withdrawn.
  Never measured; inferred from process start timestamps after the harness was
  killed. The standalone old-join measurement at that scale exceeded 40
  minutes for a single merge, which contradicts it - the earlier run had
  probably failed rather than finished.
* **"removing churn takes peak from 836 MB to about 450 MB"** - refuted by
  measurement: 833 MB.
* **The 73.3s figure for s100** was `system.time()` around `check_study` only.
  Externally it was 113.5s at that time, 77.4s after both fixes.

# Coverage: which rules pass, and why the rest do not

coreval bundles 1,054 CDISC rules and runs each against the example data CDISC
publishes with it. This file explains the ones that do not come back clean.

`tests/conformance/run_conformance.R` gives the live answer, rule by rule, and
takes about three minutes on eight cores. Counts in prose go stale; that run
does not.

At the last full sweep: **956 pass, 56 disagree, 42 cannot be measured.**

A rule counts as passing only if a case that expects findings was graded. A rule
whose clean cases pass while the case built to catch something could not be run
is reported as not measurable, with the reason: a green rule has to have been
shown to find what it is for.

## USDM

257 of the bundled rules are USDM, and all but 4 of them pass. They arrived
together with the reader that makes them runnable, so they have no history of
disagreement here: 157 are ordinary record checks over the study document read
as one table per entity, and 96 are JSONata expressions over the document
itself.

The 4 that do not run are JSON Schema Check rules. Which errors they report
depends on the internal error tree of one particular JSON Schema library,
including how it walks the branches of an `anyOf`; a different validator
reports a different shape, and deriving one from the other would be inventing
findings rather than checking data. They are skipped naming the rule type.

The reader itself is graded against the reference rather than against a
reading of the specification. No CDISC fixture pairs a USDM document with the
tables it should flatten to, so `tests/conformance/dump_usdm_tables.py` runs
CDISC's own service over a document to produce them and
`tests/conformance/compare_usdm_reader.R` diffs coreval's against those, cell
by cell.

## The 42 that cannot be measured

38 are fixtures with nothing to check against and 4 need a rule type coreval
does not implement.

| why | rules | |
|---|---|---|
| The fixture ships data but no answer sheet | 26 | unmeasurable |
| The test data contains no dataset the rule is scoped to | 5 | unmeasurable |
| The rule type is not implemented (JSON Schema Check) | 4 | a gap in coreval |
| The rule ships no test cases at all, only `rule.yml` | 4 | unmeasurable |
| The rule's `Check` block is empty upstream | 1 | unmeasurable |
| The fixture lacks a dataset the rule computes over (FDA.SENDIG.FB6403, PR) | 1 | unmeasurable; CDISC's engine skips it the same way |
| The case expecting findings cannot be read (CDISC.SDTMIG.CG0096 names a file `WHODD.csv.csv`) | 1 | unmeasurable |

Each of these was re-derived from the upstream tree rather than read back off
the reason string. The five scope skips were the ones worth doubting, because
every one has an answer sheet that expects findings, which is the exact shape a
silently mis-scoped rule would take. They were settled against the engine's own
class table (`standards_details.pkl`) and its own `rule_applies_to_class`:
under SENDIG 3-1, `DM` is SPECIAL PURPOSE, `VS` is FINDINGS and `TX` is TRIAL
DESIGN, while CORE-000794, CORE-000847 and CORE-000848 all require EVENTS.
`RELSUB` is RELATIONSHIP where CORE-000229 requires SPECIAL PURPOSE. The engine
filters those datasets out too, so those sheets are stale.

That audit also turned up `FDA.SENDIG.FB6507`, skipped as a scope mismatch
when its fixture ships no datasets at all, only a `define.xml`. The skip hid a
real limitation: coreval refused a folder with no datasets. A folder holding
only a define.xml is now checked with the rules that compare the define with
what the study contains, and FB6507 passes.

A rule with no published expected output cannot pass or fail. Counting these as
failures understates the package; hiding them overstates it. They are reported
as skipped, by name, with the reason, every time you run.

## The 56 that disagree

coreval flags different rows than the answer sheet says it should.

| source | rules | reaches users? |
|---|---|---|
| `deprecated_dir` | 26 | no, deprecated rules are off by default |
| `published` | 17 | **yes** |
| FDA business rules, draft | 7 | yes, marked draft |
| SENDIG draft | 5 | yes, marked draft |
| SDTMIG draft | 1 | yes, marked draft |

### Two that disagree because they are now graded at all

Both used to count as passing without ever being tested on the case that
matters.

**CORE-000732** (`--STRESC` not numeric while `--STRESN` is filled). Rules
written for Findings now also run on Findings About domains, as the reference
runs them, so the fixture's FA is checked for the first time. Its positive case
puts the text `<5` in `FASTRESN`, a column `_variables.csv` declares numeric.
The reference reads that cell as a missing number; coreval keeps text in a
numeric column as text, on purpose, because in a submission that text is itself
the problem. A transport file cannot hold text in a numeric variable, so this
difference exists only in CSV fixtures.

**FDA.SENDIG.FB6505** (the define declares LB with data, and there is no LB).
The ten define-based presence rules could not fire before. This one's positive
case ships an `lb.csv` whose `DOMAIN` column says `EX`, so by the DOMAIN value,
which is how the reference matches a define entry to a dataset too, the study
has no LB. The sheet expects nothing. The fixture contradicts its own name.

### What the reference says about the 55 that disagreed before

Settled by running CDISC's own engine (0.17.1 at commit `8740d201`) over every
case of every non-passing rule, not by reading its source and reasoning about
it. `tests/conformance/compare_engine.py` does this and writes
`engine_comparison.json`, which records what the engine reported and what the
committed sheet says, per rule per case. Both are in the repository, so the
table below can be checked rather than taken on trust.

| | rules | |
|---|---|---|
| The engine runs it, and **disagrees with its own committed sheet** | 41 | every single one |
| The engine cannot run it, but the sheet contradicts its own data | 6 | stale on signature alone |
| The engine cannot run it, and the sheet is self-consistent | 8 | **unadjudicated, listed below** |

Not one of the 41 is a case where the engine and the sheet agree and coreval is
the odd one out. That set is empty.

A fixture with no `.env` cannot be run by the engine at all, because CDISC's
own `test.py` requires one too. Fourteen of the 55 are in that state. Counting
those as agreement would be the vacuous-truth version of the silent-failure bug
this package keeps finding in itself, so they are held separate.

### The 16 published ones trace to stale answer sheets

**coreval matched the engine on all sixteen. The committed `results.csv`
differed from the engine on every one.**

| rule | coreval and the engine agree on | the sheet says |
|---|---|---|
| CORE-000387 | `{2,3}` | `{1,3}` |
| CORE-000390 | `{3,4}` | `{}` |
| CORE-000396 | `{61,62}` | `{59,60}` |
| CORE-000554 | `{}` | `{5}` |
| CORE-000570 | `{}` | `{5}` |
| CORE-000612 | `{2,12}` | `{1..12}` |
| CORE-000648 | `{6}` | `{}` |
| CORE-000652 | `{7}` | `{5,6}` |
| CORE-000670 | `{1..7}` | `{}` |
| CORE-000699 | `{2,5,7,...}` | `{1..22}` |
| CORE-000711 | `{1,3}` | `{1,2,3}` |
| CORE-000714 | `{1,3}` | `{1,3,6}` |
| CORE-000864 | flags SM | omits SM |
| CORE-000865 | `{2}` | `{2,4}` |
| CORE-000866 | `{1,3,5,6}` | `{}` |
| CORE-000884 | `{2,3,4}` | `{}` |

Two of them the engine cannot run: neither CORE-000554 (`SENDIG-DART 1.1`) nor
CORE-000652 (`SENDIG-GENETOX 1.0`) ships a `.env`, so the standard is never
declared and the run never starts. CORE-000554's sheet is stale on signature
anyway. CORE-000652 is the one published rule in the unadjudicated set.

### The 8 nobody can currently settle

For these the engine cannot run the fixture and the sheet does not contradict
its own data, so neither side can be shown wrong. They are not claimed as
stale sheets and not conceded as coreval defects. They are open.

| rule | source |
|---|---|
| CORE-000652 | published |
| FDA.SDTMIG.FB0801, FB0802, FB3211 | FDA business rules, draft |
| CDISC.SENDIG.71, 153, 318, 359 | SENDIG draft |

What would settle them is a `.env` in the fixture, which is upstream's to add.

### Why the sheets drift

Three mechanical signatures, each detectable without judgement:

1. **The sheet's stated Value contradicts its own data.** CORE-000748's sheet
   says `ARMNRS` is `NOTTRT`; the CSV beside it says `FAILure`.
2. **A negative case with an empty sheet.** A negative case is built to contain
   violations. An empty answer means the answer was never generated, usually
   because the engine crashed: CDISC.SDTMIG.CG0555's fixture ships no `.env`,
   so the engine raises `MissingDataError` and writes no rows.
3. **The sheet cites an Operations id the rule does not declare.**
   CDISC.SENDIG.190.1B's sheet reports `$owbw_ratio_null_unit`, which appears
   nowhere in the rule.

Applied mechanically to the sheets, these three signatures prove 28 of those 55
stale without any judgement.

## Two rules where coreval is right and cannot prove it

**CORE-001080.** coreval reports TS records 3 and 16; the sheet has only 3.
Both rows prefix-match `CDISC` in `TSVCDREF` and both carry a `TSVALCD` that is
not a term code in the package they cite (`C00001` and `C00002`, neither
present). By the rule's own text both are violations. The engine cannot
arbitrate: on that fixture it raises
`ValueError: The operator can't be used with non-string values` from
`prefix_equal_to`, because `TSVCDREF` is empty on 23 of the 51 rows. coreval
handles those rows. The rule is deprecated and does not run by default.

**Split datasets.** A finding in a split dataset names the file the problem is
in, with that file's own row numbers, where CDISC reports against the merged
domain. That is deliberate. A finding has to point at a file you can open and a
row you can find. The harness translates between the two numberings when it
grades, so split fixtures are graded rather than skipped.

## Reading a skip

Every skipped rule comes back with a reason in `result$skipped`. The reasons are
written to be acted on:

- *"needs DM, which was not supplied"* - run `check_study()` on the folder
  instead of `check_dataset()` on one file.
- *"needs TV, which is not in this study"* - the rule compares against a
  dataset the study does not have, so it has nothing to compare with.
- *"needs controlled terminology, and this study does not say which version it
  follows"* - the study's TS has no `TSVCDVER`; pass `ct_package`.
- *"unimplemented Operations type: X"* - coreval cannot evaluate that rule at
  all. It will never silently answer one of these.

An empty findings table means one of two things: clean data, or rules that
never ran. Those look identical if you only read the first table.

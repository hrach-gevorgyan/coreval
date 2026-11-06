# Maintaining coreval

How the package fits together, how to change it safely, and how to keep it
current. It is written for someone who has never touched this code.

## What coreval is made of

coreval reads SDTM, SEND, TIG and USDM data and checks it against CDISC's CORE
rules. There is one principle:

> **Rules are data. Operators are code.**

A rule is a record extracted from CDISC's YAML. It says which datasets it
applies to and which conditions make a record wrong. R code only supplies the
operators those conditions use, such as `empty` or `is_contained_by`. If adding
a rule would mean writing R, something is wrong. Only a new operator justifies
new code.

| Where | What |
|---|---|
| `R/read*.R`, `R/define.R`, `R/check_dataset.R` | reading `.xpt`, `.sas7bdat`, Dataset-JSON and USDM; define.xml; CSV |
| `R/rules.R`, `R/scope.R` | which rules apply to which dataset |
| `R/evaluate.R`, `R/match_datasets.R`, `R/operations.R` | preparing a dataset for a rule |
| `R/op_*.R` | the operators |
| `R/results.R` | `check_study()`, and turning violations into findings |
| `R/report.R` | the printed report and the triage levels |
| `R/export.R`, `R/workbook.R` | the CSV and Excel files |
| `inst/extdata/` | the bundled rules, terminology and metadata |
| `data-raw/` | how the bundled data is built, and the upkeep scripts |
| `tests/conformance/` | grading against the reference engines' test cases |

## Where the rules come from

Two repositories supply them, each pinned to a commit:

| Rules | Repository | Pin |
|---|---|---|
| SDTMIG and FDA Business Rules | `verisianHQ/core-contributor` | `data-raw/UPSTREAM_SHA_CORE1` |
| SENDIG, TIG, USDM | `cdisc-org/cdisc-open-rules` | `data-raw/UPSTREAM_SHA` |

Each has its engine, also pinned: Verisian's in
`data-raw/UPSTREAM_SHA_CORE1_ENGINE` and CDISC's in
`data-raw/UPSTREAM_SHA_ENGINE`. A rule in both repositories has two versions: an
SDTM study gets the first, a SEND or TIG study the second. A rule from the first
runs with that engine's behaviour where the two engines differ.

Nothing is fetched at run time. No Python, no network, no `reticulate`: rules
ship as data, built from the pinned commits.

To work on any of this, clone the repositories into `data-raw/upstream/`, which
is ignored by git.

## Updating the rules

1. `Rscript data-raw/check_upstream.R --fetch` says what moved.
2. Move the clone to the new commit and rebuild with
   `Rscript data-raw/extract_rules.R`. Re-pinning is always a deliberate act.
3. `Rscript data-raw/verify.R rules` reports rules that changed status, and
   rules that kept their status while their reported records moved.
4. Read every change. A moved rule is either a real change upstream or something
   coreval got wrong, and `docs/COVERAGE.md` records which.
5. Update `inst/COPYRIGHTS` and the `data-raw/UPSTREAM_SHA*` files it points to,
   which name the commit each bundled file came from.

`data-raw/weekly.R` does the watching and writes a report. It clears build
leftovers, touches the rules only when given `--adopt`, and never pushes.

## Changing the code

Before reversing a choice, read `docs/DECISIONS.md`. Before touching how an engine
is imitated, read `docs/REFERENCE-BEHAVIOUR.md`. Any claim about an engine is
checked against its pinned source, not remembered.

**Silent failure is this package's characteristic bug.** A rule that quietly finds
nothing cannot be told from a rule that correctly finds nothing, and the pass rate
cannot see it. So:

- A builder or operator that cannot resolve its input raises an error.
  `check_study()` turns that into a skipped rule with a reason.
- A Check name that is not a real column must not become literal text. The
  tripwire test in `test-rules.R` guards this.
- One job gets one code path. `evaluate_rule()` and `check_study()` both go through
  `run_rule_on_domain()`, because they once drifted apart.
- Wrong input is refused, not answered.
- A fix that moves the pass rate by zero is not evidence it did nothing. Work out the
  right answer by hand on real data.
- A verdict of "not our bug" needs a mechanical proof: argued verdicts have been
  wrong.
- Excluding something to make a check pass is not a pass. A rule that cannot be
  evaluated is skipped with a reason, never faked.

The other hard limits: runtime `Imports` stay `data.table` and `haven`; use
`data.table`, not `dplyr`, in the evaluation loop; load each domain once per study;
write nothing outside `tempdir()`.

## Checking a change

Run the level the change needs. Each includes the ones above it.

```bash
Rscript data-raw/verify.R docs      # prose only
Rscript data-raw/verify.R vignette  # + renders the guide
Rscript data-raw/verify.R roxygen   # + regenerates man/
Rscript data-raw/verify.R code      # + the test suite
Rscript data-raw/verify.R rules     # + both conformance sweeps and their diff
Rscript data-raw/verify.R release   # + URLs and R CMD check --as-cran
```

`rules` is the level for anything touching operators, evaluation, scoping or bundled
data. To chase one rule:

```bash
Rscript tests/conformance/run_conformance.R data-raw/upstream/core-contributor CORE-000123
```

`tests/conformance/scoreboard_core1.csv` holds the current pass counts for SDTM, and
the `scoreboard.csv` a sweep writes beside it holds CDISC's. The pass
rate is a lower bound on defects, not a readiness signal: the test cases barely
exercise split datasets or define.xml. `docs/REAL-STUDY.md` compares every finding on
CDISC's pilot study with Verisian's engine, and is re-run before a release.

A green check on Windows or macOS proves nothing about Linux, which is case-sensitive
about file names. CRAN builds there.

## Writing

Documentation is read by people deciding whether to trust this with their submission.
`Rscript data-raw/check_prose.R` flags the habits that make text read as generated: em
dashes, intensifiers and throat-clearing. Findings go in the relevant file in `docs/` as
lasting facts with evidence. A number that changes goes in a scoreboard, or says when
it was measured. Progress goes in `NEWS.md`.

## Releasing

1. Set `Version` in `DESCRIPTION` and the top heading of `NEWS.md`.
2. Update `cran-comments.md`.
3. Commit and push everything, `docs/` included. The README links to `docs/` with
   absolute URLs, because `docs/` is not in the tarball, so those files must be on
   GitHub before URLs are checked.
4. `Rscript data-raw/verify.R release` must end with 0 errors, 0 warnings and 0 notes,
   and `Rscript data-raw/check_prose.R` must be clean.
5. Re-run the pilot comparison and update `docs/REAL-STUDY.md`.
6. Check the other platforms: GitHub Actions, win-builder and R-hub.
7. Submit to CRAN. When it is accepted, tag the commit `vX.Y.Z`.

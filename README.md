# coreval

[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)

coreval is an R package that evaluates CDISC Open Rules (CORE) conformance rules against clinical trial datasets, returning findings as a tidy data frame.

**Status:** Phases 0-9 of the development plan are implemented: rule
extraction, `read_study()`, `rules_for_domain()`, the `Check`-tree evaluator
(~60 operators, including dates and grouping), the `Operations` pipeline,
`Match Datasets` joins, and `check_study()` as the main user-facing entry
point.

Not affiliated with or endorsed by CDISC. Not a CORE-certified conformance engine.

## Conformance

coreval ships 756 rules and is verified by a harness
(`tests/conformance/run_conformance.R`) that runs every one of them against
CDISC's own positive/negative reference test cases and compares which records
each rule flags. Current results:

| Slice | Pass rate |
|---|---|
| Published rules, Fully Executable, **with reference output to compare against** | **475 / 499 (95.2%)** |
| Published rules, Fully Executable, including those with no reference output | 475 / 543 (87.5%) |
| All Fully Executable rules (Published + Deprecated + FDA draft) | 583 / 722 (80.7%) |

Two denominators are reported deliberately, because the difference is not a
quality signal:

- **81 rules ship no reference output at all** — upstream provides either no
  `positive/`/`negative/` fixtures, or fixture data with no accompanying
  `results/`. These cannot pass or fail, so counting them as failures
  understates real conformance by roughly ten points.
- **Deprecated and draft rules are a lower-value pool** whose bundled fixtures
  predate current engine conventions. Several were verified to number records
  counting the CSV header row — one cites record 5 in a four-row file — so
  they are presumed stale until shown otherwise.

Of the remaining Published failures, essentially all are triaged: confirmed
stale fixtures (a fixture's own reported values contradict its own data),
rules requiring CDISC Library variable metadata that this package does not
bundle, or acknowledged open bugs in the upstream reference engine. Rules
that cannot be evaluated are reported as skipped with a reason — never as a
pass, and never as a fabricated finding.

**Treat the pass rate as a lower bound on defects, not a readiness signal.**
CDISC's reference fixtures are almost entirely unsplit datasets, so whole
classes of real-world input — a domain split across several files, an
Associated Persons dataset — aren't exercised by them at all. A real bug in
`"--"` wildcard resolution that silently disabled a third of the rule set on
split-domain studies produced *no* change in this table.

### define.xml

`read_study()` reads a CDISC Define-XML 2.0/2.1 file when one is present in
the study directory, exposing declared dataset- and variable-level metadata
so rules can compare it against what the data actually contains. This needs
the `xml2` package, which is a `Suggests`: without it, define.xml support is
simply unavailable and the affected rules report as skipped.

Not a CORE-certified engine: these numbers describe agreement with CDISC's
published reference data, not certification.

## Installation

Not on CRAN yet. Install the development version from GitHub:

```r
# install.packages("pak")
pak::pak("hrach-gevorgyan/coreval")
```

## Usage

```r
library(coreval)

# Read a study - either a directory of XPT datasets, or a CORE test-case
# data/ directory (.env + _datasets.csv + _variables.csv + one CSV per
# dataset). read_study() detects which one it's looking at.
study <- read_study("path/to/study")

# Evaluate every applicable, executable bundled rule against every domain
# in the study.
result <- check_study(study)

# A tidy findings table: one row per (Dataset, Record, Variable) violation
# (Record is blank for Dataset-sensitivity rules).
head(result$findings)

# Which rule/domain combinations couldn't be evaluated, and why - so a
# clean findings table is never mistaken for "everything passed."
head(result$skipped)
```

Lower-level building blocks are also exported for inspecting the rule set
itself:

```r
# The exact upstream cdisc-open-rules commit this rule set was built from
rules_version()

# All bundled rules, with provenance
rules <- list_rules()
head(rules)

# Only the fully-trusted, Published-status rules
subset(rules, source == "published")
```

`source` distinguishes how much a rule can be trusted — see [NOTICE.md](NOTICE.md)
for what `published`, `deprecated_dir`, and `fda_business_rules_draft` each mean.

## License

MIT for package code (see [LICENSE.md](LICENSE.md)). Rule content is sourced
from [cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
(CDISC) under its own terms — see [NOTICE.md](NOTICE.md).

## News

See [NEWS.md](NEWS.md).

# coreval

[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)

coreval is an R package that evaluates CDISC Open Rules (CORE) conformance rules against clinical trial datasets, returning findings as a tidy data frame.

**Status:** Phases 0-9 of the development plan are implemented: rule
extraction, `read_study()`, `rules_for_domain()`, the `Check`-tree evaluator
(~35 operators, including dates and grouping), the `Operations` pipeline,
`Match Datasets` joins, and `check_study()` as the main user-facing entry
point. A conformance harness (`tests/conformance/run_conformance.R`) tracks
pass rate against CDISC's own reference data as coverage grows - see
[NEWS.md](NEWS.md) for the current numbers and known limitations.

Not affiliated with or endorsed by CDISC. Not a CORE-certified conformance engine.

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

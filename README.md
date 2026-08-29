# coreval

[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)

coreval is an R package that evaluates CDISC Open Rules (CORE) conformance rules against clinical trial datasets, returning findings as a tidy data frame.

**Status:** early scaffolding. Rule data is extracted and queryable (`list_rules()`); rule *evaluation* against actual datasets is not implemented yet.

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

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

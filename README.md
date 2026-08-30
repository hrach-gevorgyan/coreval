# coreval

<!-- badges: start -->
[![R-CMD-check](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hrach-gevorgyan/coreval/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Check your clinical trial data against CDISC's conformance rules, from R.**

Before a clinical study is submitted to a regulator, its datasets have to follow
the CDISC standards — the shared conventions for how trial data is laid out.
CDISC publishes hundreds of machine-readable rules describing what "correct"
means: dates that must not run backwards, codes that must come from an approved
list, records that must not be duplicated, and so on.

coreval runs those rules against your data and tells you, record by record, what
doesn't conform — so you can fix it before someone else finds it.

```r
study <- read_study("path/to/my/study")
result <- check_study(study)

head(result$findings)
#>       rule_id Dataset Record Variable      Value
#> 1 CORE-000005      AE      3   AESTDTC 2013-02-30
#> 2 CORE-000005      AE      3   AEENDTC 2013-02-11
```

Findings come back as a plain data frame, so you can filter, count, join and
export them with whatever tools you already use.

## Why you might want it

- **It runs entirely on your machine.** No internet connection, no API key, no
  account, no uploading trial data to a third-party service. The rules are
  bundled inside the package.
- **It tells you when it *couldn't* check something.** A rule that can't be
  evaluated is reported as skipped with a reason — never quietly counted as a
  pass. A clean findings table always means what it appears to mean.
- **It's a normal R data frame at the end.** No bespoke report format to parse.

## Installation

Not on CRAN yet. Install the development version from GitHub:

```r
# install.packages("pak")
pak::pak("hrach-gevorgyan/coreval")
```

Requires R 4.1 or later. Only two packages are needed to run it: `data.table`
and `haven`. Add `xml2` if you want Define-XML support.

## Getting started

```r
library(coreval)

# 1. Read a study. Point it at a folder of datasets - transport (.xpt),
#    SAS, or CSV. If a Define-XML file is in the folder, it's picked up too.
study <- read_study("path/to/study")

# 2. Check it. Every applicable rule runs against every dataset.
result <- check_study(study)

# 3. What didn't conform - one row per (dataset, record, variable).
head(result$findings)

# 4. What couldn't be checked, and why. Worth a look every time:
#    a short findings table might mean clean data, or might mean
#    a lot of rules were skipped.
head(result$skipped)
```

### Looking at the rules themselves

```r
rules_version()          # the exact CDISC Open Rules commit these came from
rules <- list_rules()    # all bundled rules, with where each came from
subset(rules, source == "published")   # only the fully-vetted ones
rules_for_domain("AE")   # which rules apply to a given domain
```

Not every bundled rule carries the same weight. `list_rules()` has a `source`
column saying whether a rule is published, deprecated, or draft — see
[NOTICE.md](NOTICE.md) for what each means and how much to trust it.

## How well does it work?

coreval is tested by replaying CDISC's own reference test cases. For each rule,
CDISC publishes example datasets that *should* trigger it and example datasets
that *shouldn't*, along with the exact records their engine flags. We run every
bundled rule against all of it and compare, record by record.

Of the rules that are published, fully executable, and ship reference data to
compare against, coreval currently agrees with CDISC's own results on
**475 of 499 — about 95%**.

<details>
<summary>The other numbers, and why there's more than one</summary>

| What's being counted | Agreement |
|---|---|
| Published rules that ship reference data — **the meaningful number** | **475 / 499 (95%)** |
| All published rules, including those with nothing to compare against | 475 / 543 (87%) |
| Every bundled rule, including deprecated and draft ones | 583 / 722 (81%) |

Three honest caveats behind those numbers:

**81 rules ship no reference data at all.** CDISC publishes the rule but no
example datasets, so there's nothing to compare against — those rules can't pass
*or* fail. Counting them as failures would understate things by about ten points;
hiding them would overstate. Both numbers are shown.

**Deprecated and draft rules are a weaker pool.** Their example data predates
CDISC's current conventions — several number their records starting from the
spreadsheet header row, so one expects a "record 5" in a four-row file. Those are
problems with the example data, not with coreval.

**Most remaining disagreements are problems in the reference data, not bugs.**
The usual tell is that a file's own stated values contradict its own data, which
means the data was edited after the expected results were generated. Where a
disagreement *is* a real gap in coreval, it's recorded as one.

</details>

**Please don't read that percentage as a quality score.** CDISC's example data is
almost entirely made of simple, single-file datasets, so it doesn't exercise
plenty of things real submissions do — a domain split across several files, for
instance. A real bug that silently switched off a third of the rules on
split-domain studies moved that percentage by exactly zero. It's a floor, not a
ceiling.

coreval is **not** a CORE-certified engine. These numbers describe agreement with
CDISC's published reference data. They aren't certification, and they aren't a
regulatory guarantee.

## Define-XML

If a Define-XML file (2.0 or 2.1) sits in the study folder, `read_study()` reads
it, and rules that compare your data against what Define-XML declares will run.
This needs the `xml2` package; without it, those rules are simply reported as
skipped.

## Status

Under active development, and the API may still change. It's useful today for
finding real problems in real data; it isn't yet a finished product. See
[NEWS.md](NEWS.md) for what's landed.

## Contributing

Issues and pull requests are welcome — bug reports especially, and most
especially a dataset that produces a wrong or missing finding. Please take a
look at the [Code of Conduct](CODE_OF_CONDUCT.md) first.

## License and attribution

Package code is MIT licensed ([LICENSE.md](LICENSE.md)). The bundled rule
definitions come from
[cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules) and
remain under CDISC's own terms — see [NOTICE.md](NOTICE.md).

Not affiliated with or endorsed by CDISC.

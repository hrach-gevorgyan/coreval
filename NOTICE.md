# Notice

## Licensing

coreval's own package code is MIT licensed — see [LICENSE.md](LICENSE.md).

The rule definitions bundled in `inst/extdata/rules.rds` are extracted from
[cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules),
copyright CDISC, and remain subject to that project's terms rather than
coreval's MIT license.

The reference metadata bundled in `inst/extdata/` (domain classes, variable
metadata) is derived from the offline, MIT-licensed caches shipped inside
[cdisc-org/cdisc-rules-engine](https://github.com/cdisc-org/cdisc-rules-engine).
No CDISC API is contacted at build time or at run time.

`data-raw/UPSTREAM_SHA` records the exact upstream commit a given release was
built from; `coreval::rules_version()` reports the same at run time.

## How much to trust a given rule

Not every bundled rule carries the same weight. `coreval::list_rules()` exposes a
`source` column for exactly this reason:

- **`published`** — from upstream's `Published/` directory, with
  `Core$Status == "Published"` and full reference test data. These are the rules
  the project's reported conformance figures are based on.
- **`deprecated_dir`** — from upstream's `Deprecated/` directory. Despite the
  name these are current SDTM-only rules (`Core$Status == "Published"`, with test
  data) that upstream has temporarily parked there during unrelated integration
  work. Upstream's own README says: *"These rules may work, but their execution
  and data has not been fully validated - please use discernment if using them."*
  Their bundled reference data also predates CDISC's current conventions in
  places, so disagreements here often reflect the example data rather than
  coreval.
- **`fda_business_rules_draft`** — from upstream's `Unpublished/FDA Business
  Rules/` directory, with `Core$Status == "Draft"`. Only rules that already ship
  reference test data are included. Draft means what it says: some carry the rule
  authors' own open questions in their source.

## Disclaimer

coreval is not affiliated with, endorsed by, or certified by CDISC, and is not a
CORE-certified conformance engine.

Reported conformance figures describe agreement with CDISC's published reference
test data. They are not certification, not a regulatory guarantee, and not a
substitute for your organisation's own validation. Passing every check here does
not mean a submission will be accepted; a finding here does not necessarily mean
a submission will be rejected.

Use of this software is at your own risk, under the terms in
[LICENSE.md](LICENSE.md).

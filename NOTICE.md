# Notice

## What this project is

coreval is an **independent, personal open-source project**, written and
maintained by Hrach Gevorgyan. It is not a CDISC product, is not affiliated with
or endorsed by CDISC, and is not a CORE-certified conformance engine.

Its purpose is to give people preparing clinical trial data a **fast, local,
unqualified pre-check** — a way to catch obvious conformance problems while
still writing the code, instead of discovering them later through a slower
formal validation cycle. It is meant to run *alongside and before* a qualified
validation tool, never instead of one.

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

## Coverage

Rules for SDTM, SEND and TIG are included, across their published versions.

**ADaM rules are not yet included, and their absence is not a design decision.**
CDISC publishes 197 ADaM rules, but none of them currently ships reference
results — there is no published expected output against which an implementation
can be verified. Including them would mean shipping checks that nobody has
validated, which contradicts this project's core rule of never reporting an
unverifiable check as a pass. They will be added once CDISC publishes reference
data for them.

## Disclaimer

coreval is an independent project, not affiliated with, endorsed by, or
certified by CDISC, and is not a CORE-certified conformance engine.

It is an **unqualified** tool. It is not validated software, carries no
regulatory standing, and is not a substitute for your organisation's own
validation procedures or for a qualified validation system. Passing every check
here does not mean a submission will be accepted; a finding here does not
necessarily mean a submission will be rejected.

Reported conformance figures describe agreement with CDISC's published reference
test data — nothing more. They are a lower bound on correctness, not
certification.

Use of this software is at your own risk, under the terms in
[LICENSE.md](LICENSE.md).

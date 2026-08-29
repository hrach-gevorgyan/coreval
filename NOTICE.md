# Notice

coreval's package code is MIT licensed (see [LICENSE.md](LICENSE.md)).

The rule definitions bundled in `inst/extdata/rules.rds` are extracted from
[cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules),
copyright CDISC, and are subject to that project's own license terms, not
coreval's MIT license. See `data-raw/UPSTREAM_SHA` for the exact upstream
commit each release was built from, and `coreval::rules_version()` for the
same information at runtime.

Not all bundled rules carry the same level of trust — `coreval::list_rules()`
exposes a `source` column for exactly this reason:

- **`published`** — from upstream's `Published/` directory, `Core$Status ==
  "Published"`, with full reference test data.
- **`deprecated_dir`** — from upstream's `Deprecated/` directory. Despite the
  name, these are current SDTM-only rules (`Core$Status == "Published"`,
  full test data) that upstream has temporarily parked there during
  unrelated integration work. Upstream's own README says: *"These rules may
  work, but their execution and data has not been fully validated - please
  use discernment if using them."*
- **`fda_business_rules_draft`** — from upstream's `Unpublished/FDA Business
  Rules/` directory, `Core$Status == "Draft"`. Only rules that already ship
  reference test data are included.

coreval is not affiliated with or endorsed by CDISC, and is not a
CORE-certified conformance engine.

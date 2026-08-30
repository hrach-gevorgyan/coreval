# coreval 0.0.0.9000

First development version. Not yet released; the API may still change.

## What it does

* `read_study()` reads a study from a folder of transport (`.xpt`), SAS or CSV
  datasets, and picks up a Define-XML (2.0 or 2.1) file if one is present.
* `check_study()` runs every applicable bundled rule against every dataset and
  returns findings as a tidy data frame — one row per (dataset, record,
  variable) — alongside a table of what could not be checked and why.
* `list_rules()`, `rules_for_domain()` and `rules_version()` expose the bundled
  rule set itself, including which upstream commit it came from and how much
  each rule can be trusted.

## Coverage

* 756 rules bundled as data, covering the SDTM, SEND and TIG standards across
  their published versions, extracted at build time from a pinned commit of
  CDISC Open Rules. Checking a study needs no internet connection and no API
  key.
* Around 60 rule operators, including partial-date comparison (SDTM dates are
  legitimately incomplete, such as `2024-03`), grouping and uniqueness checks,
  and set membership.
* The `Operations` pipeline (pre-computed values a rule's checks refer to),
  `Match Datasets` joins including RELREC relationships and SUPP/SQ
  supplemental qualifiers, and seven rule types spanning record-level, dataset,
  variable-metadata and domain-presence checks.

## Correctness

* Verified by replaying CDISC's own reference test cases and comparing flagged
  records one by one. Currently agrees with CDISC on 475 of 499 published,
  fully executable rules that ship reference data (about 95%). See the README
  for the other denominators and what they mean.
* A rule that cannot be evaluated is always reported as skipped, with a reason,
  rather than counted as a pass — so a clean findings table means what it
  appears to mean.

## Known limitations

* Rules needing CDISC Library variable metadata, or a merged view of a domain
  split across several files, are reported as skipped rather than evaluated.
* Values are reported as parsed, so a source value of `0.0` is reported as `0`.
* Not a CORE-certified engine. These results describe agreement with CDISC's
  published reference data, not certification.

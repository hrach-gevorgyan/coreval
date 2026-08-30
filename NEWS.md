# coreval 0.0.0.9000

First development version. Not yet released; the API may still change.

An independent project — not affiliated with or endorsed by CDISC, and not a
CORE-certified engine. It is a fast, local, **unqualified** pre-check meant to
run alongside and before a qualified validation system, never instead of one.

## What it does

* `read_study()` reads a study from a folder of transport (`.xpt`), SAS or CSV
  datasets, and picks up a Define-XML (2.0 or 2.1) file if one is present.
* `check_study()` runs every applicable bundled rule against every dataset and
  returns findings as a tidy data frame — one row per (dataset, record,
  variable) — alongside a table of what could not be checked and why.
* `write_findings()` saves the result to Excel (one workbook, two sheets) or
  CSV (two files), so findings can be shared with people who don't use R or
  attached to data-review documentation. Both the findings and the skipped
  table are always written — a short findings table can mean clean data or
  many skipped rules, and those look identical otherwise.
* `list_rules()`, `rules_for_domain()` and `rules_version()` expose the bundled
  rule set itself, including which upstream commit it came from and how much
  each rule can be trusted.

## Coverage

* CDISC Library variable metadata is bundled for SDTM, SEND, ADaM and TIG
  (Core designation, ordinal, label, role and data type), together with the
  SDTM Model's class variables. Rules that compare a dataset's own variable
  metadata against the standard's can therefore be evaluated rather than
  skipped, and SEND studies resolve against SEND metadata instead of being
  refused. Extracted at build time from the offline cache that CDISC's own
  rules engine ships; no CDISC API is contacted at build or run time.
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
  records one by one. Currently agrees with CDISC on 482 of 505 published,
  fully executable rules that ship reference data (about 95%). See the README
  for the other denominators and what they mean.
* A rule that cannot be evaluated is always reported as skipped, with a reason,
  rather than counted as a pass — so a clean findings table means what it
  appears to mean.

## Known limitations

* **ADaM rules are not included yet.** CDISC publishes 197 of them, but none
  currently ships reference results, so there is no published expected output
  to verify an implementation against. They will be added once that reference
  data exists — shipping unverifiable checks would contradict the rule above.
* Uniqueness checks now span every file a domain is split across, so a value
  appearing once in each of two files is correctly reported as a duplicate.
  A few rules that expect findings *merged* under a single dataset name,
  rather than reported per file, are still skipped.
* Rules needing CDISC Controlled Terminology *terms* are skipped: that data is
  around 438 MB, which belongs in a separate data package rather than here.
  The CT package dates are bundled, so rules checking that a study cites a real
  terminology version do run.
* Values are reported as parsed, so a source value of `0.0` is reported as `0`.
* Not a CORE-certified engine. These results describe agreement with CDISC's
  published reference data, not certification.

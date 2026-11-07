# Notice

## What this project is

coreval is an **independent, personal open-source project**, written and
maintained by Hrach Gevorgyan. It is not a CDISC product, is not affiliated with
or endorsed by CDISC, and is not a CORE-certified conformance engine.

Its purpose is to give people preparing clinical trial data a **fast, local,
unqualified pre-check**: a way to catch obvious conformance problems while
still writing the code, instead of discovering them later through a slower
formal validation cycle. It is meant to run *alongside and before* a qualified
validation tool, never instead of one.

## Licensing

coreval's own package code is MIT licensed. See [LICENSE.md](LICENSE.md).

The bundled third-party material and the MIT notices it requires are
reproduced in `inst/COPYRIGHTS`, which **ships with the installed package**. This file does
not, so the legally required notice travels with the software rather than only
with the repository. Read it after installing with:

```r
file.show(system.file("COPYRIGHTS", package = "coreval"))
```

The rule definitions bundled in `inst/extdata/rules.rds` are extracted from
two repositories and remain subject to their terms rather than coreval's MIT
license: the CORE 1.0 SDTMIG and FDA Business Rules from
[verisianHQ/core-contributor](https://github.com/verisianHQ/core-contributor),
copyright Verisian, and the SENDIG, TIG and USDM rules from
[cdisc-org/cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules),
copyright CDISC.

The reference metadata and Controlled Terminology bundled in `inst/extdata/`
are derived from the offline, MIT-licensed caches shipped inside
[cdisc-org/cdisc-rules-engine](https://github.com/cdisc-org/cdisc-rules-engine).
That repository carries its own copyright notice, distinct from the rules
repositories', and `inst/COPYRIGHTS` reproduces all three. A few reference
tables CORE 1.0's rules read (the FDA guides list, the FDA Data Standards
Catalog, and ISO 3166 and GENC country lists) come from Verisian's fork of
that engine, verisianHQ/cdisc-rules-engine, under the same notice.

**No CDISC API is contacted, at build time or at run time.** CDISC's own engine
reaches the CDISC Library through an API requiring a `CDISC_LIBRARY_API_KEY`,
under the Library's separate terms of use. coreval holds no key and makes no
such request. The rules, standards metadata and terminology are taken from
material committed to a public repository under MIT, by CDISC or by Verisian.
The W3C schemas and the JSONata library are not CDISC's: `inst/COPYRIGHTS`
gives their own notices.

`data-raw/UPSTREAM_SHA` (cdisc-open-rules), `data-raw/UPSTREAM_SHA_CORE1`
(core-contributor), `data-raw/UPSTREAM_SHA_ENGINE` and
`data-raw/UPSTREAM_SHA_CORE1_ENGINE` record the exact upstream commits a
given release was built from. At run time both rules commits are on the rule
table as `attr(list_rules(), "rules_version")`, and `write_findings()`
records them in every file it writes.

## Trademarks

CDISC, CORE, SDTM, SEND, ADaM, Define-XML and TIG are trademarks or registered
trademarks of the Clinical Data Interchange Standards Consortium. They are used
in this project only to identify the standards and rules it reads. No claim to
them is made, and their use does not imply CDISC sponsorship or approval.

## What is bundled, and how far it has been checked

Which rules are fully vetted, which are drafts, and how each was verified is in
[docs/COVERAGE.md](docs/COVERAGE.md). `list_rules()` carries the same
distinction on a `source` column, so a report can always be traced back to the
standing of the rule that produced it.

## Disclaimer

coreval is an independent project, not affiliated with, endorsed by, or
certified by CDISC, and is not a CORE-certified conformance engine.

It is an **unqualified** tool. It is not validated software, carries no
regulatory standing, and is not a substitute for your organisation's own
validation procedures or for a qualified validation system. Passing every check
here does not mean a submission will be accepted; a finding here does not
necessarily mean a submission will be rejected.

Reported conformance figures describe agreement with the rules' published
reference test data, nothing more. They are a lower bound on correctness, not
certification.

Use of this software is at your own risk, under the terms in
[LICENSE.md](LICENSE.md).

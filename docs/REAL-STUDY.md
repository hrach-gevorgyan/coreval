# A real study, checked by coreval and by CDISC's engine

CDISC's rule examples are small and hand-built, and a package can agree with
all of them while still getting real submission data wrong. This is the test
that answers that: one complete, real SDTM study, checked by coreval and by
CDISC's own engine with the same settings, and every finding compared rule by
rule.

Run it again before a release. The numbers below describe the run recorded
here, at the versions listed, and will move when the rules, the engine or
coreval do.

## The study

CDISCPILOT01, CDISC's pilot submission, from
[cdisc-org/sdtm-adam-pilot-project](https://github.com/cdisc-org/sdtm-adam-pilot-project)
at commit `667511d4b183871d74392ba691c935c38d431d39`. It is a complete SDTMIG
3.1.2 submission: 22 datasets, 294,677 records, a define.xml, and the same 22
datasets again as Dataset-JSON.

It is published under CDISC's terms of use, which do not allow it to be
redistributed, so it is not in this repository. Clone it into `data-raw/upstream/`,
which git ignores.

## How to repeat it

Only the SDTM folder is needed:

```bash
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/cdisc-org/sdtm-adam-pilot-project.git \
  data-raw/upstream/sdtm-adam-pilot-project
git -C data-raw/upstream/sdtm-adam-pilot-project sparse-checkout set \
  updated-pilot-submission-package/900172/m5/datasets/cdiscpilot01/tabulations/sdtm
```

Both tools are run on a folder holding the 22 `.xpt` files and nothing else.
The define.xml is left out because the engine cannot read it (see below), and a
comparison needs both sides to see the same input.

The engine, from its clone in `data-raw/upstream/cdisc-rules-engine` with the
virtual environment described in `tests/conformance/compare_engine.py`:

```bash
python core.py validate -s sdtmig -v 3-2 -uc INDH -ct sdtmct-2014-09-26 \
  -d <folder of .xpt files> -of json -rr -o <out>/report -p disabled -l error
```

Then coreval, and the comparison:

```bash
Rscript tests/conformance/pilot_study.R <folder of .xpt files> <out>
python tests/conformance/compare_pilot.py <out>/report.json <out>
```

### Why these settings

- **SDTMIG 3.2.** The pilot is 3.1.2, and the engine has rules only for 3.2,
  3.3 and 3.4. 3.2 is the nearest.
- **Use case INDH**, a human drug study, which the pilot is.
- **CT package sdtmct-2014-09-26.** The pilot's TS names no terminology
  version, so both tools are given the same one. It is the earliest the engine
  carries, and close to the pilot's own date.

## The run recorded here

| | |
|---|---|
| coreval | commit `55a6765`, rules from cdisc-open-rules `1fb7b81e40bdb6632375761c561fabd29676a477` |
| CDISC engine | 0.17.1, cdisc-rules-engine `8740d201c4a3816a8fff93745d698486cb0ea504` |
| Time | coreval 32 s, engine 443 s, on the same machine |

## What came out

Every rule the engine reported on falls into one of these:

| | rules |
|---|---|
| Both tools agree, both found no problems | 117 |
| Both tools agree, both found the same problems | 14 |
| Retired rule: the engine runs it, coreval does not by default | 60 |
| The engine crashed | 72 |
| The engine considered the rule not applicable | 127 |
| Both found problems, on different records | 2 |

No rule is left where only one of the two found problems without a known
reason. Each category is explained below.

### Where coreval was wrong, and is fixed

Three defects, all found by this comparison, none reachable from CDISC's rule
examples:

- **Text in the Windows encoding SAS writes.** Three TS values carry a curly
  apostrophe as the single byte 0x92, which is not a character in UTF-8. Every
  pattern rule meeting one warned and left the row unchecked, 126 warnings in
  all. Such text is now read as Windows-1252.
- **Conversion noise in transport-file numbers.** The same visit number was
  read as 9.2999999999999989 in LB and 9.3000000000000007 in SV, and
  CORE-000168 reported 250 lab records whose visit exists. Numbers from XPT and
  SAS files are rounded to 15 significant digits.
- **Keys written with padding.** IDVARVAL 1 is stored as `"       1"`, so no
  SUPPLB or RELREC row found its parent record, and CORE-000206 reported all
  64,637 of them. Keys are compared without surrounding blanks.

With those fixed, the pilot gives identical findings read from its XPT files
and from its Dataset-JSON copy: 40,355 finding rows each, from 4,001 checks,
with the define.xml present.

### Where the engine is wrong

- **CORE-000542** (a numeric `--STRESC` must match `--STRESN`). The engine
  reports 5,592 records; coreval reports 24, and those 24 are among the
  engine's. The other 5,568 are the engine's own conversion noise: `LBSTRESC`
  `8.55` against `LBSTRESN` read as `8.549999999999999`. The 24 are real
  (`QSSTRESC` `56.7` against `QSSTRESN` `56.7241379310345`).
- **CORE-000699.** The engine could not find the grouping variables `QSSPEC`
  and `QSMETHOD`, which the pilot does not have, and reported that error as a
  finding on a record `0` of dataset `N/A`. coreval reports two QS records.
- **The define.xml.** The engine stops with an `AttributeError` reading the
  pilot's own define.xml. coreval reads it.
- **72 rules crashed**, most with "evaluation dataset failed to build", some on
  the same 0x92 byte coreval now handles. On 7 of them coreval found problems,
  and those are real: a study day of 366 on the reference start date
  (CORE-000552), baseline flags with no result (CORE-000643), `--DY` absent
  where `--DTC` is present (CORE-000321, CORE-000793), expected variables
  missing (CORE-000334), labels that differ from the 3.2 Implementation Guide
  (CORE-000398), and leading blanks in text (CORE-000867, which is the same
  padding described above).

### Retired rules

60 rules the engine ran are ones CDISC has retired in its rules repository, and
coreval does not run retired rules unless asked (`include_deprecated = TRUE`):
a retired rule has a published replacement, and running both reports one
problem twice. That is a deliberate difference, kept after this comparison.

The engine found problems under 10 of them. With retired rules switched on,
coreval reports exactly the same number of records on all 10:

| rule | records, both tools |
|---|---|
| CORE-000264 | 1,818 |
| CORE-000331 | 52 |
| CORE-000333 | 122 |
| CORE-000531 | 52 |
| CORE-000655 | 12 |
| CORE-000656 | 12 |
| CORE-000657 | 250 |
| CORE-000701 | 221,114 |
| CORE-000841 | 1 |
| CORE-000842 | 122 |

### Rules only one tool has

- **CORE-000294** (TSVAL must be ISO 8601). The engine considers it not
  applicable; coreval reports TS `AGEMAX = "No maximum"`, which is not an ISO
  8601 value.
- **Six rules the engine's bundled rule set does not include** for SDTMIG 3.2,
  where coreval found problems: CORE-000734, CORE-000737, CORE-000738, and the
  FDA business rules FB0801, FB1107 and FB3211.

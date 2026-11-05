# A real study, checked by coreval and by CORE 1.0's engine

The rules' own examples are small and hand-built, and a package can agree with
all of them while still getting real submission data wrong. This is the test
that answers that: one complete, real SDTM study, checked by coreval and by the
reference engine with the same settings, and every finding compared rule by
rule.

Since CORE 1.0 the SDTM rules are Verisian's, and the reference for them is
Verisian's engine, so that is the engine this study is checked with.

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

Both tools are run on a folder holding the 22 `.xpt` files and nothing else,
so both see the same input.

The engine is [verisianHQ/cdisc-rules-engine](https://github.com/verisianHQ/cdisc-rules-engine)
at the commit in `data-raw/UPSTREAM_SHA_CORE1_ENGINE`, cloned to
`data-raw/upstream/verisian-engine` with its requirements installed in a
virtual environment there. It runs an in-memory PostgreSQL of its own (`-mem`),
so no database needs installing. The rules are core-contributor at the commit
in `data-raw/UPSTREAM_SHA_CORE1`, cloned beside it:

```bash
cd data-raw/upstream/verisian-engine
PYTHONUTF8=1 .venv/Scripts/python core.py validate -s sdtmig -v 3-2 \
  -ct sdtmct-2014-09-26 -d <folder of .xpt files> \
  -lr ../core-contributor/sdtm_rules -mem -of JSON -rr -o <out>/report \
  -p disabled -l error
```

Its raw report is turned into the shape the comparison reads, then coreval is
run and the two compared:

```bash
python tests/conformance/core1_report.py <out>/report.json <out>/engine.json
Rscript tests/conformance/pilot_study.R <folder of .xpt files> <out>
python tests/conformance/compare_pilot.py <out>/engine.json <out>
```

### Why these settings

- **SDTMIG 3.2.** The pilot is 3.1.2, and the rules exist only for 3.2, 3.3
  and 3.4. 3.2 is the nearest.
- **CT package sdtmct-2014-09-26.** The pilot's TS names no terminology
  version, so both tools are given the same one, close to the pilot's own date.
- **No dictionaries, no define.xml.** 1.0's engine takes MedDRA, WHODrug and
  the other dictionaries as separate inputs, which the pilot does not supply;
  coreval skips those rules too. Rules needing a define are not applicable to
  the engine without `-dxp`, so they are compared only where both ran.

## The run recorded here

| | |
|---|---|
| coreval | the commit that recorded this run, 5 November 2026; the same 507 rules came out the same way at `e987c78` |
| Rules | verisianHQ/core-contributor `a3b4d0b08e45f44bcd1aafe16687aa76fe9680e3` |
| Engine | verisianHQ/cdisc-rules-engine 1.0.0, `4a734105540a83f1df80d061df5049bd4b6bda4d` |
| Time | coreval 33 s, engine 181 s, each the whole command, on the same machine |

## What came out

The engine reported on 507 rules:

| | rules |
|---|---|
| Both tools agree, both found no problems | 338 |
| Both tools agree, both found the same problems | 44 |
| The engine considered the rule not applicable | 114 |
| Both found problems, on records that do not line up | 8 |
| Only coreval found problems | 1 |
| Only the engine found problems | 1 |
| The engine crashed | 1 |

Every one of the 11 that differ has a known cause, below. None is coreval
missing a problem the engine finds.

### Same findings, reported differently

- **CORE-000206 and CORE-000701.** Every record the engine reports is among
  coreval's (50,234 of 64,637, and 139,785 of 221,114). The engine stops at
  50,000 findings per dataset; coreval keeps them all here.
- **CORE-000867.** Leading blanks in text: the same padded values, 50,292
  against 64,695, with the same 50,000 cap. The records do not line up because
  the engine numbers them after its own sort.
- **CORE-002061, CORE-002062.** Length rules over a table with one row per
  value. Both tools flag the same variables: for CORE-002062, the same 30, with
  the same longest value and declared length on each. The engine numbers rows
  within that table, coreval reports the dataset's first record, so the pairing
  by record finds none in common.
- **CORE-002084.** One study-level finding each, numbered differently.

### Where the engine is wrong

- **CORE-000542** (a numeric `--STRESC` must match `--STRESN`). The engine
  reports 9,334 records and coreval 24, all 24 among the engine's. The other
  9,310 are conversion noise in transport-file numbers: `LBSTRESC` `8.55`
  against `LBSTRESN` read as `8.549999999999999`. coreval rounds numbers from
  XPT and SAS files to 15 significant digits.
- **CORE-000168.** The same noise: the visit number 9.3 is read as
  9.2999999999999989 in LB and 9.3000000000000007 in SV, so the engine reports
  250 lab records whose visit exists.
- **CORE-000270** (a planned visit must be one TV lists). Both report the
  same 1,450 records; coreval reports 250 more, all in LB, with visit numbers
  1.2, 1.3, 4.2 and 9.3, which TV does not list. They are stored with the same
  noise (1.2000000000000002), and the engine compares visit numbers exactly
  when it pairs records up, so it never reaches them.
- **CORE-002056 and CORE-000550.** The engine looks the Trial Design class up
  under the name "TRIAL DESIGN MODEL", which its Library tables do not use.
  Running its own lookup function on that name returns nothing. CORE-002056
  therefore finds no trial design datasets where the pilot has five, and
  CORE-000550 crashes with "Class metadata is not found".

### Where coreval was wrong, and is fixed

This comparison found these, none reachable from the rules' own examples:

- **Text against numbers.** For a 1.0 rule, `type_insensitive: true` means
  compare as text, where coreval compared numbers. CORE-000206 reported nothing
  where the engine reports 50,234 SUPP keys written `"       1"`. Fixed; the two
  now agree.
- **The wrong Library.** SDTMIG 3.2 was checked against the 3.4 Library, and
  SUPP datasets had no Library variables at all.
- **A missing column read as text.** A condition naming a column the dataset
  lacks compared against the column's name (CORE-000264). 1.0 reads such a
  condition as false, and coreval now does too for 1.0 rules.
- **Study-level rules, once per record.** CORE-002084 reported 294,677 rows
  for one fact.
- **Variable lengths were never read.** The length rules need each variable's
  declared length, which is now read from the transport file's header and from
  Dataset-JSON.
- **Grouped findings were merged, and each carried every row's value.**
  CORE-002062 reported one finding per dataset, each holding 644,030 numbers
  for SUPPLB.
- **A pre-check had drifted from the check it guards**, and refused rules that
  run.

### Not applicable to the engine

The engine skips 114 rules: 57 because an input was not supplied (31 need a
define.xml, 1 a study tagging file, 25 a dictionary), and most of the rest
because they concern datasets the pilot does not have, such as IE, TR, EC and
SS.

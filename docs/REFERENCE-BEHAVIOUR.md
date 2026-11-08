# How the reference engines actually behave

coreval is judged against two engines: Verisian's
`verisianHQ/cdisc-rules-engine` (CORE 1.0) for the SDTM rules, and CDISC's
`cdisc-org/cdisc-rules-engine` for SEND, TIG and USDM. Most entries below
concern CDISC's engine; those about CORE 1.0 say so. Where coreval and the
engine for a rule differ and no third source settles it, the engine is right
by definition.

**Read the relevant entry before changing anything in that area.** Most of what
follows looks like a bug in coreval until you know the reference does the same
thing. Every entry names its evidence: a line of the pinned source, or a
fixture, or a run of the engine itself.

Where an entry calls a fixture *stale*, that means the fixture's own values
contradict its own data or contradict the pinned implementation. It never means
an inconvenient result was set aside.

## Reading a rule

1. **`value_is_literal` defaults to false, but that is not the whole rule.**
   The engine tries `value` as a column reference only when a column of that
   *exact name* exists. Otherwise, whatever `value_is_literal` says, it falls
   back to the literal text. `value: Y` with no column named `Y` means the
   string `"Y"`. Returning `NULL` there instead makes the condition silently
   always false. A multi-element `value` (`is_not_contained_by: [Y, N]`) is
   never a column reference and needs no special case: it simply never matches
   one name.

2. **An Operations id does not have to start with `$`.** Most rules write
   `$name`, but `CDISC.SDTMIG.CG0555`-`CG0560` declare theirs bare, as
   `pkunit_terms`. Resolve bindings by exact id whichever form they take. Miss
   this and the condition compares a column against the seven-letter string
   `"pkunit_terms"`, which is never contained by it, so every row is reported.

3. **`--` is a variable-prefix wildcard**, not a literal: `SUPP--` matches
   `SUPPAE` and `SUPPDM`.

4. **`ALL` in `Domains` is a sentinel**, not a domain name. `Domains: ALL`
   alongside a narrower `Classes` does **not** widen scope: both still have to
   match. Tested directly. Letting `Domains: ALL` override `Classes` turns
   three rules green and breaks eleven, a net loss of eight.

5. **`Output Variables` is part of the contract.** A wrong set or order fails
   differential tests even with correct logic.

6. **`Sensitivity: Record` and `Dataset` change the output shape**: one finding
   per row against one per dataset. `Record` in `results.csv` is 1-based and
   positional as read; reordering during load breaks every comparison.

## Operators that surprise people

7. **`is_inconsistent_across_dataset` flags the whole group.** Since CDISC's
   engine 1.0.0, as in Verisian's, every row of a group holding more than one
   value is flagged, and `where_populated` and `where_populated_columns` keep rows
   out of the comparison first. Before that it flagged only the minority. With no
   grouping column it now answers FALSE, where it used to fail.

8. **Date comparison truncates to the coarser precision.**
   `get_common_precision()` returns `min(p1, p2)`, so `2018-11-06T12:00`
   against `2018-11-06` compares at day precision and is equal. Sheets that
   expect the finer comparison predate truncation.

9. **`equal_to_case_insensitive` is strict equality after case folding**, not a
   prefix or substring match (`_check_equality`).

10. **`contains_all` has two paths.** Row by row when both sides are columns of
    iterables, dataset-level otherwise. Implement only the second and a rule
    whose comparator is one collection *per row* gets a single verdict landed
    on row 1, and reports nothing.

11. **`is_not_unique_relationship` flags both directions.** A non-null value in
    either column that maps to more than one distinct value in the other, or to
    one value plus a null, is a violation; rows matching either side are
    reported. Since CDISC's engine 1.0.0 a missing comparator answers FALSE where
    it used to fail, and a list of comparators counts as blank only when all of
    them are blank.

11a. **`type_insensitive` has three settings.** `false` compares as stored, `true`
    casts both sides to text, and `numeric` compares as numbers where both sides are
    numbers and as stored otherwise. Reading it as a yes or no loses the third.

12. **A negation is not always a plain negation.** The reference negates
    `contains_all` *before* index alignment, so the dataset-level
    first-row-only shape survives rather than inverting into "every row but the
    first".

13. **A column the dataset lacks skips the rule, through `all` but not `any`.**
    CDISC's engine reads the target column for nearly every operator, and a
    missing one raises KeyError, which skips the rule ("Column not found in
    data", rules_engine.py). In the business-rules evaluator (engine.py) an
    `all` evaluates every child, so one missing column skips it even beside an
    `exists` guard; an `any` treats a branch that raises as no match, and
    raises only when every branch does. `exists`, `not_exists` and
    `inconsistent_enumerated_columns` read no column, and `is_unique_set`
    keeps whichever of its columns exist, the target included.

14. **CORE 1.0 answers the same case with FALSE.** A condition naming a column
    the dataset lacks is FALSE there (postgresql_operators.py,
    `_missing_columns_for_operator`), with its own list of exempt operators,
    and the rule runs. A missing column in an Operation (grouping, filter,
    target) still skips it (ColumnNotFoundError).

15. **CORE 1.0's `type_insensitive: true` is a text cast.** Only
    `type_insensitive: numeric` compares numbers (equal_to_operator.py). So
    an IDVARVAL of `"       1"` differs from the parent's sequence number 1,
    though the join that found the parent compares numbers.

## Metadata the engine reads, and from where

16. **`domain_label` comes from the standard, not from the study.** The engine
    reads the label the standard gives a domain
    (`operations/domain_label.py`), and the standards differ: SENDIG calls `LB`
    "Laboratory" where SDTMIG calls it "Laboratory Test Results".

17. **A variable's codelist C-code is a link, not a field.** It is the last
    segment of `_links.codelist[0].href`
    (`/mdr/root/ct/sendct/codelists/C66770` gives `C66770`), taken from the
    first link only (`base_dataset_builder`).

18. **A Define-XML codelist's C-code is its own `Alias` with Context
    `nci:ExtCodeID`**, matched as a *direct child*. Every `EnumeratedItem`
    inside the codelist carries one too, one per term, so matching descendants
    returns a term's code instead of the codelist's.

19. **Controlled terminology must be supplied, never guessed.** The engine's
    `-ct` is optional, but without it some terminology operations raise
    (`codelist_terms`) and one answers with an empty set
    (`get_codelist_attributes`). Terminology moves between
    releases: `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`.

    **The SDTM Model follows the guide.** CORE 1.0 reads the Model an
    Implementation Guide links to (`_links.model`): SDTMIG 3.2 uses Model 1.4, 3.3
    uses 1.7, 3.4 uses 2.0. coreval bundles those three for the 1.0 rules
    (`sdtm_model_versions.rds`, `use_sdtm_model()`) and keeps 2.1 for the rest.
    Read against 2.1, a 3.2 study's AERLPRC was allowed where its Model has no
    --RLPRC (CORE-000550), and SPTOBID, new in 2.1, passed on a 3.4 study.

## Reference behaviour that is a defect, not a rule

20. **Its operation cache rejects values it accepted.** `InMemoryCacheService.add()`
    guards with `get_data_size(data) > self.max_size` while the `LRUCache`
    behind it measures with a different function, so a value can pass the guard
    and then be refused. The operation is recomputed. On a 10,000-subject study
    the distinct-`USUBJID` list trips it.

21. **`prefix_equal_to` raised on non-string values** at commit `8740d201`,
    fixed in `0be94c38`. On CORE-001080's own fixture it raised "The operator can't be used with non-string values",
    because `TSVCDREF` is empty on 23 of 51 rows.

22. **Some rules errored on their own fixtures.** At commit `8740d201` the engine
    reported `EXECUTION ERROR` for CORE-000929 and CORE-001081 on the data CDISC
    ships with them. At 1.0.0 CORE-000929 runs all its cases.

**CORE 1.0's `empty_within_except_last_row` has no tiebreak.** It finds a group's
last record with `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY <ordering>)` alone
(`empty_within_except_last_row_operator.py`), so of two records sharing the ordering
value, the one counted as last is whatever the database's sort returns. On an SE
holding two elements with the same SESTDTC, swapping the two records, or reversing
the file, changed which one 1.0 reported (CORE-000527), in no consistent direction.
coreval breaks the tie by file order, so its answer can be reproduced.

**CORE 1.0 reads a codelist of several codes as one invalid code (CORE-000929).** It
stores a define variable's codelist codes as one comma-joined text
(metadata/store.py, `format_metadata_dict`) and asks whether that text is among the
DOMAIN codes (is_contained_by_operator.py, `IN`). Any codelist with more than one
term is reported, even when every term is valid: on a define whose RELREC RDOMAIN
codelist holds AE, DS, DD and FA, 1.0 reports RELREC record 3. coreval requires every
code to be a DOMAIN code, which gives 1.0's answer for a single code and for any
codelist holding an invalid one.

**The Library gives SUPPQUAL no roles before SDTMIG 3.3.** Its SUPPQUAL variables
carry a role from 3.3 on, and none in 3.1.2, 3.1.3 or 3.2. CORE-001081 compares the
define's role with the Library's, so for a 3.2 or older study every SUPP-- define
item is reported: run as 3.2, CORE 1.0 reports SUPPDM's IDVAR, IDVARVAL, QEVAL,
QLABEL and QNAM, and coreval does the same.

**CORE 1.0 cannot run CORE-002002 on the case it is written for.** It builds the
define key-uniqueness column for every Dataset Contents rule, so when a key the
define names is missing from the data, the whole rule fails. CORE-002002 asks
exactly whether --TESTCD is missing, and reports nothing on that case; coreval
skips it with the reason.

**CORE 1.0 orders a dataset of no known domain against an empty list.** For a
domain the declared SDTMIG version does not define and whose topic variable gives
no class (DI, SJ, TP, TT under 3.4), its `get_column_order_from_library` returns an
empty order without consulting the Model, and `is_not_ordered_subset_of` against an
empty list is always true. CORE-000852 reports such a dataset as out of order even
when its columns follow SDTM Model 2.0 exactly. coreval skips it: there is no
order to compare against.

**CORE 1.0 reads pooldef.xpt as domain PO.** It derives a domain from the first two
letters of a file name, so `get_model_column_order` finds no Model list for "PO",
returns nothing, and CORE-000550 reports every POOLDEF variable as not allowed,
although all four are SDTM Model 2.0's POOLDEF variables. Its own CORE-000852 run
on the same study fails with "Dataset 'po' not found in schema". coreval skips
the rule there.

**CORE 1.0 relates every record through a RELREC row it cannot resolve.** Its RELREC
join adds an IDVAR condition only for a variable the dataset has (relrec.py,
`_build_union_parts`, the `has_column` checks), and ignores the partner's IDVARVAL
when the record's own is blank. A RELREC row naming a variable its RDOMAIN lacks
therefore relates every record of that subject to every partner record, and
CORE-000744, CORE-000757, CORE-000766 and CORE-000767 report records nothing
relates. coreval relates no record through such a row, since it identifies none.
SDTM allows neither row, so only data with that error is affected.

**`does_not_have_next_corresponding_record` mislines its answers.** It
sorts by `ordering` alone, groups by `within`, and assigns the exploded
results back by position (dataframe_operators.py), so its answers belong to
the right records only when the data is already sorted by `within` and then
`ordering`. coreval keeps each answer on its own record.

**CORE 1.0's CORE-000539 flags the files of a split domain.** It compares each
dataset's name with the list of dataset names, and that list holds the file
names (`DM`, `LB1`, `LB2`), not the domains. Given `lb1.xpt` and `lb2.xpt`, both
`DOMAIN = "LB"`, and no `lb.xpt`, 1.0's engine reports LB1 and LB2, and so does
coreval. The SDTMIG allows a split domain, so on such a study this finding is
the rule's, not the data's.

**CDISC's engine can drop the last row of a narrow transport file.** It reads
XPT with `pd.read_sas` (services/data_readers/xpt_reader.py). In pandas 3.0.5,
when a row is 80 bytes or less, any all-blank 8-byte block in the file's last
80 bytes is taken for padding (`sas_xport.py`, `_record_count`), and that can
swallow the final real row. A three-row TS of four short variables reads as two
rows there and three in pyreadstat and haven, and the engine reported rows 1 and
2 of CORE-000742 where coreval reported 1, 2 and 3; widened past 80 bytes, the
engine reported all three. CORE 1.0 overrides `_record_count` and reads every
row (readers/data_readers/xpt_data_reader.py). CDISC's own cases are CSV and are
not affected; an engine run on a small hand-made XPT study has to be checked for it.

## Rule sets and denominators

23. **Partially Executable rules** are marked so by their authors and may not
    match reference output exactly. Most pass anyway; the harness reports a
    Fully Executable pass rate beside the full one.

24. **Many rules ship no expected output at all**: no `positive/`/`negative/`
    directories (CORE-000765 contains only `rule.yml`), or `data/` with
    no sibling `results/` (CORE-000675, most of `Deprecated/`). These are
    unmeasurable, not failing. Verified as a genuine absence, not a harness
    layout bug.

25. **Do not write a pass rate into this file.** It moves whenever a rule is
    fixed or the upstream pin changes. The conformance harness gives the
    current answer: `tests/conformance/scoreboard_core1.csv` (tracked) for the
    CORE 1.0 rules, and `tests/conformance/scoreboard.csv`, which it writes
    on each run, for CDISC's.

## Resolved: things that looked like semantics and were not

**CORE-000884 is a stale fixture, not a question about multi-domain rules.**
The rule's DM branch is
`all(DOMAIN == DM, AGEU empty, any(AGETXT non_empty, AGE non_empty))`, and
`negative/01`'s DM records 2, 3 and 4 satisfy it exactly. The sheet contains no
DM rows at all and cites `$age_count` and `$agetxt_count`, while the shipped
`rule.yml` declares one Operations id, `$ageu_count`. The answers were
generated against an earlier version of the rule. Multi-domain rules evaluate
once per domain, as every other rule does.

**CORE-000866's Check contradicts its own Description.** The Check uses
`date_greater_than_or_equal_to`, so `--DTC == --ENDTC` is a violation, but
`positive/01` record 1 has `LBDTC` and `LBENDTC` both `2018-01-29T07:00:00` and
expects nothing. The Description ("prior **or equal** to") agrees with the
fixture; the operator should be `date_greater_than`. coreval implements the
rule as published.

**CORE-000864's fixture is incomplete.** It omits SM, which the engine flags
alongside CE, CM, FA, LB, SE and SV.

**Split datasets report per physical file.** A finding names the file the
problem is in and that file's own row numbers, where CDISC names the merged
domain. Deliberate: a finding has to point at a file you can open.

## Settled by running the engines

Each of these was a known difference, now resolved by running the engine on
the same data as coreval.

- **CDISC's `target_is_sorted_by`.** coreval ports
  `check_target_ascending_in_sorted_group_with_regex` and the checks around it
  (dataframe_operators.py): misplaced blanks, dates of different precision
  that contain each other, each row's target against the one at its place once
  sorted by the date, and each date against its neighbours, for every sort
  specification. On 300 generated groups of shuffled, partial and blank dates,
  under all four sort orders and blank positions, 4,912 rows out of 4,912
  agree with the engine; the neighbouring-pair test used before disagreed on
  839. Affects CORE-000386 and CDISC's CORE-000535.
- **CDISC's length operators.** `longer_than` and its kin read the length
  through pandas' `.str`, which fails on a numeric column, so the rule is
  skipped; against a column they compare the two values' lengths; and a blank
  has length 0. All 18 combinations of operator and input agree with the
  engine. CORE 1.0 measures a number as text and answers FALSE for a blank.
- **CORE 1.0 column names** are matched whatever their case
  (models/sql/table_schema.py lower-cases every name), so a CSV header written
  `aeterm` answers a rule naming AETERM.
- **CORE 1.0 and an empty computed value.** `equal_to` and `not_equal_to`
  treat it as a blank (equal_to_operator.py): not equal for a filled target,
  equal to nothing.
- **TIG use cases** are kept per sub-standard (constants/use_cases.py), and
  the engine will not check a TIG study without `--substandard` (core.py).
  Nor will coreval: `standard = "TIG"` needs `substandard`.
- **CORE 1.0 joins** on `l.key = r.key` (merges/join.py): two blank text keys,
  read as "" from a transport file, pair; a missing number pairs with nothing.
- **A set is printed as a list**, `['ARMCD']`, even when it holds one value.
- **CORE 1.0 comparing text with a number.** With no `type_insensitive`, two columns
  of different types end the rule: PostgreSQL has no `=` between text and a number.
  `numeric` casts both sides and compares with `IS DISTINCT FROM`, so two values that
  are no numbers count as the same: "NEG" equals "POS". CDISC's engine compares as
  Python does without the flag, and "200" never equals 200.
- **CORE 1.0 and an SSTDTC that is not a date (CORE-002041).** The operator casts
  TSVAL to a timestamp (is_latest_available_exdict_version.py), so a blank, partial,
  impossible or interval value ends the rule with `execution_error` and no finding.
  TS's other rows, "Y" among them, do no harm: the TSPARMCD condition selects first.
  A date older than every release known is a finding, and no SSTDTC row is none. The
  rule was run through 1.0's own runner on 13 altered copies of its negative case,
  and coreval agrees on all 13; a value that stops the engine is a skip with a reason.
- **CORE 1.0's extended-term check (CORE-002117).** A term the define marks
  `def:ExtendedValue="Yes"` is compared with the codelist of the same C-code
  (the codelist's first `Alias`) in the terminology in use
  (define_extended_terms_in_ct.py). It is reported when it equals a submission
  value or one of that term's synonyms, case-sensitively. Synonyms are trimmed;
  the extended term is not, so `" AGEDTH"` is new. A third test, every
  ";"-part of the term being a part of a ";"-separated submission value, cannot
  fire on CDISC's terminology: no term of an extensible codelist in any release
  contains ";". On a define given 14 extended terms of every kind, the engine
  and coreval report the same six, in the same order. The terminology is the
  one the run names, so CORE-002117's own case, which names sdtmct-2024-09-27,
  reports ATNR: it became a synonym after 2020. coreval compares with the
  study's own SDTM or SEND package; the engine, given no `-ct` and a 2.1 define,
  also compares with the define's DEFINE-XML terminology, whose codelists a
  study's define does not normally extend.

## The engine answers by file format

CDISC's engine holds a blank text value as missing when it reads CSV or
Dataset-JSON, and as an empty string when it reads a transport file
(`pd.read_sas`). Some operators answer the two differently, so the same study
can get different findings from the engine as CSV and as XPT. coreval holds
every blank as "" but answers as the engine does for a missing value, which is
how every rule's worked example is written:

- `not_matches_regex`, `not_prefix_matches_regex` and
  `not_suffix_matches_regex` never report a blank. From a transport file the
  engine reports one.
- `is_unique_set` with a regex reduces a column whose first value is blank.
  From a transport file the engine leaves that column whole, and on a subject
  with a blank date, then `2022-01-05`, then `2022-01-05T10:00` it misses the
  duplicate both other readings report.

## Not followed, on purpose

- **CORE 1.0 numeric comparison of text.** 1.0 casts with `CAST(... AS
  NUMERIC)` (numeric_comparison_operator.py), which fails the query on text
  such as "LOW". Whether it fails depends on the order PostgreSQL evaluates the
  conditions in: CORE-000889 guards its comparison with a pattern and runs
  through the engine on "LOW" and "<5". Every other bundled 1.0 rule compares
  a variable SDTM defines as numeric, or a count, which a transport file or
  Dataset-JSON holds as a number. coreval answers row by row rather than guess
  the evaluation order.
- **`is_not_unique_set` with one column left.** When a comparator is absent and one
  column survives, CDISC's engine reports every row: under pandas 3.0.5 the counts of a
  single-column group do not line up with their 1-tuple keys. coreval counts them,
  and reports only the rows that repeat.
- **CORE 1.0 reading dates PostgreSQL's way.** The same cast accepts `20251102`,
  `Nov 2 2025` and `11/02/2025`. TSVAL for SSTDTC is ISO 8601, so CORE-002041 skips on
  these rather than compare a date in a form the standard does not allow.

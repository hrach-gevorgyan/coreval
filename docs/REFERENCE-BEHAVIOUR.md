# How CDISC's engine actually behaves

coreval is judged against `cdisc-org/cdisc-rules-engine`. Where the two differ
and no third source settles it, the reference is right by definition.

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

7. **`is_inconsistent_across_dataset` flags the minority.** Within an
   inconsistent group it reports only the rows holding the less common value,
   and every row when the counts tie (`_check_inconsistency`). Answer sheets
   that flag the whole group predate this and are stale.

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
    reported.

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
    `-ct` is required and it errors without one. Terminology moves between
    releases: `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`.

## Reference behaviour that is a defect, not a rule

20. **Its operation cache rejects values it accepted.** `InMemoryCacheService.add()`
    guards with `get_data_size(data) > self.max_size` while the `LRUCache`
    behind it measures with a different function, so a value can pass the guard
    and then be refused. The operation is recomputed. On a 10,000-subject study
    the distinct-`USUBJID` list trips it.

21. **`prefix_equal_to` raises on non-string values.** On CORE-001080's own
    fixture it raises "The operator can't be used with non-string values",
    because `TSVCDREF` is empty on 23 of 51 rows.

22. **Some rules error on their own fixtures.** The engine reports
    `EXECUTION ERROR` for CORE-000929 and CORE-001081 on the data CDISC ships
    with them.

**`does_not_have_next_corresponding_record` mislines its answers.** It
sorts by `ordering` alone, groups by `within`, and assigns the exploded
results back by position (dataframe_operators.py), so its answers belong to
the right records only when the data is already sorted by `within` and then
`ordering`. coreval keeps each answer on its own record.

## Rule sets and denominators

23. **16 rules are Partially Executable by design** and will never match
    reference output exactly. Exclude them from the pass-rate denominator and
    say so.

24. **Many rules ship no expected output at all**: no `positive/`/`negative/`
    directories (CORE-000110/645/765 contain only `rule.yml`), or `data/` with
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

## Still open

Differences from the reference that are known, traced, and not yet fixed.
None of them is reached by the rules' own examples.

- **`target_is_not_sorted_by` (CDISC's engine).** coreval checks neighbouring
  pairs in target order and flags both rows of a bad pair. The engine compares
  each row's target with the one that would sit at its position once sorted by
  the date (`check_target_ascending_in_sorted_group_with_regex`,
  dataframe_operators.py), flags only the blank row when a blank is out of
  place, and tests dates of different precision for overlap across all pairs.
  The two flag different records on out-of-order data. Affects CORE-000386 and
  CDISC's version of CORE-000535.
- **A length test on a number.** `longer_than` and its kin answer for a
  numeric target where CDISC's engine fails (`.str.len()`). Every bundled use
  targets text.
- **Prefix and suffix regex operators and blanks.** They are not exempt for a
  blank value, where matches_regex is; on CSV and Dataset-JSON input the
  engine exempts it. Reached only through DOMAIN and dataset names.
- **CORE 1.0 column names.** 1.0 finds a column whatever its case
  (table_schema.py); coreval matches the case written. XPT and Dataset-JSON
  names are upper case; a CSV written in lower case is not.
- **CORE 1.0 and a blank computed value.** `not_equal_to` against a scalar
  Operations value that came out missing is TRUE for a populated target in
  1.0 (`_is_empty_sql_operation_variable`); coreval leaves it unknown.
- **`is_unique_set` with a regex, on blank text (CDISC's engine).** The engine
  leaves a blank `""` as it is and puts an unmatched value with the missing
  ones (`apply_regex()`, helpers.py), and skips the column when its first
  non-missing value is blank. coreval holds every blank as `""` and groups
  blank, missing and unmatched together. The two agree where the engine reads
  blanks as missing (CSV and Dataset-JSON, as the rules' examples are) and
  could differ on XPT input. Affects CORE-001034.
- **A set of one shown as text.** A computed set holding one value is reported
  as `ARMCD`; CDISC's sheets write `['ARMCD']`. Display only.

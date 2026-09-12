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

## Metadata the engine reads, and from where

13. **`domain_label` comes from the standard, not from the study.** The engine
    reads the label the standard gives a domain
    (`operations/domain_label.py`), and the standards differ: SENDIG calls `LB`
    "Laboratory" where SDTMIG calls it "Laboratory Test Results".

14. **A variable's codelist C-code is a link, not a field.** It is the last
    segment of `_links.codelist[0].href`
    (`/mdr/root/ct/sendct/codelists/C66770` gives `C66770`), taken from the
    first link only (`base_dataset_builder`).

15. **A Define-XML codelist's C-code is its own `Alias` with Context
    `nci:ExtCodeID`**, matched as a *direct child*. Every `EnumeratedItem`
    inside the codelist carries one too, one per term, so matching descendants
    returns a term's code instead of the codelist's.

16. **Controlled terminology must be supplied, never guessed.** The engine's
    `-ct` is required and it errors without one. Terminology moves between
    releases: `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`.

## Reference behaviour that is a defect, not a rule

17. **Its operation cache rejects values it accepted.** `InMemoryCacheService.add()`
    guards with `get_data_size(data) > self.max_size` while the `LRUCache`
    behind it measures with a different function, so a value can pass the guard
    and then be refused. The operation is recomputed. On a 10,000-subject study
    the distinct-`USUBJID` list trips it.

18. **`prefix_equal_to` raises on non-string values.** On CORE-001080's own
    fixture it raises "The operator can't be used with non-string values",
    because `TSVCDREF` is empty on 23 of 51 rows.

19. **Some rules error on their own fixtures.** The engine reports
    `EXECUTION ERROR` for CORE-000929 and CORE-001081 on the data CDISC ships
    with them.

## Rule sets and denominators

20. **16 rules are Partially Executable by design** and will never match
    reference output exactly. Exclude them from the pass-rate denominator and
    say so.

21. **Many rules ship no expected output at all**: no `positive/`/`negative/`
    directories (CORE-000110/645/765 contain only `rule.yml`), or `data/` with
    no sibling `results/` (CORE-000675, most of `Deprecated/`). These are
    unmeasurable, not failing. Verified as a genuine absence, not a harness
    layout bug.

22. **Do not write a pass rate into this file.** It moves whenever a rule is
    fixed or the upstream pin changes. `tests/conformance/scoreboard.csv` is
    the current answer.

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

**SDTMIG has no published CORE rule for general date format.** With
`standard = "SDTMIG"`, `AESTDTC = "2024-13-01"` is reported by nothing.
Unfiltered it is caught by `CORE-000547`, which is published for SENDIG,
SENDIG-DART, SENDIG-GENETOX and TIG, but not SDTMIG.

Every SDTMIG rule mentioning ISO 8601 is either scoped to one variable or
withdrawn:

| rule | legacy | covers | |
|---|---|---|---|
| CORE-000294, CORE-000504, CORE-000506 | CG0171, CG0283, CG0286 | `TSVAL` only | published |
| CORE-000730, CORE-000731 | CG0438, CG0439 | `TSVAL` only | deprecated |
| CORE-000779 | CG0376 | `TDSTOFF` only | deprecated |

The other SDTMIG date rules are about relationships ("falls after `RFPENDTC`")
or variable presence, never format. A relationship rule cannot rescue this:
comparing against an unparseable date yields FALSE, so a malformed value slips
through those too.

This is a gap in CORE's metadata, not a position that SDTM dates need no format
check. FDA requires ISO 8601 with at minimum year, month and day, and a valid
ISO 8601 study start date under the Technical Rejection Criteria. SDTMIG itself
requires ISO 8601 for `--DTC`.

coreval changes nothing about the rules. Inventing an SDTMIG applicability for
CORE-000547 would be the fabrication this package refuses everywhere else: that
rule's own metadata says it is not an SDTMIG rule. Instead the report prints how
many rules the standard filter set aside, and the documentation warns that
narrowing can stop a real problem being reported.

**Worth raising upstream:** is CORE-000547's omission of SDTMIG deliberate, or
an oversight left when CG0438/CG0439 were deprecated without an SDTMIG
successor? If the latter, the fix belongs upstream and coreval picks it up on
the next rules rebuild.

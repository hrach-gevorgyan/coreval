# Decisions

Choices that shaped the package, with the reasoning. Recorded so they aren't
silently re-litigated or accidentally reversed.

---

## Rules are data; operators are code

Every rule is driven by a data-defined registry (`inst/extdata/rules.rds`) plus
generic operator implementations. **Never write a per-rule check function.** If a
change requires touching R code to add a *rule*, something is wrong, only a
new *operator* justifies new code.

## No Python, no network, no `reticulate` at runtime

Rules ship inside the package as data, extracted at build time from a pinned
upstream commit. A user running `check_study()` needs no internet and no Python.

## Runtime imports stay at `data.table` + `haven`

`yaml` and `xml2` are build-time or `Suggests` only. `xml2` *is* used at runtime
by the define.xml reader, but reached through `requireNamespace()` so support
degrades gracefully when it's absent. **Do not promote it to `Imports`.**

## `data.table`, not `dplyr`, inside the evaluation loop

Per-rule evaluation runs across every domain of a study; the loop is hot.

## Load every domain once per study

Never re-read files per rule.

## Never fake a pass, and never fabricate a finding

A rule that cannot be evaluated is reported as **skipped, with a reason**, never
as a pass, and never as a confident finding.

This turned out to be the single most valuable rule in the project. Trap 1's
"not a real column → literal text" fallback means any pseudo-column we can't
supply silently becomes a literal string, so a comparison like
`variable_label != "define_variable_label"` is true for *every* row, in the
conformant and non-conformant case alike. Three rules sat in the FAIL column
doing exactly that before a guard was added. Guard on the **built dataset**, not
a hard-coded rule-type list, so supplying the data later disables the guard
automatically.

## Two conformance denominators are reported, always

81 rules ship no reference output at all and can neither pass nor fail. Counting
them as failures understates conformance by ~10 points; hiding them overstates
it. Report both, and say which is which.

## The conformance harness is the oracle: but only for what it covers

Prefer a differential test against CDISC's own `results.csv` over hand-reasoning
about whether an operator is "obviously correct."

**But treat the pass rate as a lower bound on defects, not a readiness signal.**
The fixtures are almost entirely unsplit datasets, so whole classes of real-world
input aren't exercised. A bug that silently disabled a third of the rule set on
split-domain studies produced *no* change in the pass rate. Two other real fixes
likewise moved it by zero.

## Deprecated and draft rules are a lower-value pool

163 of the bundled rules come from `Deprecated/`, and they account for roughly
half the failures. Their fixtures predate current engine conventions, several
number records counting the CSV header row (one cites record 5 in a four-row
file). Treat a deprecated failure as presumed-stale until shown otherwise, and
prioritise Published rules.

## Verify every sub-agent claim about the reference engine

Sub-agents investigating upstream can read a *different* cached snapshot than the
pinned commit this project uses. Every claim of the form "the reference does X"
must be checked against the pinned source before acting on it. This has caught
real errors, including one agent overstating a bug's severity.

## Test fixtures come from real upstream data

Copied verbatim from the upstream clone rather than hand-authored, so a test
can't drift into asserting our own misunderstanding. Bundled copies rename
`.env` to `_env`, see the note below.

## `.env` → `_env` in bundled fixtures

`R CMD check` flags shipped dot-files. Excluding them via `.Rbuildignore` (tried
first) silently broke every fixture-based test that depends on the declared
standard: under `devtools::test()` the file is read from the source tree and
works, but under `R CMD check` it's missing and `read_study()` quietly defaults
to "no declared standard". Tests kept passing, against silently wrong data.

**A "0 notes" check achieved by excluding files from the build is not the same as
a correct build.** Always verify that what got dropped does not matter.

## Controlled Terminology ships, and the version is never guessed (reversed 2026-09-13)

**This reverses the 2026-09-02 decision to leave CT out.** That decision rested
on a number that was wrong: CDISC's terminology caches are 438 MB, so bundling
looked impossible. Almost all of that is definitions, synonyms and preferred
terms no rule asks for. What conformance needs is the codelist and term
submission values, their C-codes, and the extensible flag. For **every one of
the 206 published packages** that is 0.54 MB, because consecutive releases are
nearly identical and xz collapses the repetition.

The lesson is worth more than the megabytes: the blocker was never measured,
only assumed, and it stood for weeks.

Which version to use is not coreval's choice. Terminology moves between
releases: `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`. Judging a study
against a version it never declared would invent violations and hide real ones.
So the version comes from the study's own TS (`TSVCDREF` names the publisher,
`TSVCDVER` the version), and `ct_package` is the override for setting it by
hand. With neither, those rules skip and say so. CDISC's engine takes the same
position: its `-ct` is required and it errors without one.

Preferred terms are deliberately not bundled. No rule asks for
`returntype: pref_term`, and carrying them doubles both the file and its
in-memory size. A rule that ever needs one is skipped with a reason rather than
answered from data that is not there.

## `Depends: R (>= 4.1)` stays, though nothing needs it (decided 2026-09-12)

A pre-release audit noted the floor is stricter than the code requires, and
that is true: there is no native pipe and no lambda shorthand anywhere in
`R/` (checked mechanically), `data.table` needs only R >= 3.4 and `haven`
R >= 3.6.

It stays at 4.1 anyway. The only R available here is 4.6, so lowering the
floor would claim compatibility that has never been executed - and a subtle
base-R behaviour difference would then fail in a user's session rather than in
a check. R 4.1 is from May 2021; the users this excludes are vanishingly few,
and the cost of being wrong is higher than the cost of being conservative.

Revisit only with a real multi-version check (R-hub can do 4.0/oldrel), not by
reasoning about it.

## Tracking state between runs is deferred, not forgotten

Two requested features both need something coreval has never had, state
carried from one run to the next, and both were deferred by the user:

* **The Excel round trip is one-way.** `write_findings()` writes `Status`,
  `Owner` and `Notes`; nothing reads them back. A finding marked
  "expected, screen failure" therefore reappears at full volume on every
  run, so the noise never decreases for the one user who has already done
  the triage work.
* **No run-to-run comparison.** "What is new since yesterday" cannot be
  answered, which is the question that matters once a study is being cleaned
  iteratively.

They are one problem, not two: both need findings from a previous run to be
identified stably enough to match against the current one, which means a
finding needs an identity beyond its row position. That is the hard part, and
it is why neither is a small addition. Recorded so the gap is visible when
the next release is scoped; not scheduled.

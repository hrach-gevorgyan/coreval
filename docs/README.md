# docs

Four of these are written for anyone reading the repository. One is not.

| file | for |
|---|---|
| [DECISIONS.md](DECISIONS.md) | why coreval is built the way it is, and what has been tried and rejected |
| [REFERENCE-BEHAVIOUR.md](REFERENCE-BEHAVIOUR.md) | how CDISC's own engine actually behaves, with the evidence |
| [COVERAGE.md](COVERAGE.md) | which rules pass, which disagree, and why |
| [BENCHMARKS.md](BENCHMARKS.md) | speed and memory against the reference engine, and how to reproduce it |
| RELEASING.md | the CRAN submission process. Maintainer only. |

Two rules keep these useful:

**No number that moves.** Pass rates, rule counts and timings go stale within a
session. Point at `tests/conformance/scoreboard.csv` instead, or say when a
number was measured and on what.

**No session narrative.** "Found this today", "fixed in this pass", a list of
audits each superseding the last. A finding belongs here stated as durable
fact with its evidence. Progress belongs in `NEWS.md`.

`archive/` holds documents that are no longer true. Nothing there is maintained.

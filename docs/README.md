# docs

These are written for anyone reading the repository.

| file | for |
|---|---|
| [COMPARISON.md](COMPARISON.md) | coreval, CDISC's engine and Verisian's engine side by side: differences, problems and strengths |
| [DECISIONS.md](DECISIONS.md) | why coreval is built the way it is, and what has been tried and rejected |
| [REFERENCE-BEHAVIOUR.md](REFERENCE-BEHAVIOUR.md) | how CDISC's and Verisian's engines actually behave, with the evidence |
| [COVERAGE.md](COVERAGE.md) | which rules pass, which disagree, and why |
| [BENCHMARKS.md](BENCHMARKS.md) | speed and memory against the reference engine, and how to reproduce it |
| [MAINTAINING.md](MAINTAINING.md) | how the package fits together, how to update the rules, and how to release |
| [CHANGES-0.4.0.md](CHANGES-0.4.0.md) | every change in 0.4.0, behind the short notes in `NEWS.md` |
| [REAL-STUDY.md](REAL-STUDY.md) | CDISC's pilot submission checked by coreval and by CORE 1.0's engine, every finding compared |

Two rules keep these useful:

**No number that moves.** Pass rates, rule counts and timings go stale within a
session. Say when a number was measured and on what; the current pass rate
comes from running `tests/conformance/run_conformance.R`.

**No session narrative.** "Found this today", "fixed in this pass", a list of
audits each superseding the last. A finding belongs here stated as durable
fact with its evidence. Progress belongs in `NEWS.md`.

`archive/` holds documents that are no longer true. Nothing there is maintained.

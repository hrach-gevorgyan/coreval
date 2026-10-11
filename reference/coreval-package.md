# coreval: Check Clinical Trial Data Against 'CDISC' Open Rules

Finds conformance problems in clinical trial data without leaving R,
using the openly published 'CDISC' Open Rules ('CORE'). Check a single
dataset while you are still writing the code that builds it, or a whole
study folder once it exists, and get the findings back as a tidy data
frame pointing at the exact row and variable. Reads transport ('XPT'),
'SAS', comma-separated and 'Dataset-JSON' files, plus 'Define-XML' when
present, and 'USDM' study-design documents. Covers rules for the 'SDTM',
'SEND', 'TIG' and 'USDM' standards. The rules are bundled inside the
package, so nothing is downloaded and your data never leaves your
machine: no internet, no API key, no account. When a rule cannot be
checked - because it needs a dataset you did not supply, for instance -
it is reported as skipped with the reason, never counted as a pass.
Meant as a quick first pass before a qualified validation system, never
as a replacement for one. An independent project: not affiliated with or
endorsed by 'CDISC', and not a 'CORE'-certified conformance engine.

## Details

coreval finds CDISC conformance problems in clinical trial data without
leaving R. Run it early and often, while you are still writing the code
that produces the data, so problems turn up while they are cheap to fix.

Two ways in, depending on what you have:

- [`check_dataset()`](https://hrach-gevorgyan.github.io/coreval/reference/check_dataset.md) -
  one dataset, either a data frame you already have open or a single
  file. Use this while writing code.

- [`check_study()`](https://hrach-gevorgyan.github.io/coreval/reference/check_study.md) -
  a whole study folder. Use this once the datasets exist, since the
  cross-dataset rules need everything present.

Both entry points give you two tables, and **both matter**. `$findings`
is what is wrong. `$skipped` is what could not be checked, with a reason
for each. An empty `$findings` can mean clean data *or* rules that never
ran, and those look identical if you only read the first table.

[`write_findings()`](https://hrach-gevorgyan.github.io/coreval/reference/write_findings.md)
saves both to Excel or CSV.
[`vignette("coreval")`](https://hrach-gevorgyan.github.io/coreval/articles/coreval.md)
walks through all of it.

## Status

**coreval is a personal open-source project.** It is not a CDISC
product, is not affiliated with or endorsed by CDISC, and is not
qualified or validated software. The rules are bundled inside the
package, so nothing is downloaded and your data never leaves your
machine: no internet, no API key, no account.

Treat every result as a hint, not a verdict. A qualified validation
system and your own review are still what decide whether data is good to
submit. coreval does not remove that step - it just leaves that step
less to find.

## See also

Useful links:

- <https://hrach-gevorgyan.github.io/coreval/>

- <https://github.com/hrach-gevorgyan/coreval>

- Report bugs at <https://github.com/hrach-gevorgyan/coreval/issues>

## Author

**Maintainer**: Hrach Gevorgyan <hrach.gevorgyan@yandex.com> \[copyright
holder\]

Authors:

- Hrach Gevorgyan <hrach.gevorgyan@yandex.com> \[copyright holder\]

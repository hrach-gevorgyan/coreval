#' @details
#' coreval finds CDISC conformance problems in clinical trial data without
#' leaving R. Run it early and often, while you are still writing the code that
#' produces the data, so problems turn up while they are cheap to fix.
#'
#' Two ways in, depending on what you have:
#'
#' * [check_dataset()] - one dataset, either a data frame you already have open
#'   or a single file. Use this while writing code.
#' * [read_study()] then [check_study()] - a whole study folder. Use this once
#'   the datasets exist, since the cross-dataset rules need everything present.
#'
#' Either way you get back two tables, and **both matter**. `$findings` is what
#' is wrong. `$skipped` is what could not be checked, with a reason for each. An
#' empty `$findings` can mean clean data *or* rules that never ran, and those
#' look identical if you only read the first table.
#'
#' [write_findings()] saves both to Excel or CSV. `vignette("coreval")` walks
#' through all of it.
#'
#' @section Status:
#' **coreval is a personal open-source project.** It is not a CDISC product, is
#' not affiliated with or endorsed by CDISC, and is not qualified or validated
#' software. The rules are bundled inside the package, so nothing is downloaded
#' and your data never leaves your machine: no internet, no API key, no account.
#'
#' Treat every result as a hint, not a verdict. A qualified validation system
#' and your own review are still what decide whether data is good to submit.
#' coreval does not remove that step - it just leaves that step less to find.
#'
#' @keywords internal
"_PACKAGE"

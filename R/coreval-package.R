#' @details
#' `coreval` checks clinical trial datasets against the CDISC Open Rules (CORE)
#' and returns the findings as a tidy data frame. It is meant to be run early
#' and often, while the code that produces the data is still being written, so
#' that problems are found when they are cheap to fix.
#'
#' Start with `vignette("coreval")`. The usual path through the package is
#' [read_study()] to load a study directory, then [check_study()] to evaluate
#' every applicable rule, then [write_findings()] to export the result.
#'
#' [check_study()] returns two tables, and both matter. `$findings` holds the
#' rule violations. `$skipped` holds the rules that could **not** be evaluated,
#' each with a reason. A short `$findings` table on its own is ambiguous — it
#' can mean clean data, or it can mean many rules never ran — so read `$skipped`
#' before concluding anything.
#'
#' @section Status:
#' **coreval is an independent, personal open-source project.** It is not a
#' CDISC product, is not affiliated with or endorsed by CDISC, and is not
#' qualified or validated software. It evaluates a copy of the publicly
#' published CDISC Open Rules, bundled as data from a pinned upstream commit,
#' so that checking a study needs no internet connection, no API key and no
#' external service.
#'
#' Every result is an *indication*, not a certification. A qualified validation
#' system and your own review remain the authority on whether data is
#' submittable. Nothing here removes that step; it only makes that step find
#' less.
#'
#' @keywords internal
"_PACKAGE"

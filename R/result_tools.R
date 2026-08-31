# Small tools for working with a result, so the common questions do not each
# need a hand-written subset() over $findings.

#' Rebuild a result around a subset of its findings
#'
#' Keeps the class and the attributes the report reads, so a filtered result
#' still prints as a report rather than as a bare list.
#'
#' @param result The original result.
#' @param findings The findings to keep.
#' @return A `coreval_result`.
#' @noRd
respin_result <- function(result, findings) {
  kept <- unique(paste(findings$Dataset, findings$rule_id))
  truncated <- result$truncated
  if (!is.null(truncated) && nrow(truncated) > 0) {
    truncated <- truncated[paste(truncated$domain, truncated$rule_id) %in% kept, ]
  }
  structure(
    list(findings = findings, skipped = result$skipped, truncated = truncated),
    class = "coreval_result",
    checks_run = attr(result, "checks_run"),
    domains = attr(result, "domains"),
    standard = attr(result, "standard"),
    excluded_by_standard = attr(result, "excluded_by_standard"),
    # So the report can say it is a subset. A filtered report otherwise looks
    # exactly like a full one, and a screenshot of "2 problems" would read as
    # the whole picture.
    filtered = TRUE
  )
}

#' Narrow a result to the findings you care about
#'
#' Saves writing `subset()` over `$findings` by hand, and - because it returns
#' a result rather than a plain table - what comes back still prints as a
#' readable report.
#'
#' @param result A result from [check_dataset()] or [check_study()].
#' @param triage Keep only these triage levels, e.g. `"wrong value"`. See
#'   [print.coreval_result()] for what the levels mean.
#' @param dataset Keep only these datasets, e.g. `"AE"`.
#' @param rule Keep only these rule ids, e.g. `"CORE-000547"`.
#' @param variable Keep only findings naming these variables.
#' @return A `coreval_result` holding the matching findings. `$skipped` is
#'   left alone: what could not be checked does not become less true because
#'   you narrowed what you are looking at.
#' @examples
#' ae <- data.frame(
#'   STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
#'   AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
#'   AESTDTC = c("2024-01-10", "2024-02-30")
#' )
#' result <- check_dataset(ae)
#'
#' # Just the things that are definitely wrong:
#' filter_findings(result, triage = "wrong value")
#' @export
filter_findings <- function(result, triage = NULL, dataset = NULL,
                            rule = NULL, variable = NULL) {
  if (!inherits(result, "coreval_result")) {
    stop(
      "`result` must be what check_dataset() or check_study() returned.",
      call. = FALSE
    )
  }
  f <- result$findings
  keep <- rep(TRUE, nrow(f))

  if (!is.null(triage)) {
    unknown <- setdiff(triage, TRIAGE_LEVELS)
    if (length(unknown) > 0) {
      stop(
        "no such triage level: ", paste(unknown, collapse = ", "),
        ". Use one of: ", paste(TRIAGE_LEVELS, collapse = ", "),
        call. = FALSE
      )
    }
    keep <- keep & f$triage %in% triage
  }
  if (!is.null(dataset)) keep <- keep & f$Dataset %in% toupper(dataset)
  if (!is.null(rule)) keep <- keep & f$rule_id %in% rule
  if (!is.null(variable)) keep <- keep & f$Variable %in% variable

  respin_result(result, f[keep, ])
}

#' Summarize a check result in a few lines
#'
#' The short form of [print.coreval_result()], for when you have run a check
#' inside a script, or just want to know whether the last fix helped.
#'
#' @param object A result from [check_dataset()] or [check_study()].
#' @param ... Ignored.
#' @return A one-row [data.table::data.table()], invisibly, with the counts it
#'   printed - so it can be logged or compared.
#' @examples
#' ae <- data.frame(
#'   STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
#'   AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
#'   AESTDTC = c("2024-01-10", "2024-02-30")
#' )
#' summary(check_dataset(ae))
#' @export
summary.coreval_result <- function(object, ...) {
  f <- object$findings
  per_problem <- unique(f[, c("Dataset", "rule_id", "triage")])
  counts <- table(factor(per_problem$triage, levels = TRIAGE_LEVELS))

  truncated <- object$truncated
  n_capped <- if (is.null(truncated)) 0L else nrow(truncated)

  out <- data.table::data.table(
    problems = nrow(per_problem),
    records = if (nrow(f) == 0) 0L else nrow(unique(f[, c("Dataset", "Record")])),
    wrong_value = as.integer(counts[["wrong value"]]),
    missing_required = as.integer(counts[["missing required"]]),
    missing_optional = as.integer(counts[["missing optional"]]),
    checks_run = attr(object, "checks_run") %||% NA_integer_,
    could_not_run = nrow(object$skipped),
    # `records` counts what was KEPT. Where a rule matched more records than
    # max_records allowed, that number is a floor rather than the truth, and
    # presenting a floor as a total is exactly the quiet under-reporting this
    # package exists to avoid.
    capped_rules = n_capped
  )

  cat(
    out$problems, if (out$problems == 1) " problem" else " problems",
    " across ", out$records, if (out$records == 1) " record" else " records",
    if (n_capped > 0) " or more" else "",
    "  (", out$checks_run, " checks ran, ", out$could_not_run, " could not)\n",
    sep = ""
  )
  if (isTRUE(attr(object, "filtered"))) {
    cat("  (filtered - a subset of the full result)\n")
  }
  if (n_capped > 0) {
    cat(
      "  ", n_capped, if (n_capped == 1) " problem affects" else " problems affect",
      " more records than were kept (up to ", max(truncated$records_found),
      ") - see $truncated\n",
      sep = ""
    )
  }
  for (lvl in TRIAGE_LEVELS) {
    n <- as.integer(counts[[lvl]])
    if (n > 0) cat(sprintf("  %-17s %d\n", lvl, n))
  }
  invisible(out)
}

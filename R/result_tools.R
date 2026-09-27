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
    # A study-level cap (a USDM document rule) is recorded under STUDY while
    # its findings name the entity table, so it is matched on the rule too.
    keep <- paste(truncated$domain, truncated$rule_id) %in% kept |
      (truncated$domain == "STUDY" & truncated$rule_id %in% findings$rule_id)
    truncated <- truncated[keep, ]
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
#' @param triage Keep only these triage levels. One or more of:
#'   * `"wrong value"` - the data contains something that breaks the rule, like
#'     a month of 13. Nothing about your study explains it away. Start here.
#'   * `"missing required"` - something the standard marks Required is absent.
#'   * `"missing optional"` - something Expected is absent, or a value is
#'     blank. Often legitimate: a screen-failure subject with no reference
#'     dates, a variable your raw data does not carry yet.
#'
#'   These are coreval's own triage, not a CDISC severity: the rules carry no
#'   severity field, and this does not map onto anyone's scale.
#' @param dataset Keep only these datasets, e.g. `"AE"`.
#' @param rule Keep only these rule ids, e.g. `"CORE-000547"`.
#' @param variable Keep only findings naming these variables, including a
#'   finding that lists the variable as missing (a Required variable the
#'   dataset lacks).
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
  # Refused rather than matched: a typo, NA or a number used to match nothing
  # and read as "no findings of that kind".
  text_arg <- function(x, name) {
    if (!is.null(x) && (!is.character(x) || length(x) == 0 || anyNA(x) || any(!nzchar(x)))) {
      stop("`", name, "` must be one or more names, e.g. ",
           switch(name, dataset = "\"AE\"", rule = "\"CORE-000547\"", "\"AESTDTC\""),
           ".", call. = FALSE)
    }
    if (is.null(x)) NULL else toupper(trimws(x))
  }
  dataset <- text_arg(dataset, "dataset")
  rule <- text_arg(rule, "rule")
  variable <- text_arg(variable, "variable")
  if (!is.null(dataset)) keep <- keep & f$Dataset %in% dataset
  if (!is.null(rule)) keep <- keep & f$rule_id %in% rule
  if (!is.null(variable)) {
    # A rule comparing sets of variables reports the missing names inside one
    # finding ("$required_variables = ['AEDECOD']"), so a variable is looked
    # for there too. Matched on Variable alone, asking about AEDECOD answered
    # "no findings" while the report listed it as a missing Required variable.
    keep <- keep & (f$Variable %in% variable | names_missing(f, variable))
  }

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
  assert_coreval_result(object, "object")
  f <- object$findings
  per_problem <- unique(f[, c("Dataset", "rule_id", "triage")])
  counts <- table(factor(per_problem$triage, levels = TRIAGE_LEVELS))

  truncated <- object$truncated
  n_capped <- if (is.null(truncated)) 0L else nrow(truncated)

  out <- data.table::data.table(
    problems = nrow(per_problem),
    records = count_records(f),
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

#' Refuse an object that carries the class but not the contents
#'
#' `print()` and `summary()` both index `$findings` and `$skipped` straight
#' away, so a malformed object failed with base R's "argument is of length
#' zero" - after the banner had already printed, which reads like a bug in
#' the report rather than a bad input.
#'
#' @param x The object to check.
#' @param arg Argument name to name in the message.
#' @return `invisible(NULL)`; raises an error when `x` is not a result.
#' @noRd
assert_coreval_result <- function(x, arg = "x") {
  needed <- c("findings", "skipped")
  if (!is.list(x) || !all(needed %in% names(x))) {
    stop(
      "`", arg, "` is not a coreval result: it has no ",
      paste(setdiff(needed, names(x)), collapse = " or "), " table. ",
      "Results come from check_dataset() or check_study().",
      call. = FALSE
    )
  }
  invisible(NULL)
}


#' Which findings report one of these variables as missing
#'
#' The rules that compare the standard's variables with the dataset's report
#' both sets, and what is missing is the difference, the same arithmetic the
#' printed report does ([binding_gap()]).
#'
#' @param f Findings.
#' @param variable Upper-case variable names.
#' @return A logical vector, one per finding row.
#' @noRd
names_missing <- function(f, variable) {
  out <- rep(FALSE, nrow(f))
  binds <- which(startsWith(f$Variable, "$"))
  if (length(binds) == 0) {
    return(out)
  }
  key <- paste(f$Dataset, f$rule_id, f$Record)
  for (k in unique(key[binds])) {
    rows <- binds[key[binds] == k]
    sets <- lapply(f$Value[rows], parse_set_value)
    names(sets) <- f$Variable[rows]
    gap <- binding_gap(sets)
    if (!is.null(gap) && any(toupper(gap$missing) %in% variable)) {
      out[key == k] <- TRUE
    }
  }
  out
}

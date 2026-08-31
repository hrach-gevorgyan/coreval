#' CDISC Open Rules upstream commit
#'
#' @return A single string: the git commit SHA of `cdisc-org/cdisc-open-rules`
#'   that the bundled rule set was extracted from.
#' @examples
#' rules_version()
#' @export
rules_version <- function() {
  .coreval_env$data$upstream_sha
}

#' List available CORE rules
#'
#' `source` distinguishes where a rule came from in the upstream repository,
#' since not all of them carry the same level of trust:
#' * `"published"` - `Published/`, `Core$Status == "Published"`, fully tested.
#' * `"deprecated_dir"` - `Deprecated/`, `Core$Status == "Published"` with full
#'   test data, but upstream's own README says these SDTM-only rules are
#'   temporarily parked there during unrelated integration work and are
#'   "not fully validated."
#' * `"fda_business_rules_draft"` - `Unpublished/FDA Business Rules/`,
#'   `Core$Status == "Draft"`. Only rules that already ship test data are
#'   included.
#'
#' @return A [data.table::data.table()] with one row per rule: `id`,
#'   `source`, `status`, `standard`, `authority`, `rule_type`,
#'   `executability`, `sensitivity`.
#' @examples
#' rules <- list_rules()
#' nrow(rules)
#' head(rules)
#' @export
list_rules <- function() {
  rules <- .coreval_env$data$rules
  data.table::rbindlist(lapply(rules, function(r) {
    data.table::data.table(
      id = r$id,
      # What the rule is actually about. Without this the table could tell you
      # a rule's sensitivity and executability but not what it CHECKS, so a
      # report saying "CORE-000547" could not be resolved from within R at all.
      issue = rule_message(r),
      source = r$source,
      status = r$status,
      standard = paste(r$standards, collapse = ", "),
      authority = paste(r$authorities, collapse = ", "),
      rule_type = r$rule_type,
      executability = r$executability,
      sensitivity = r$sensitivity
    )
  }))
}

#' Look up what a rule checks
#'
#' The report gives you a rule id such as `CORE-000547`. This tells you what it
#' means, without leaving R or opening a CDISC spreadsheet.
#'
#' @param id One or more rule ids, e.g. `"CORE-000547"`.
#' @return A [data.table::data.table()] with one row per rule: its `id`, the
#'   one-line `issue` it reports, the fuller `description`, which `standard`s
#'   and `authority` it comes from, its `rule_type` and `sensitivity`, and
#'   whether it is `published`, `deprecated` or draft (`source`).
#' @examples
#' rule_info("CORE-000547")
#'
#' # Look up everything a result reported:
#' # rule_info(unique(result$findings$rule_id))
#' @seealso [list_rules()] for the whole rule set, [rules_for_domain()] for the
#'   rules that apply to one domain.
#' @export
rule_info <- function(id) {
  known <- .coreval_env$data$rules
  missing <- setdiff(id, names(known))
  if (length(missing) > 0) {
    stop(
      "no such rule: ", paste(missing, collapse = ", "),
      ". Rule ids look like \"CORE-000547\"; see list_rules() for all of them.",
      call. = FALSE
    )
  }
  data.table::rbindlist(lapply(known[id], function(r) {
    data.table::data.table(
      id = r$id,
      issue = rule_message(r),
      description = if (is.null(r$description)) NA_character_ else r$description,
      standard = paste(r$standards, collapse = ", "),
      authority = paste(r$authorities, collapse = ", "),
      rule_type = r$rule_type,
      sensitivity = r$sensitivity,
      source = r$source
    )
  }))
}

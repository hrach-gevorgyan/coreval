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

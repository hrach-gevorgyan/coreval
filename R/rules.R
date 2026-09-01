#' CDISC Open Rules upstream commit
#'
#' Internal. Reachable as `attr(list_rules(), "rules_version")`, and written
#' into every exported file's `about` sheet by [write_findings()] - which is
#' where it matters, since the point of recording it is to say which snapshot
#' of CDISC's rules produced a given set of results.
#'
#' @return A single string: the git commit SHA of `cdisc-org/cdisc-open-rules`
#'   that the bundled rule set was extracted from.
#' @noRd
rules_version <- function() {
  .coreval_env$data$upstream_sha
}

#' Build the full rule table, one row per bundled rule
#' @return A [data.table::data.table()] with the columns [list_rules()] documents.
#' @noRd
build_rules_table <- function() {
  rules <- .coreval_env$data$rules
  data.table::rbindlist(lapply(rules, function(r) {
    data.table::data.table(
      id = r$id,
      # What the rule is actually about. Without this the table could tell you
      # a rule's sensitivity and executability but not what it CHECKS, so a
      # report saying "CORE-000547" could not be resolved from within R at all.
      issue = rule_message(r),
      description = if (is.null(r$description)) NA_character_ else r$description,
      # The sentence from the Implementation Guide the rule enforces - the
      # "why", which no rule message carries.
      guidance = if (length(r$citations)) r$citations[1] else NA_character_,
      # What Pinnacle 21 and the published Conformance Rules spreadsheets call
      # this same rule, which is how a finding here is matched to one there.
      legacy_ids = paste(r$legacy_ids, collapse = ", "),
      standard = paste(r$standards, collapse = ", "),
      standard_version = paste(r$standard_versions, collapse = ", "),
      authority = paste(r$authorities, collapse = ", "),
      rule_type = r$rule_type,
      sensitivity = r$sensitivity,
      executability = r$executability,
      source = r$source,
      status = r$status
    )
  }))
}

#' Look up CORE rules
#'
#' One way in for every question about the rule set: what rules exist, what a
#' particular one checks, and which of them apply to a domain.
#'
#' The columns are the same whatever you ask for, so the result is safe to
#' filter, join and script against.
#'
#' @section What `source` tells you:
#' Not every bundled rule carries the same weight:
#' * `"published"` - `Published/` upstream, fully tested. The trusted core.
#' * `"deprecated_dir"` - superseded by a published replacement. Not returned
#'   unless you ask for it, since running both reports the same defect twice.
#' * `"fda_business_rules_draft"` - FDA drafts that already ship test data.
#'
#' @param id Return only these rules, e.g. `"CORE-000547"`. This is how you
#'   look up a rule id the report gave you.
#' @param domain Return only rules that apply to this domain, e.g. `"AE"`,
#'   resolving each rule's `Scope > Classes` and `Scope > Domains`.
#' @param standard Return only rules for this standard, e.g. `"SDTMIG"`.
#'   Matched exactly, so `"SENDIG"` does not pick up `"SENDIG-DART"`.
#' @param version The standard's version, e.g. `"3.4"` (or `"3-4"`). Only
#'   narrows alongside `standard`, since a bare version is ambiguous across
#'   standards.
#' @param use_case Optional use case (e.g. `"INDH"`). Rules with no Use Case
#'   constraint always pass.
#' @param include_deprecated Include superseded rules. `TRUE` here, unlike
#'   [check_dataset()] and [check_study()], which default to `FALSE`. The
#'   difference is deliberate: **listing is not running**. This function is the
#'   catalog of what is bundled, so hiding a fifth of it would make
#'   `nrow(list_rules())` stop meaning "how many rules are there" - and `source`
#'   is right here to filter on. Checking is a different question, and there a
#'   superseded rule would report the same defect twice.
#'   Pass `FALSE` to see exactly what would run.
#' @return A [data.table::data.table()], one row per rule: `id`, the one-line
#'   `issue` it reports, its fuller `description`, the `guidance` sentence
#'   from the Implementation Guide it enforces, the `legacy_ids` Pinnacle 21
#'   uses for it, `standard` and `standard_version`, `authority`, `rule_type`,
#'   `sensitivity`, `executability`, `source` and `status`.
#'
#'   The commit the bundled rules came from is on the result as
#'   `attr(x, "rules_version")`; [write_findings()] records it in every
#'   exported file.
#' @examples
#' # Everything
#' nrow(list_rules())
#'
#' # What does the rule the report just named actually check?
#' list_rules(id = "CORE-000547")$issue
#'
#' # What applies to AE under SDTMIG 3.4?
#' nrow(list_rules(domain = "AE", standard = "SDTMIG", version = "3.4"))
#'
#' # Which snapshot of CDISC's rules is this?
#' attr(list_rules(), "rules_version")
#' @export
list_rules <- function(id = NULL, domain = NULL, standard = NULL,
                       version = NULL, use_case = NULL,
                       include_deprecated = TRUE) {
  out <- build_rules_table()

  # Looking up an id is a different question from "what would run": it should
  # answer even for a deprecated rule, or one outside the standard in play,
  # because the report may well have named it. So it short-circuits the
  # scoping filters rather than being narrowed by them.
  if (!is.null(id)) {
    unknown <- setdiff(id, out$id)
    if (length(unknown) > 0) {
      stop(
        "no such rule: ", paste(unknown, collapse = ", "),
        '. Rule ids look like "CORE-000547"; list_rules() returns all of them.',
        call. = FALSE
      )
    }
    # Returned in the order asked for, so this composes with a result's own
    # rule ids.
    #
    # The index is computed OUTSIDE the `[`. data.table evaluates `i` with the
    # table's own columns in scope, and this table has a column called `id` -
    # so `out[match(id, out$id), ]` silently becomes
    # `match(out$id, out$id)`, which is 1:756, and every rule comes back
    # instead of the one asked for. Naming the index something no column
    # shares removes the collision.
    wanted <- match(id, out$id)
    out <- out[wanted, ]
    data.table::setattr(out, "rules_version", rules_version())
    return(out)
  }

  if (!is.null(domain)) {
    # Asking about a domain implies asking what would RUN against it, so the
    # same scoping check_dataset() uses applies here - otherwise the two would
    # disagree about which rules apply, which is worse than either answer.
    scoped <- rules_for_domain(
      domain,
      use_case = use_case, standard = standard, version = version,
      include_deprecated = include_deprecated
    )
    out <- out[out$id %in% scoped$id, ]
  } else {
    if (!is.null(standard)) {
      want <- toupper(standard)
      keep <- vapply(out$standard, function(s) {
        want %in% toupper(trimws(strsplit(s, ",")[[1]]))
      }, logical(1))
      if (!is.null(version)) {
        pair <- toupper(paste(standard, gsub("-", ".", version, fixed = TRUE)))
        keep <- keep & vapply(out$standard_version, function(s) {
          pair %in% toupper(trimws(strsplit(s, ",")[[1]]))
        }, logical(1))
      }
      out <- out[keep, ]
    }
    if (!isTRUE(include_deprecated)) {
      out <- out[out$source != "deprecated_dir", ]
    }
  }

  data.table::setattr(out, "rules_version", rules_version())
  out
}

# Does `pattern` (a value from a Scope Domains Include/Exclude list) match
# `domain`? Handles the two sentinels ("ALL", "NONE") and the "XX--" prefix
# wildcard (e.g. "SUPP--" matches "SUPPAE", "SUPPDM"; "AP--" matches "APDM").
pattern_matches_domain <- function(pattern, domain) {
  pattern <- toupper(pattern)
  domain <- toupper(domain)
  if (pattern == "ALL") {
    return(TRUE)
  }
  if (pattern == "NONE") {
    return(FALSE)
  }
  if (endsWith(pattern, "--")) {
    prefix <- substr(pattern, 1, nchar(pattern) - 2)
    return(startsWith(domain, prefix))
  }
  identical(domain, pattern)
}

# Shared Include/Exclude resolution for both Classes and Domains scope
# blocks. `matches_fn(pattern)` tests one Include/Exclude list entry against
# whatever value the caller is checking (a domain code, or a class name).
include_exclude_matches <- function(spec, matches_fn) {
  if (is.null(spec)) {
    return(TRUE)
  }
  if (!is.null(spec$Include) && !any(vapply(spec$Include, matches_fn, logical(1)))) {
    return(FALSE)
  }
  if (!is.null(spec$Exclude) && any(vapply(spec$Exclude, matches_fn, logical(1)))) {
    return(FALSE)
  }
  TRUE
}

domain_class <- function(domain) {
  domain <- toupper(domain)
  tbl <- .coreval_env$domain_classes
  idx <- match(domain, tbl$domain)
  if (!is.na(idx)) {
    return(tbl$class[idx])
  }
  # Every SUPPxx dataset (SUPPAE, SUPPDM, ...) follows the SUPPQUAL template
  # and is not individually listed in the domain/class table, since it's
  # generated per parent domain rather than being a fixed domain itself.
  if (startsWith(domain, "SUPP") && nchar(domain) > 4) {
    return("RELATIONSHIP")
  }
  NA_character_
}

class_matches <- function(classes_spec, domain) {
  cls <- domain_class(domain)
  include_exclude_matches(classes_spec, function(pattern) {
    if (toupper(pattern) == "ALL") {
      return(TRUE)
    }
    !is.na(cls) && identical(toupper(cls), toupper(pattern))
  })
}

domains_match <- function(domains_spec, domain) {
  include_exclude_matches(domains_spec, function(pattern) pattern_matches_domain(pattern, domain))
}

rule_applies_to_domain <- function(rule, domain, use_case = NULL) {
  scope <- rule$scope
  if (!is.null(scope$Classes) && !class_matches(scope$Classes, domain)) {
    return(FALSE)
  }
  if (!is.null(scope$Domains) && !domains_match(scope$Domains, domain)) {
    return(FALSE)
  }
  if (!is.null(use_case) && !is.null(scope[["Use Case"]])) {
    allowed <- trimws(strsplit(scope[["Use Case"]], ",")[[1]])
    if (!(use_case %in% allowed)) {
      return(FALSE)
    }
  }
  TRUE
}

#' SDTM domain to observation-class reference table
#'
#' The static SDTMIG 3.4 domain/class assignments used to resolve a rule's
#' `Scope > Classes` (e.g. `"FINDINGS"`) against an actual domain code (e.g.
#' `"LB"`). See `data-raw/domain_classes.R` for provenance.
#'
#' @return A [data.table::data.table()] with columns `domain`, `class`.
#' @export
sdtm_domain_classes <- function() {
  data.table::as.data.table(.coreval_env$domain_classes)
}

#' Rules that apply to a given SDTM domain
#'
#' Resolves each rule's `Scope > Classes` and `Scope > Domains` (handling the
#' `"ALL"`/`"NONE"` sentinels and `"XX--"` prefix wildcards) against `domain`.
#'
#' Dynamically-named domains not in [sdtm_domain_classes()] (e.g. `SUPPAE`,
#' `SUPPDM`) resolve to the `RELATIONSHIP` class, since every `SUPPxx`
#' dataset follows the `SUPPQUAL` template. Associated Persons domains
#' (`APxx`) currently have no class resolution - as of this writing no
#' bundled rule pairs an `AP--` domain with a specific (non-`"ALL"`) Classes
#' constraint, so this is a known gap rather than a fix, should that change
#' upstream.
#'
#' @param domain Domain code, e.g. `"AE"`.
#' @param use_case Optional use case (e.g. `"INDH"`). When supplied, also
#'   filters out rules whose `Scope > Use Case` doesn't include it. Rules
#'   with no Use Case constraint always pass, regardless of this argument.
#' @return A [data.table::data.table()] with the same columns as
#'   [list_rules()], filtered to matching rules.
#' @export
rules_for_domain <- function(domain, use_case = NULL) {
  rules <- .coreval_env$data$rules
  keep <- vapply(
    rules, rule_applies_to_domain, logical(1),
    domain = domain, use_case = use_case
  )
  ids <- vapply(rules[keep], function(r) r$id, character(1))
  rules_table <- list_rules()
  rules_table[rules_table$id %in% ids, ]
}

# Does `pattern` (a value from a Scope Domains Include/Exclude list) match
# `domain`? Handles the two sentinels ("ALL", "NONE") and the "XX--" prefix
# wildcard (e.g. "SUPP--" matches "SUPPAE", "SUPPDM"; "AP--" matches "APDM").
#' Test whether a Scope Domains pattern matches a domain code
#' @param pattern One Include/Exclude entry (e.g. `"ALL"`, `"SUPP--"`).
#' @param domain Domain code to test.
#' @return A single logical.
#' @noRd
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
#' Resolve a Scope Include/Exclude block against a single value
#' @param spec A `list(Include, Exclude)` scope block, or `NULL` (matches everything).
#' @param matches_fn Function of one pattern, returning a logical.
#' @return A single logical: whether the value passes this Include/Exclude spec.
#' @noRd
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

#' Look up a domain's SDTMIG observation class
#' @param domain Domain code, e.g. `"AE"`.
#' @return A single class name, or `NA_character_` if unknown.
#' @noRd
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
  # An Associated Persons dataset (APEG, APQS, ...) holds the same kind of
  # observation as the domain it is associated with, so it takes that
  # domain's class - APEG is Findings exactly as EG is. Like SUPPxx these are
  # generated per parent domain and never listed individually. APID is an
  # identifier variable, not a domain prefix, so it is excluded here for the
  # same reason resolve_var_name() excludes it.
  if (startsWith(domain, "AP") && nchar(domain) > 2 && !startsWith(domain, "APID")) {
    return(domain_class(substring(domain, 3)))
  }
  NA_character_
}

#' Test a rule's Scope > Classes block against a domain
#' @param classes_spec The rule's `scope$Classes` Include/Exclude block.
#' @param domain Domain code to test.
#' @return A single logical.
#' @noRd
class_matches <- function(classes_spec, domain) {
  cls <- domain_class(domain)
  include_exclude_matches(classes_spec, function(pattern) {
    if (toupper(pattern) == "ALL") {
      return(TRUE)
    }
    !is.na(cls) && identical(toupper(cls), toupper(pattern))
  })
}

#' Test a rule's Scope > Domains block against a domain
#' @param domains_spec The rule's `scope$Domains` Include/Exclude block.
#' @param domain Domain code to test.
#' @return A single logical.
#' @noRd
domains_match <- function(domains_spec, domain) {
  include_exclude_matches(domains_spec, function(pattern) pattern_matches_domain(pattern, domain))
}

#' Test whether a rule's full Scope (Classes, Domains, Use Case) applies to a domain
#' @param rule A rule record.
#' @param domain Domain code to test.
#' @param use_case Optional use case to also filter on.
#' @return A single logical.
#' @noRd
rule_applies_to_domain <- function(rule, domain, use_case = NULL, dataset = NULL) {
  scope <- rule$scope
  # `Domains: Include: [ALL]` alongside a narrower `Classes` filter does NOT
  # widen scope to every domain: both still have to match. Tested directly -
  # letting Domains=ALL override Classes turns CORE-000794/847/848 green but
  # breaks 11 other rules, a net loss of 8. Whatever the reference does for
  # those three, it is not this. 121 of the 797 rules pair the two, so do not
  # retry this without measuring the whole sweep.
  if (!is.null(scope$Classes) && !class_matches(scope$Classes, domain)) {
    return(FALSE)
  }
  if (!is.null(scope$Domains) && !domains_match(scope$Domains, domain)) {
    return(FALSE)
  }
  # `include_split_datasets` narrows or widens scope by whether the dataset
  # is one FILE of a domain split across several, which is a property of
  # the data (its DOMAIN column), not of the name - so it can only be
  # evaluated when the dataset itself is available. Per the reference's
  # _is_domain_name_included / _handle_split_domains: TRUE with no Include
  # list means "only split datasets"; TRUE with one ADDS split datasets to
  # whatever the list already matched; FALSE excludes split datasets
  # outright; absent does nothing.
  include_split <- scope$Domains[["include_split_datasets"]]
  if (!is.null(include_split) && !is.null(dataset)) {
    split <- dataset_is_split(dataset, domain)
    if (isTRUE(include_split) && !split && length(scope$Domains$Include) == 0) {
      return(FALSE)
    }
    if (identical(include_split, FALSE) && split) {
      return(FALSE)
    }
  }
  if (!is.null(use_case) && !is.null(scope[["Use Case"]])) {
    allowed <- trimws(strsplit(scope[["Use Case"]], ",")[[1]])
    if (!(use_case %in% allowed)) {
      return(FALSE)
    }
  }
  TRUE
}

#' Domain to observation-class reference table
#'
#' Maps a domain code (e.g. `"LB"`) to its observation class (e.g.
#' `"FINDINGS"`), which is how a rule's `Scope > Classes` is resolved against
#' real data.
#'
#' A domain's class is stable across Implementation Guide versions — `LB` is a
#' Findings domain in every version of SDTMIG — so one table serves all of
#' them. It covers the SDTM domains plus the SEND-specific ones (`BW`, `MA`,
#' `TF`, ...), so SDTMIG, SENDIG and TIG rules all resolve. See
#' `data-raw/domain_classes.R` for provenance.
#'
#' Internal. It answers a question nobody working with their own data has -
#' anyone who needs to know LB is a Findings domain already knows - and exists
#' only so `Scope > Classes` can be resolved.
#'
#' @return A [data.table::data.table()] with columns `domain`, `class`.
#' @noRd
sdtm_domain_classes <- function() {
  data.table::as.data.table(.coreval_env$domain_classes)
}

#' Rules that apply to a given SDTM domain
#'
#' Resolves each rule's `Scope > Classes` and `Scope > Domains` (handling the
#' `"ALL"`/`"NONE"` sentinels and `"XX--"` prefix wildcards) against `domain`.
#'
#' Dynamically-named domains not in the bundled domain-to-class table (e.g. `SUPPAE`,
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
#' @param dataset Optional dataset (an element of a [read_study()] object's
#'   `$datasets`). Only needed to resolve a rule's
#'   `include_split_datasets` scope flag, which depends on whether this
#'   dataset is one file of a domain split across several - a property of
#'   the data's `DOMAIN` column, not of its name. Without it, such rules
#'   are neither narrowed nor widened.
#' @param standard Optionally the standard the data follows, e.g. `"SDTMIG"`
#'   or `"SENDIG"`. Rules are matched against it EXACTLY, so a `"SENDIG"`
#'   study does not pick up `"SENDIG-DART"` rules. Left `NULL`, rules from
#'   every standard apply.
#' @param version The standard's version, e.g. `"3.4"` (or `"3-4"`). Only used
#'   alongside `standard`. Rules are written per Implementation Guide version -
#'   408 SDTMIG rules exist for 3.2 against 445 for 3.4 - so without this a 3.2
#'   study is measured against rules written for 3.4.
#' @param include_deprecated Include rules CDISC has deprecated. `FALSE` by
#'   default: a deprecated rule has a published replacement, so running both
#'   reports the same defect twice.
#' Internal. [list_rules()] is the public way to ask this, via its `domain`
#' argument; this stays separate because `run_checks()` calls it per domain in
#' the hot path and needs the `dataset` argument, which has no public meaning.
#'
#' @return A [data.table::data.table()] of matching rules.
#' @noRd
rules_for_domain <- function(domain, use_case = NULL, dataset = NULL,
                             standard = NULL, version = NULL,
                             include_deprecated = FALSE) {
  rules <- .coreval_env$data$rules
  keep <- vapply(
    rules, rule_applies_to_domain, logical(1),
    domain = domain, use_case = use_case, dataset = dataset
  )

  # A SENDIG rule has nothing to say about an SDTM study. Of the 270 rules in
  # scope for DM, 73 are SENDIG-only - they inflated the findings, inflated
  # the skipped list, and cost runtime, and they were the reason one defect
  # could be reported three times over: once by the SDTMIG rule, once by the
  # SENDIG one, once by a deprecated predecessor.
  #
  # Matched exactly, not by prefix: a study declaring SENDIG should not pick
  # up SENDIG-DART rules, which are for a different kind of study.
  if (!is.null(standard) && length(standard) == 1 && !is.na(standard) && nzchar(standard)) {
    want <- toupper(standard)
    keep <- keep & vapply(
      rules, function(r) want %in% toupper(r$standards), logical(1)
    )

    # Narrow further to the Implementation Guide VERSION when one is given.
    # Rules are written per version: 408 SDTMIG rules exist for 3.2 against
    # 445 for 3.4, and 86 apply to exactly one version. Without this a study
    # on 3.2 is measured against rules written for a guide it does not follow.
    #
    # A CORE test case writes its version as "3-4" in .env while the rules say
    # "3.4", so the separator is normalised rather than requiring the caller
    # to know which form to use.
    if (!is.null(version) && length(version) == 1 && !is.na(version) && nzchar(version)) {
      want_pair <- toupper(paste(standard, gsub("-", ".", version, fixed = TRUE)))
      keep <- keep & vapply(
        rules, function(r) want_pair %in% toupper(r$standard_versions), logical(1)
      )
    }
  }

  # Deprecated rules have been superseded by a published replacement, so
  # running them reports the same defect twice.
  if (!isTRUE(include_deprecated)) {
    keep <- keep & vapply(
      rules, function(r) !identical(r$source, "deprecated_dir"), logical(1)
    )
  }

  ids <- vapply(rules[keep], function(r) r$id, character(1))
  # build_rules_table(), not list_rules(): list_rules(domain =) delegates HERE
  # for scoping, so calling it back would recurse forever.
  rules_table <- build_rules_table()
  rules_table[rules_table$id %in% ids, ]
}

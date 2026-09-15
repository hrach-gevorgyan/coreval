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
  # Cached: this is a pure function of the bundled rules, which are read once
  # in .onLoad and never replaced. It builds one one-row data.table per rule and
  # rbindlist()s them, and `rules_for_domain()` calls it once per domain - so
  # a seven-domain study rebuilt the same table seven times. Allocation
  # profiling put 600 MB of a 51,000-row study's 2.9 GB total in here, a fifth
  # of everything allocated, none of it touching the study's data at all.
  cached <- .coreval_env$rules_table
  if (!is.null(cached)) {
    # A copy, so a caller that modifies the table it gets back cannot corrupt
    # the cache for every later call.
    return(data.table::copy(cached))
  }
  rules <- .coreval_env$data$rules
  out <- data.table::rbindlist(lapply(rules, function(r) {
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
  .coreval_env$rules_table <- out
  data.table::copy(out)
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
  # Same guard the check entry points use, so an unrecognised standard or a
  # bare version is refused here too rather than quietly returning a
  # plausible-looking number. A version with no standard used to be discarded
  # in silence: list_rules(version = "3.4") returned all 797 rules.
  validate_check_args(standard = standard, version = version, domain = domain,
                      use_case = use_case, include_deprecated = include_deprecated)
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
    # `match(out$id, out$id)`, which is every row in order, and every rule comes back
    # instead of the one asked for. Naming the index something no column
    # shares removes the collision.
    wanted <- match(id, out$id)
    out <- out[wanted, ]
    data.table::setattr(out, "rules_version", rules_version())
    return(out)
  }

  if (!is.null(domain)) {
    # A domain no standard defines still matches every class-unconstrained
    # rule, so the count comes back confidently non-zero - 163 for a typo like
    # "ZZ". Someone asking "does coreval cover my domain?" deserves to be told
    # it does not recognise the name, not handed a plausible number.
    if (is.na(domain_class(domain))) {
      warning(
        "'", domain, "' is not a domain any bundled standard defines, so this ",
        "counts only the rules that apply to every domain. Check the spelling.",
        call. = FALSE
      )
    }
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
        keep <- keep & vapply(out$standard_version, function(s) {
          targets_standard_version(strsplit(s, ",")[[1]], standard, version)
        }, logical(1))
      }
      out <- out[keep, ]
    }
    # Documented as a filter, and applied only on the domain branch above, so
    # without a domain it was accepted and ignored.
    if (!is.null(use_case)) {
      rules <- .coreval_env$data$rules
      keep <- vapply(out$id, function(i) {
        uc <- rules[[i]]$scope[["Use Case"]]
        is.null(uc) || toupper(use_case) %in% trimws(strsplit(uc, ",")[[1]])
      }, logical(1))
      out <- out[keep, ]
    }
    if (!isTRUE(include_deprecated)) {
      out <- out[out$source != "deprecated_dir", ]
    }
  }

  data.table::setattr(out, "rules_version", rules_version())
  out
}

#' Check a controlled terminology package name against what is bundled
#'
#' Reported immediately rather than at first use, so a typo surfaces once as an
#' error naming the near misses, not as an identical skip reason on every rule
#' that wanted it.
#'
#' @param ct_package One package name, e.g. `"sdtmct-2026-03-27"`.
#' @return `ct_package`, unchanged.
#' @noRd
validate_ct_package <- function(ct_package) {
  if (!is.character(ct_package) || length(ct_package) != 1L || is.na(ct_package)) {
    stop("`ct_package` must be a single package name, e.g. \"sdtmct-2026-03-27\".",
         call. = FALSE)
  }
  known <- ct_package_names()
  if (!(ct_package %in% known)) {
    family <- sub("ct-.*$", "", ct_package)
    near <- grep(paste0("^", family, "ct-"), known, value = TRUE)
    stop(
      "'", ct_package, "' is not a bundled controlled terminology package.",
      if (length(near) > 0) {
        paste0("
  Available for ", family, ": ", paste(utils::tail(near, 4), collapse = ", "),
               if (length(near) > 4) ", ..." else "")
      } else {
        paste0("
  Available families: ",
               paste(unique(sub("ct-.*$", "", known)), collapse = ", "))
      },
      call. = FALSE
    )
  }
  ct_package
}

#' Reject arguments that would silently make a check do nothing
#'
#' Every one of these used to fail quietly rather than loudly. An unrecognised
#' `standard` scoped every rule out and reported a clean bill of health on zero
#' checks; a `domain` given as a number or `NA` reached the scope matcher and
#' produced an internal error several frames from the call; an out-of-range
#' `max_records` aborted only at the end, after all the evaluation work, with a
#' message that named none of the arguments. Checking here means the caller is
#' told which argument is wrong, before anything runs.
#'
#' @param standard,version,domain,max_records The user-supplied arguments.
#' @return `invisible(NULL)`; raises an error naming the offending argument.
#' @noRd
validate_check_args <- function(standard = NULL, version = NULL, domain = NULL,
                                max_records = NULL, use_case = NULL,
                                include_deprecated = FALSE) {
  one_string <- function(x, arg) {
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
      stop("`", arg, "` must be a single, non-empty string.", call. = FALSE)
    }
  }
  if (!is.null(domain)) {
    one_string(domain, "domain")
  }
  if (!is.null(max_records)) {
    if (!is.numeric(max_records) || length(max_records) != 1L ||
      is.na(max_records) || max_records < 1) {
      stop("`max_records` must be a single number of 1 or more.", call. = FALSE)
    }
  }
  # Anything but TRUE was quietly taken as FALSE, so `include_deprecated =
  # "yes"` ran without the retired rules the caller asked for.
  if (!isTRUE(include_deprecated) && !isFALSE(include_deprecated)) {
    stop("`include_deprecated` must be TRUE or FALSE.", call. = FALSE)
  }
  # A use case narrows which rules run, so a misspelt one ("IND") silently ran
  # only the rules that name no use case at all and reported the rest as never
  # having applied.
  if (!is.null(use_case)) {
    one_string(use_case, "use_case")
    known <- unique(unlist(lapply(.coreval_env$data$rules, function(r) {
      uc <- r$scope[["Use Case"]]
      if (is.null(uc)) NULL else trimws(strsplit(uc, ",")[[1]])
    })))
    if (!(toupper(use_case) %in% known)) {
      stop(
        "'", use_case, "' is not a use case any bundled rule names. Available: ",
        paste(sort(known), collapse = ", "), ".",
        call. = FALSE
      )
    }
  }
  if (is.null(standard) && is.null(version)) {
    return(invisible(NULL))
  }

  pairs <- unlist(lapply(.coreval_env$data$rules, function(r) r$standard_versions))
  products <- sort(unique(sub("[[:space:]].*$", "", pairs)))
  if (!is.null(standard)) {
    one_string(standard, "standard")
    if (!(toupper(standard) %in% toupper(products))) {
      stop(
        "no bundled rule targets the standard '", standard, "'. Available: ",
        paste(products, collapse = ", "), ".",
        call. = FALSE
      )
    }
  }
  if (!is.null(version)) {
    one_string(version, "version")
    if (is.null(standard)) {
      stop("`version` needs `standard` too - a version alone is ambiguous.", call. = FALSE)
    }
    # Compared the same way the rule filter compares, so a version accepted
    # here is one that actually selects rules there.
    prefix <- paste0(toupper(standard), " ")
    have <- sub(prefix, "", grep(prefix, toupper(pairs), value = TRUE), fixed = TRUE)
    if (!targets_standard_version(pairs, standard, version)) {
      stop(
        "no bundled ", standard, " rule targets version '", version, "'. Available: ",
        paste(sort(unique(have)), collapse = ", "), ".",
        call. = FALSE
      )
    }
  }
  invisible(NULL)
}

#' Controlled Terminology packages coreval bundles
#'
#' Which version of CDISC's Controlled Terminology a study follows decides
#' whether a value is a legal term, and the answer changes between releases -
#' `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`. So coreval never picks
#' one for you: pass the one your study declares as `check_study(ct_package =)`
#' and this is the list to pick from.
#'
#' Only what a conformance rule can ask about is bundled - each codelist's
#' submission value and C-code, its terms' submission values and C-codes, and
#' whether it is extensible. Definitions and synonyms are not, which is how
#' 438 MB of CDISC's own caches becomes half a megabyte here.
#'
#' @param family Optional prefix to narrow to one terminology family, e.g.
#'   `"sdtm"` or `"send"`.
#' @return A character vector of package names, oldest first.
#' @export
#' @examples
#' head(list_ct_packages("sdtm"))
list_ct_packages <- function(family = NULL) {
  out <- ct_package_names()
  if (!is.null(family)) {
    if (!is.character(family) || length(family) != 1L) {
      stop("`family` must be a single prefix, e.g. \"sdtm\".", call. = FALSE)
    }
    out <- grep(paste0("^", tolower(family), "ct-"), out, value = TRUE)
  }
  out
}

#' The upstream commits the bundled rules came from
#'
#' Internal. Reachable as `attr(list_rules(), "rules_version")`, and written
#' into every exported file's `about` sheet by [write_findings()] - which is
#' where it matters, since the point of recording it is to say which snapshot
#' of the rules produced a given set of results.
#'
#' @return A single string naming both repositories and the commit of each:
#'   `cdisc-org/cdisc-open-rules` (SENDIG, TIG, USDM) and
#'   `verisianHQ/core-contributor` (the CORE 1.0 SDTMIG rules).
#' @noRd
rules_version <- function() {
  paste0(
    "cdisc-org/cdisc-open-rules ", .coreval_env$data$upstream_sha,
    "; verisianHQ/core-contributor ", .coreval_env$data$core1_sha
  )
}

#' Which of the two bundled rule sets a study is checked with
#'
#' CORE 1.0 took the SDTMIG rules to verisianHQ/core-contributor and left
#' SENDIG, TIG and USDM with cdisc-org/cdisc-open-rules. A rule in both
#' repositories has a version from each: an SDTM study gets the 1.0 one, a
#' SEND or TIG study CDISC's. A study that declares no standard is checked as
#' SDTM, the standard coreval assumes elsewhere when none is given.
#'
#' @param standard The study's declared standard, or `NULL`.
#' @return `"sdtm"` or `"cdisc"`.
#' @noRd
rule_family <- function(standard) {
  s <- toupper(standard %||% "")
  if (length(s) == 1 && !is.na(s) && (startsWith(s, "SEND") || s == "TIG")) "cdisc" else "sdtm"
}

#' Make one rule set the bundled rules for the duration of `code`
#'
#' Everything that reads `.coreval_env$data$rules` then sees that set, and the
#' caches built over it are kept per set, so neither answer leaks into the
#' other.
#'
#' @param family `"sdtm"` or `"cdisc"`, see [rule_family()].
#' @param code Code to run.
#' @return The value of `code`.
#' @noRd
with_rule_family <- function(family, code) {
  old <- .coreval_env$rule_family %||% "sdtm"
  set_rule_family(family)
  on.exit(set_rule_family(old), add = TRUE)
  force(code)
}

#' Switch the bundled rules to one rule set
#' @param family `"sdtm"` or `"cdisc"`.
#' @return `NULL`, invisibly.
#' @noRd
set_rule_family <- function(family) {
  sets <- .coreval_env$rule_sets
  if (is.null(sets[[family]])) {
    stop("unknown rule set: ", family, call. = FALSE)
  }
  .coreval_env$rule_family <- family
  .coreval_env$data$rules <- sets[[family]]
  invisible(NULL)
}

#' Is a rule left out unless retired rules are asked for?
#'
#' A rule CDISC has deprecated is, and so, for an SDTM study, is a CDISC SDTM
#' rule that CORE 1.0 no longer carries: 1.0 is now where SDTM rules live, and
#' running one it dropped beside its replacement can report a defect twice. A
#' SEND or TIG study still runs those, since CDISC's set is the current one
#' there.
#'
#' @param r A rule record.
#' @return A single logical.
#' @noRd
rule_is_retired <- function(r) {
  identical(r$source, "deprecated_dir") ||
    (isTRUE(r$retired_in_core1) && identical(.coreval_env$rule_family %||% "sdtm", "sdtm"))
}

#' Build the two rule sets from the bundled data
#' @param data The bundled `rules.rds` list.
#' @return `list(sdtm, cdisc)`.
#' @noRd
build_rule_sets <- function(data) {
  cdisc <- data$rules
  for (id in names(data$cdisc_originals)) {
    r <- data$cdisc_originals[[id]]
    keep <- r$standards != "SDTMIG"
    # A rule CDISC wrote for SDTMIG alone has nothing left for SEND or TIG;
    # the 1.0 version, which names only SDTMIG, stays in its place.
    if (!any(keep)) {
      next
    }
    r$standards <- r$standards[keep]
    r$standard_versions <- r$standard_versions[
      sub("[[:space:]].*$", "", r$standard_versions) != "SDTMIG"
    ]
    cdisc[[id]] <- r
  }
  list(sdtm = data$rules, cdisc = cdisc)
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
  family <- .coreval_env$rule_family %||% "sdtm"
  cached <- .coreval_env$rules_table[[family]]
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
  .coreval_env$rules_table[[family]] <- out
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
#' Where a rule comes from, and what standing it has there:
#' * `"core_contributor"` - a CORE 1.0 SDTMIG or FDA Business Rule, from
#'   Verisian's core-contributor repository. These check an SDTM study.
#' * `"published"` - `Published/` in CDISC's cdisc-open-rules, fully tested.
#' * `"sendig_draft"`, `"sdtmig_draft"`, `"fda_business_rules_draft"` - drafts
#'   upstream that already ship test data.
#' * `"deprecated_dir"` - superseded by a published replacement. A check does
#'   not run it unless you ask, since running both reports the same defect
#'   twice.
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
#' @param substandard For `standard = "TIG"` only: whether the tobacco study
#'   is `"SDTM"` (clinical), `"SEND"` (nonclinical) or `"ADaM"`, which decides
#'   the datasets a TIG rule's use case covers when `domain` is given.
#'   Optional here, unlike [check_study()]: left out, the use cases of all three
#'   apply.
#' @param use_case Optional use case (e.g. `"INDH"`). Rules with no Use Case
#'   constraint always pass.
#' @param include_deprecated Include superseded rules. `TRUE` here, unlike
#'   [check_dataset()] and [check_study()], which default to `FALSE`. The
#'   difference is deliberate: **listing is not running**. This function is the
#'   catalog of what is bundled, so hiding the retired rules would make
#'   `nrow(list_rules())` stop meaning "how many rules are there" - and `source`
#'   is right here to filter on. Checking is a different question, and there a
#'   superseded rule would report the same defect twice.
#'   Pass `FALSE` to see exactly what would run.
#' @return A [data.table::data.table()], one row per rule: `id`, the one-line
#'   `issue` it reports, its fuller `description`, the `guidance` sentence
#'   from the Implementation Guide it enforces, its `legacy_ids` (the ids the
#'   CDISC Conformance Rules and FDA Business Rules give it), `standard` and `standard_version`, `authority`, `rule_type`,
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
#' # Which snapshot of the rules is this?
#' attr(list_rules(), "rules_version")
#' @export
list_rules <- function(id = NULL, domain = NULL, standard = NULL,
                       version = NULL, use_case = NULL,
                       include_deprecated = TRUE, substandard = NULL) {
  # Optional here: listing is not checking, and without it the TIG lists are
  # merged, as with no standard.
  substandard <- validate_substandard(standard, substandard, required = FALSE)
  with_substandard(substandard, list_rules_impl(
    id = id, domain = domain, standard = standard, version = version,
    use_case = use_case, include_deprecated = include_deprecated
  ))
}

#' The body of [list_rules()], run with the TIG sub-standard in force
#' @noRd
list_rules_impl <- function(id = NULL, domain = NULL, standard = NULL,
                            version = NULL, use_case = NULL,
                            include_deprecated = TRUE) {
  # Same guard the check entry points use, so an unrecognised standard or a
  # bare version is refused here too rather than quietly returning a
  # plausible-looking number. A version with no standard used to be discarded
  # in silence: list_rules(version = "3.4") returned all 797 rules.
  validate_check_args(standard = standard, version = version, domain = domain,
                      use_case = use_case, include_deprecated = include_deprecated)
  # A SEND or TIG standard is answered from CDISC's rule set, everything else
  # from the CORE 1.0 one, as check_study() would run them. See rule_family().
  family <- rule_family(standard)
  if (!identical(family, .coreval_env$rule_family)) {
    return(with_rule_family(family, list_rules_impl(
      id = id, domain = domain, standard = standard, version = version,
      use_case = use_case, include_deprecated = include_deprecated
    )))
  }
  out <- build_rules_table()

  # Looking up an id is a different question from "what would run": it should
  # answer even for a deprecated rule, or one outside the standard in play,
  # because the report may well have named it. So it short-circuits the
  # scoping filters rather than being narrowed by them.
  if (!is.null(id)) {
    # Any case, and the older ids a report prints after "also" (CG0665, FB0801)
    # find the rule too.
    id <- toupper(trimws(id))
    legacy <- strsplit(toupper(out$legacy_ids), ",[[:space:]]*")
    id <- unique(unlist(lapply(id, function(x) {
      if (x %in% out$id) return(x)
      hit <- out$id[vapply(legacy, function(l) x %in% l, logical(1))]
      if (length(hit) > 0) hit else x
    })))
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
      retired <- names(Filter(rule_is_retired, .coreval_env$data$rules))
      out <- out[!out$id %in% retired, ]
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
#' Check `substandard` against `standard`, as CDISC's engine does for TIG
#'
#' The engine stops on a TIG check without `--substandard` (core.py), because
#' its use-case lists are kept per sub-standard.
#'
#' @param standard,substandard As passed by the caller.
#' @param required Whether TIG needs one; `list_rules()` does not.
#' @return The sub-standard, upper case, or `NULL`.
#' @noRd
validate_substandard <- function(standard, substandard, required = TRUE) {
  tig <- identical(toupper(standard %||% ""), "TIG")
  if (is.null(substandard)) {
    if (tig && required) {
      stop("standard = \"TIG\" needs substandard = \"SDTM\" or \"SEND\" (or \"ADaM\"): ",
           "a TIG rule's use case covers different datasets in each.", call. = FALSE)
    }
    return(NULL)
  }
  if (!is.character(substandard) || length(substandard) != 1L || is.na(substandard) ||
        !toupper(substandard) %in% c("SDTM", "SEND", "ADAM")) {
    stop("`substandard` must be \"SDTM\", \"SEND\" or \"ADaM\".", call. = FALSE)
  }
  if (!tig) {
    stop("`substandard` applies to standard = \"TIG\" only.", call. = FALSE)
  }
  toupper(substandard)
}

#' Make a TIG sub-standard the one in force for the duration of `code`
#' @param substandard A validated sub-standard, or `NULL`.
#' @param code Code to run.
#' @return The value of `code`.
#' @noRd
with_substandard <- function(substandard, code) {
  old <- .coreval_env$substandard
  .coreval_env$substandard <- substandard
  on.exit(.coreval_env$substandard <- old, add = TRUE)
  force(code)
}

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
    if (is.numeric(version)) {
      stop("`version` must be text, e.g. version = \"3.4\", not a number.", call. = FALSE)
    }
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

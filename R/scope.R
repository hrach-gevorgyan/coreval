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

#' The observation class of a dataset
#'
#' Looked up by the domain the dataset belongs to, not by its file name. A
#' domain split into LB1 and LB2 was looked up as "LB1", had no class, and
#' every rule scoped to Findings silently passed it by.
#'
#' A sponsor-defined domain is in no table, so its class comes from its topic
#' variable, as the reference decides it (handle_custom_domains,
#' base_data_service.py): --TERM is Events, --TRT Interventions, QNAM
#' Relationship, --TESTCD Findings, or Findings About when --OBJ is present too.
#' Without this every class-scoped rule skipped a custom domain without a word,
#' and CORE-000376, which exists only for custom domains, could never run.
#'
#' @param dataset A dataset entry, or `NULL` when only the name is known.
#' @param key The dataset's key (file name).
#' @return A single class name, or `NA_character_` if it cannot be told.
#' @noRd
dataset_class <- function(dataset, key) {
  code <- if (is.null(dataset)) toupper(key) else dataset_unsplit_name(dataset, key)
  cls <- domain_class(code)
  if (!is.na(cls) || is.null(dataset) || is.null(dataset$data)) {
    return(cls)
  }
  cols <- toupper(names(dataset$data))
  if ("DOMAIN" %in% cols) {
    has <- function(suffix) paste0(code, suffix) %in% cols
    if (has("TERM")) return("EVENTS")
    if (has("TRT")) return("INTERVENTIONS")
    if (has("QNAM")) return("RELATIONSHIP")
    if (has("TESTCD")) return(if (has("OBJ")) "FINDINGS ABOUT" else "FINDINGS")
  } else if ("RDOMAIN" %in% cols && "QNAM" %in% cols) {
    return("RELATIONSHIP")
  }
  NA_character_
}

#' Test a rule's Scope > Classes block against a dataset
#'
#' Findings About is a kind of Findings: a rule written for Findings also
#' covers FA and SR, as it does in the reference (rule_applies_to_class,
#' rule_processor.py), for inclusion and exclusion alike.
#'
#' @param classes_spec The rule's `scope$Classes` Include/Exclude block.
#' @param domain The dataset's key.
#' @param dataset The dataset, or `NULL`.
#' @return A single logical.
#' @noRd
class_matches <- function(classes_spec, domain, dataset = NULL) {
  cls <- toupper(dataset_class(dataset, domain))
  include_exclude_matches(classes_spec, function(pattern) {
    pattern <- toupper(pattern)
    if (pattern == "ALL") {
      return(TRUE)
    }
    !is.na(cls) && (identical(cls, pattern) ||
                      (identical(cls, "FINDINGS ABOUT") && identical(pattern, "FINDINGS")))
  })
}

#' Test a rule's Scope > Domains block against a dataset
#'
#' A pattern matches the dataset's file name or the domain it belongs to, so a
#' rule for LB runs on LB1 and LB2 as the reference runs it (it tests the
#' DOMAIN value and the name, _is_domain_name_included).
#'
#' @param domains_spec The rule's `scope$Domains` Include/Exclude block.
#' @param domain The dataset's key.
#' @param dataset The dataset, or `NULL`.
#' @return A single logical.
#' @noRd
domains_match <- function(domains_spec, domain, dataset = NULL) {
  names_ <- unique(c(toupper(domain),
                     if (!is.null(dataset)) dataset_unsplit_name(dataset, domain)))
  include_exclude_matches(domains_spec, function(pattern) {
    any(vapply(names_, pattern_matches_domain, logical(1), pattern = pattern))
  })
}

#' Is this dataset a USDM entity table?
#'
#' Told by its shape rather than by where it came from, because it can come
#' from either: a study document flattened by read_usdm.R, or the per-entity
#' CSVs CDISC publishes as the rules' own test data. Both carry the columns
#' saying what each record hangs off, which is what makes a graph readable as
#' tables, and no SDTM dataset has them.
#'
#' @param dataset A dataset entry, or `NULL`.
#' @return A single logical.
#' @noRd
is_usdm_entity_table <- function(dataset) {
  if (is.null(dataset) || is.null(dataset$data)) {
    return(FALSE)
  }
  all(c("parent_entity", "parent_rel", "rel_type") %in% names(dataset$data))
}

#' Test a USDM `Scope: Entities` spec against a dataset name
#'
#' USDM entity names arrive as the dataset key, upper-cased like every other
#' dataset name here (`StudyVersion.csv` becomes `STUDYVERSION`), so the
#' comparison is case-insensitive. `ALL` means every USDM entity, which is
#' narrower than it means for Domains: see [is_usdm_entity_table()].
#'
#' @param entities_spec The `Entities` element of a rule's scope.
#' @param domain Dataset key to test.
#' @param dataset The dataset itself, so `ALL` can be limited to entity tables.
#' @return A single logical.
#' @noRd
entities_match <- function(entities_spec, domain, dataset = NULL) {
  target <- toupper(domain)
  # `ALL` means every USDM ENTITY, not every dataset. Scoping by Entities is a
  # USDM idea, and a study-design rule has nothing to say about an SDTM domain:
  # left open, eight of them matched every tabular study ever checked and
  # arrived in the report as rules that could not run, one of them as a bare
  # "subscript out of bounds". A named entity needs no such guard, since an
  # SDTM domain code never matches one.
  usdm <- is_usdm_entity_table(dataset)
  include_exclude_matches(entities_spec, function(pattern) {
    pattern <- toupper(as.character(pattern)[[1]])
    (identical(pattern, "ALL") && usdm) || identical(pattern, target)
  })
}

#' Test whether a rule's full Scope (Classes, Domains, Entities, Use Case) applies to a domain
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
  # those three, it is not this. Over a hundred rules pair the two, so do not
  # retry this without measuring the whole sweep.
  if (!is.null(scope$Classes) && !class_matches(scope$Classes, domain, dataset)) {
    return(FALSE)
  }
  if (!is.null(scope$Domains) && !domains_scope_applies(scope$Domains, domain, dataset)) {
    return(FALSE)
  }
  # USDM rules scope by ENTITY, not by domain or class: a study-design document
  # has a StudyVersion and an Encounter where SDTM has a DM and an AE, and the
  # rules say `Entities: Include: [StudyVersion]`. Matched on the name, with no
  # `--` prefix wildcard and no class lookup, because neither exists in that
  # model.
  #
  # A rule with an Entities scope and nothing else used to match EVERY dataset,
  # since all three tests above are skipped when their key is absent. That is
  # the default-open shape this file has to be careful about: a scope key the
  # resolver does not know silently widens scope to everything rather than
  # narrowing it.
  if (!is.null(scope$Entities) && !entities_match(scope$Entities, domain, dataset)) {
    return(FALSE)
  }
  if (!is.null(use_case) && !is.null(scope[["Use Case"]])) {
    allowed <- toupper(trimws(strsplit(scope[["Use Case"]], ",")[[1]]))
    if (!(toupper(use_case) %in% allowed)) {
      return(FALSE)
    }
  }
  TRUE
}

#' Resolve a rule's Scope > Domains block, split-dataset flag included
#'
#' `include_split_datasets` narrows or widens scope by whether the dataset is
#' one FILE of a domain split across several, a property of the data (its
#' DOMAIN column), so it is only evaluated when the dataset is available. Per
#' the reference's _is_domain_name_included / _handle_split_domains: TRUE with
#' no Include list means "only split datasets"; TRUE with one ADDS split
#' datasets to what the list matched (this used to be read after the list had
#' already said no, so it never widened anything); FALSE excludes split
#' datasets; absent does nothing.
#'
#' @param domains_spec The rule's `scope$Domains` block.
#' @param domain The dataset's key.
#' @param dataset The dataset, or `NULL`.
#' @return A single logical.
#' @noRd
domains_scope_applies <- function(domains_spec, domain, dataset = NULL) {
  include_split <- domains_spec[["include_split_datasets"]]
  split <- !is.null(dataset) && dataset_is_split(dataset, domain)
  included <- is.null(domains_spec$Include) ||
    domains_match(list(Include = domains_spec$Include), domain, dataset)
  excluded <- !is.null(domains_spec$Exclude) &&
    !domains_match(list(Exclude = domains_spec$Exclude), domain, dataset)
  if (!is.null(dataset)) {
    if (isTRUE(include_split) && is.null(domains_spec$Include) && !split) {
      included <- FALSE
    }
    if (isTRUE(include_split) && split && !excluded) {
      included <- TRUE
    }
    if (identical(include_split, FALSE) && split) {
      excluded <- TRUE
    }
  }
  included && !excluded
}

#' The datasets each TIG use case covers, from the reference
#'
#' The reference applies a TIG rule to a dataset only when the dataset's domain
#' belongs to one of the rule's use cases (rule_applies_to_use_case,
#' rule_processor.py, with USE_CASE_DOMAINS from constants/use_cases.py), and
#' does so whether or not a use case was asked for. Without it, "the tobacco
#' product dataset TO is missing" was reported for every SDTM study checked
#' with no standard declared.
#' @noRd
use_case_domains <- list(
  INDH = c("AE", "CO", "CM", "DM", "DI", "DU", "DO", "DS", "EG", "EX", "EC", "FA",
           "IE", "LB", "MH", "PC", "PP", "DA", "DV", "QS", "RELREC", "RE", "SC",
           "SE", "SV", "SU", "EM", "TA", "TE", "TI", "TS", "TV", "VS"),
  PROD = c("TO", "PD", "PT", "IT", "IN", "IQ", "ES"),
  NONCLIN = c("BW", "CV", "CL", "CO", "DD", "DM", "DI", "DU", "DS", "EG", "EX", "FW",
              "GT", "LB", "MA", "MI", "OM", "PM", "PK", "PP", "POOLDEF", "RELREC",
              "RELREF", "RE", "SC", "SE", "TA", "TE", "TF", "TX", "TS", "VS"),
  ANALYSIS = character(0)
)

#' Does a TIG rule's Use Case cover this dataset?
#'
#' Only a rule checked as a TIG rule is limited this way: the reference applies
#' the use case only when the standard being checked is TIG. So it applies to
#' every rule when TIG is declared, and, with no standard declared, to a rule
#' that belongs to TIG alone; a rule SENDIG also publishes still runs on SEND
#' data as a SENDIG rule.
#'
#' A supplemental dataset counts as the domain it qualifies. A sponsor-defined
#' domain is in no use case's list; the reference refuses to run without being
#' told its use case, and here it is left in scope rather than dropped in
#' silence.
#'
#' @param rule A rule record.
#' @param domain The dataset's key.
#' @param dataset The dataset, or `NULL`.
#' @param standard The declared standard, or `NULL`.
#' @return A single logical.
#' @noRd
tig_use_case_applies <- function(rule, domain, dataset = NULL, standard = NULL) {
  if (is.null(rule$scope[["Use Case"]])) {
    return(TRUE)
  }
  standards <- toupper(rule$standards)
  as_tig <- if (is.null(standard)) all(standards == "TIG") else identical(toupper(standard), "TIG")
  if (!as_tig) {
    return(TRUE)
  }
  allowed <- toupper(trimws(strsplit(rule$scope[["Use Case"]], ",")[[1]]))
  use_case_covers_dataset(allowed, domain, dataset)
}

#' Is this dataset's domain among those a set of use cases covers?
#' @param allowed Use cases, upper case.
#' @param domain The dataset's key.
#' @param dataset The dataset, or `NULL`.
#' @return A single logical.
#' @noRd
use_case_covers_dataset <- function(allowed, domain, dataset = NULL) {
  code <- if (is.null(dataset)) toupper(domain) else dataset_unsplit_name(dataset, domain)
  code <- sub("^(SUPP|SQ)", "", code)
  covered <- unique(unlist(use_case_domains[intersect(allowed, names(use_case_domains))]))
  if (code %in% covered) {
    return(TRUE)
  }
  !(code %in% .coreval_env$domain_classes$domain) &&
    !(code %in% unlist(use_case_domains))
}

#' Domain to observation-class reference table
#'
#' Maps a domain code (e.g. `"LB"`) to its observation class (e.g.
#' `"FINDINGS"`), which is how a rule's `Scope > Classes` is resolved against
#' real data.
#'
#' A domain's class is stable across Implementation Guide versions - `LB` is a
#' Findings domain in every version of SDTMIG - so one table serves all of
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

#' One standard version, written any of the ways people write it
#'
#' A CORE test case writes "3-4" where the rules say "3.4", and a USDM study
#' document says "4.0.0" where the rules say "4.0". All name one version. They
#' were compared as exact text, and a USDM study declaring "4.0.0" matched no
#' rule at all: nothing ran, and the study was reported clean. Separators are
#' made dots and trailing zero components dropped, so "4.0.0", "4.0" and "4"
#' compare equal while "3.1" and "3.10" stay apart.
#'
#' @param version A character vector of versions.
#' @return The normalised versions.
#' @noRd
normalise_version <- function(version) {
  v <- toupper(trimws(as.character(version)))
  v <- gsub("-", ".", v, fixed = TRUE)
  sub("([.]0+)+$", "", v)
}

#' Does any "STANDARD VERSION" pair name this standard at this version?
#'
#' The one place a declared version is compared with the versions a rule
#' targets. It used to be done three times, with three slightly different
#' normalisations, which is how one of them came to miss "4.0.0".
#'
#' @param pairs Entries like `"SDTMIG 3.4"`, as a rule's `standard_versions`.
#' @param standard The declared standard.
#' @param version The declared version.
#' @return A single logical.
#' @noRd
targets_standard_version <- function(pairs, standard, version) {
  pairs <- trimws(as.character(pairs))
  pairs <- pairs[nzchar(pairs)]
  if (length(pairs) == 0) {
    return(FALSE)
  }
  names_ <- toupper(sub("[[:space:]].*$", "", pairs))
  versions <- normalise_version(sub("^[^[:space:]]+[[:space:]]*", "", pairs))
  any(names_ == toupper(standard) & versions == normalise_version(version))
}

#' Rules that apply to a given SDTM domain
#'
#' Resolves each rule's `Scope > Classes` and `Scope > Domains` (handling the
#' `"ALL"`/`"NONE"` sentinels and `"XX--"` prefix wildcards) against `domain`.
#'
#' Dynamically-named domains not in the bundled domain-to-class table resolve
#' by template: every `SUPPxx` dataset follows `SUPPQUAL`, so `SUPPAE` and
#' `SUPPDM` are `RELATIONSHIP`; and an Associated Persons dataset holds the
#' same kind of observation as the domain it is associated with, so `APEG`
#' takes `EG`'s class. `APID` is excluded from that rule - it is an identifier
#' variable, not a domain prefix.
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

  declared <- if (!is.null(standard) && length(standard) == 1 && !is.na(standard) &&
                   nzchar(standard)) standard else NULL
  keep <- keep & vapply(rules, tig_use_case_applies, logical(1),
                        domain = domain, dataset = dataset, standard = declared)

  # The one ADaMIG rule asks whether ADSL exists. With no standard declared,
  # every standard's rules run, and it told every SDTM study that ADSL was
  # missing. An ADaM rule is about ADaM datasets, whose names begin with AD.
  adam_declared <- identical(toupper(standard %||% ""), "ADAMIG")
  if (!adam_declared && !startsWith(toupper(domain), "AD")) {
    keep <- keep & vapply(
      rules, function(r) !all(toupper(r$standards) == "ADAMIG"), logical(1)
    )
  }

  # A SENDIG rule has nothing to say about an SDTM study. Of the 270 rules in
  # scope for DM, 73 are SENDIG-only - they inflated the findings, inflated
  # the skipped list, and cost runtime, and they were the reason one defect
  # could be reported three times over: once by the SDTMIG rule, once by the
  # SENDIG one, once by a deprecated predecessor.
  #
  # Matched exactly, not by prefix: a study declaring SENDIG should not pick
  # up SENDIG-DART rules, which are for a different kind of study.
  if (!is.null(standard) && length(standard) == 1 && !is.na(standard) && nzchar(standard)) {
    # Narrowed to the Implementation Guide VERSION too when one is given.
    # Rules are written per version: 408 SDTMIG rules exist for 3.2 against
    # 445 for 3.4, and 86 apply to exactly one version. Without this a study
    # on 3.2 is measured against rules written for a guide it does not
    # follow. "3-4" reads as "3.4" and "4.0.0" as "4.0".
    keep <- keep & rules_for_standard(rules, standard, version)
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

#' Which rules target a standard, and a version of it
#'
#' The answer depends on the standard and version alone, not on the dataset,
#' and working it out per rule per dataset was the largest single cost of a
#' study check: every rule's version list was re-normalised with regular
#' expressions once for each dataset. It is worked out once per standard and
#' version and kept for the session; the bundled rules do not change while it
#' runs.
#'
#' @param rules The bundled rules.
#' @param standard A standard, e.g. `"SDTMIG"`.
#' @param version A version or `NULL`.
#' @return A logical vector over `rules`.
#' @noRd
rules_for_standard <- function(rules, standard, version = NULL) {
  has_version <- !is.null(version) && length(version) == 1 && !is.na(version) && nzchar(version)
  cache_key <- paste0("std:", toupper(standard), ":", if (has_version) normalise_version(version) else "")
  if (is.null(.coreval_env$standard_filter)) {
    .coreval_env$standard_filter <- new.env(parent = emptyenv())
  }
  hit <- .coreval_env$standard_filter[[cache_key]]
  if (!is.null(hit) && length(hit) == length(rules) && identical(names(hit), names(rules))) {
    return(unname(hit))
  }
  want <- toupper(standard)
  keep <- vapply(rules, function(r) want %in% toupper(r$standards), logical(1))
  if (has_version) {
    keep <- keep & vapply(
      rules, function(r) targets_standard_version(r$standard_versions, standard, version),
      logical(1)
    )
  }
  names(keep) <- names(rules)
  assign(cache_key, keep, envir = .coreval_env$standard_filter)
  unname(keep)
}

# Quick check of a SINGLE dataset, for the person writing the code that
# produces it - as opposed to check_study(), which needs the whole folder.
#
# The honest part of this file is assert_referenced_domains_available(). A
# rule that joins another domain, or reads a value out of one, cannot be
# answered from one dataset alone, and evaluating it anyway would compare
# against columns that are simply absent - manufacturing findings out of
# missing input, exactly what read_study()/evaluate_rule()'s other guards
# exist to prevent. Those rules are SKIPPED, with a reason naming the domain
# that would have been needed.

#' Domains a rule needs besides the one being checked
#'
#' Three shapes name another dataset, and they resolve differently:
#'
#' * A `Match Datasets` `Name` such as `"SV"` - that domain, literally.
#' * A `"SUPP--"`/`"SQ--"` template - this domain's supplemental dataset. Note
#'   the `--` is a SUFFIX here, so `apply_match_dataset()` expands it with
#'   `sub("--$", ...)`, not with `resolve_var_name()`, which handles the
#'   leading-`--` variable-name form. Using the wrong one leaves the literal
#'   text `"SUPP--"` looking like a domain of that name.
#' * A `Child: TRUE` spec, which names the CHILD - the dataset being checked -
#'   and joins each row to the parent named in its own `RDOMAIN` column. The
#'   dependency is therefore in the DATA, not the rule, so it is read from
#'   `RDOMAIN` when the dataset is available.
#'
#' An `Operations` block's `domain` is the fourth, and is literal.
#'
#' @param rule A rule record.
#' @param domain The domain being checked, used to expand templates.
#' @param dataset Optional dataset entry, needed only to resolve a `Child`
#'   spec's parent domains from `RDOMAIN`.
#' @return An upper-case character vector of other domains, possibly empty.
#' @noRd
rule_external_domains <- function(rule, domain, dataset = NULL) {
  named <- character(0)

  for (spec in rule$match_datasets %||% list()) {
    name <- if (is.null(spec$Name)) NA_character_ else as.character(spec$Name)
    if (isTRUE(spec$Child)) {
      rdomain <- if (is.null(dataset)) NULL else dataset$data$RDOMAIN
      named <- c(named, if (is.null(rdomain)) {
        # No data to look in: the parent is genuinely unknown rather than
        # absent, and saying so beats inventing a domain name.
        "the parent domain named in RDOMAIN"
      } else {
        unique(rdomain[!is.na(rdomain) & nzchar(rdomain)])
      })
      next
    }
    if (is.na(name)) {
      next
    }
    named <- c(named, sub("--$", dataset_wildcard(dataset, domain), name))
  }

  for (op in rule$operations %||% list()) {
    if (!is.null(op$domain)) {
      named <- c(named, sub("--$", dataset_wildcard(dataset, domain), as.character(op$domain)))
    }
  }

  named <- named[!is.na(named) & nzchar(named)]
  if (length(named) == 0) {
    return(character(0))
  }
  setdiff(unique(toupper(named)), toupper(domain))
}

#' Refuse a rule that needs a domain this study does not contain
#'
#' Applied when checking a SINGLE dataset, never for a whole study, and the
#' difference is deliberate.
#'
#' `apply_match()` returns the dataset unchanged when a referenced domain is
#' absent, and an `Operations` block over a missing domain yields `NA`. For a
#' whole study that is the right, forgiving behaviour: a study legitimately has
#' no `SUPPAE` or `RELREC`, and the reference engine also carries on. Making
#' those hard requirements would refuse rules that genuinely have nothing to
#' join, so `check_study()` does not.
#'
#' For a single dataset the same silence is dangerous rather than forgiving.
#' The user has supplied one domain and *every* cross-domain rule would find
#' its counterpart missing, so instead of a handful of no-op joins there would
#' be a systematic stream of rules quietly comparing against columns that do
#' not exist. A short findings table would then read as "my dataset is clean"
#' when it actually means "most of the applicable rules never really ran."
#'
#' @param rule A rule record.
#' @param study The study object (here, one holding a single dataset).
#' @param domain The domain being checked.
#' @return The domains the rule needs that `study` does not have, possibly empty.
#' @noRd
missing_referenced_domains <- function(rule, study, domain) {
  needed <- rule_external_domains(rule, domain, study$datasets[[domain]])
  setdiff(needed, toupper(names(study$datasets)))
}

#' Read a single dataset file into the internal representation
#' @param path Path to one `.xpt`, `.sas7bdat` or `.csv` file.
#' @return `list(data, meta, label)`, see [read_study()].
#' @noRd
read_one_dataset_file <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "xpt") {
    return(build_dataset_from_data_frame(haven::read_xpt(path)))
  }
  if (ext == "sas7bdat") {
    return(build_dataset_from_data_frame(haven::read_sas(path)))
  }
  if (ext == "csv") {
    # A bare CSV declares no types, unlike an XPT (which carries its own) or a
    # CORE test case (which ships `_variables.csv`). Inference is the only
    # option here, so it is done with fread's defaults - but note the cost:
    # a numeric-looking identifier such as "007" becomes 7, and a rule about
    # its text form can no longer see the original. Prefer .xpt when the
    # distinction matters.
    dt <- data.table::fread(path, na.strings = character(0), strip.white = FALSE)
    fill_char_blanks(dt)
    return(list(
      data = dt,
      meta = data.table::data.table(
        variable = names(dt),
        label = NA_character_,
        type = vapply(dt, function(col) if (is.character(col)) "Char" else "Num", character(1))
      ),
      label = NA_character_
    ))
  }
  stop(
    "don't know how to read '", basename(path),
    "': expected a .xpt, .sas7bdat or .csv file",
    call. = FALSE
  )
}

#' Work out which domain a dataset is
#' @param dataset A dataset entry.
#' @param path Optional source path, used when there is no usable `DOMAIN` column.
#' @return A two-or-more character domain code, or `NULL` if undeterminable.
#' @noRd
infer_domain <- function(dataset, path = NULL) {
  # The DOMAIN column is the authority, not the file name: a split dataset
  # lives in ae1.xpt / ae2.xpt but still carries DOMAIN == "AE", and that is
  # the code the rules are written against.
  col <- dataset$data$DOMAIN
  has_domain_column <- !is.null(col)
  if (has_domain_column) {
    # Trailing blanks are everywhere in SAS-derived data, and an untrimmed
    # "AE " is not the domain "AE": it silently scoped to a domain of that
    # name, ran a different set of rules, and reported a different number of
    # findings with no warning at all.
    values <- trimws(as.character(col))
    values <- unique(values[!is.na(values) & nzchar(values)])
    if (length(values) == 1) {
      return(toupper(values))
    }
    if (length(values) > 1) {
      stop(
        "DOMAIN holds more than one value (", paste(sort(values), collapse = ", "),
        ") - pass domain= to say which one to check, or split the data first",
        call. = FALSE
      )
    }
  }
  if (!is.null(path)) {
    return(toupper(tools::file_path_sans_ext(basename(path))))
  }
  # Say which of the two situations this actually is. "no single DOMAIN value"
  # reads as "your DOMAIN column is inconsistent" to someone whose column is
  # simply empty, or whose dataset has no rows yet.
  if (has_domain_column) {
    stop(
      if (nrow(dataset$data) == 0) {
        "this dataset has no rows, so the DOMAIN column is empty - "
      } else {
        "every value in the DOMAIN column is blank - "
      },
      "pass domain= to say what this is, e.g. domain = \"AE\"",
      call. = FALSE
    )
  }
  NULL
}

#' Check one dataset, without needing a study folder
#'
#' For when you are writing the code that builds a domain and want to know
#' what is wrong with it right now. Give it the data frame you already have
#' open, or the path to a single file.
#'
#' @section What it cannot check on its own:
#' Plenty of CDISC rules compare one dataset against another - an adverse event
#' date against the subject's reference dates in `DM`, a visit against the trial
#' design. Hand over a single dataset and those questions cannot be answered.
#'
#' coreval does not guess. Those rules are skipped, and `$skipped` names the
#' dataset each one wanted. Running them anyway would compare your data against
#' columns that are not there and report problems that do not exist.
#'
#' Most rules still run - across AE, DM, LB and VS, 76-84% of the applicable
#' ones work on a single dataset. But the ones that cannot are the cross-dataset
#' checks, which are often the ones that matter.
#'
#' **So a short `$findings` table here does not mean the data is clean.** It is
#' a quick first pass, not a verdict. Run [check_study()] on the whole folder
#' before drawing conclusions.
#'
#' @param x A data frame (or [data.table::data.table()]), or the path to one
#'   `.xpt`, `.sas7bdat` or `.csv` file.
#' @param domain Two-letter domain code, e.g. `"AE"`. Left as `NULL`, coreval
#'   takes it from your `DOMAIN` column, or the file name if there isn't one -
#'   so `ae1.xpt` from a split dataset is still checked as `AE`. Set it
#'   yourself if that guess is wrong.
#' @param standard The standard the data follows, e.g. `"SDTMIG"` or
#'   `"SENDIG"`. Rules are scoped to it, which is usually what you want - a
#'   SENDIG rule has nothing to say about an SDTM study.
#'
#'   It is not free, though, and CDISC's coverage is uneven. The general
#'   "dates must be valid ISO 8601" rule (`CORE-000547`) is published for
#'   SENDIG and TIG but **not for SDTMIG**, whose only equivalents are
#'   `TSVAL`-specific or deprecated. So `standard = "SDTMIG"` genuinely stops
#'   a malformed `RFSTDTC` being reported. The report says how many rules were
#'   set aside; leave `standard` unset to see everything.
#' @param version The standard's version, e.g. `"3-4"`.
#' @param use_case Optional use case (e.g. `"INDH"`), as in [rules_for_domain()].
#' @param max_records Most records to keep per rule, default 1000. A rule that
#'   flags every row of a large dataset would otherwise produce more findings
#'   than anyone can read or Excel can hold. The true count is kept in
#'   `truncated`. Use `Inf` for every record.
#' @param include_deprecated Also run rules CDISC has deprecated. `FALSE` by
#'   default: a deprecated rule has a published replacement, so running both
#'   reports the same defect twice.
#' @return `list(findings, skipped, truncated)` - the same shape
#'   [check_study()] returns, so [write_findings()] works on it unchanged.
#' @examples
#' ae <- data.frame(
#'   STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
#'   AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
#'   AESTDTC = c("2024-01-10", "2024-02-30") # 30 February is not a date
#' )
#' result <- check_dataset(ae)
#' result$findings[result$findings$Value == "2024-02-30", ]
#'
#' # Always look at what could not run:
#' nrow(result$skipped)
#' @seealso [check_study()] to check a whole study folder.
#' @export
check_dataset <- function(x, domain = NULL, standard = NULL, version = NULL,
                          use_case = NULL, max_records = 1000,
                          include_deprecated = FALSE) {
  path <- NULL
  if (is.character(x)) {
    if (length(x) != 1) {
      stop("x must be a single file path, or a data frame", call. = FALSE)
    }
    if (!file.exists(x)) {
      stop("file not found: ", x, call. = FALSE)
    }
    if (dir.exists(x)) {
      stop(
        "'", x, "' is a folder - use read_study() then check_study() for a whole study",
        call. = FALSE
      )
    }
    path <- x
    dataset <- read_one_dataset_file(x)
  } else if (is.data.frame(x)) {
    dataset <- build_dataset_from_data_frame(x)
  } else {
    stop("x must be a data frame, or a path to one dataset file", call. = FALSE)
  }

  if (is.null(domain)) {
    domain <- infer_domain(dataset, path)
  }
  if (is.null(domain) || !nzchar(domain)) {
    stop(
      "can't tell which domain this is: the data has no single DOMAIN value ",
      "and there is no file name to fall back on - pass domain=, e.g. domain = \"AE\"",
      call. = FALSE
    )
  }
  domain <- toupper(domain)

  study <- list(
    datasets = stats::setNames(list(dataset), domain),
    define = NULL,
    ct = NULL,
    standard = list(
      product = if (is.null(standard)) NA_character_ else toupper(standard),
      version = if (is.null(version)) NA_character_ else version
    )
  )
  run_checks(
    study,
    use_case = use_case, require_referenced_domains = TRUE,
    max_records = max_records, include_deprecated = include_deprecated
  )
}

# Regenerates inst/extdata/rules.rds from a local clone of cdisc-org/cdisc-open-rules.
# Requires the `yaml` package (not a runtime dependency of coreval).
#
# Usage (from the package root):
#   git clone https://github.com/cdisc-org/cdisc-open-rules.git data-raw/upstream/cdisc-open-rules
#   Rscript data-raw/extract_rules.R
#
# The clone lives under data-raw/upstream/ (gitignored - see .gitignore),
# persisted across sessions on purpose so re-running this script or doing
# ad-hoc research against the real upstream data never needs a fresh clone.
# data-raw/ as a whole is already excluded from the built package via
# .Rbuildignore, so its size doesn't affect R CMD check or the shipped
# tarball either way.
#
# Sources combined, each tagged with a `source` field so downstream code
# (list_rules(), the conformance harness) can tell them apart:
#
#   - Published/*                       -> source "published"
#       Core$Status == "Published", full test data. The trusted core set.
#   - Deprecated/*                      -> source "deprecated_dir"
#       Despite the folder name, upstream's README says these are current
#       rules (SDTM- and SEND-family) temporarily parked here during FDA
#       Business Rules integration work: Core$Status == "Published", full
#       test data, but upstream itself says "not fully validated - use
#       discernment."
#   - Unpublished/FDA Business Rules/*  -> source "fda_business_rules_draft"
#       Core$Status == "Draft". Only the subset that already ships test data
#       (results.csv) is included, since untested rules can't be checked
#       against the conformance harness anyway.

library(yaml)

upstream_dir <- file.path("data-raw", "upstream", "cdisc-open-rules")
sha <- system2("git", c("-C", upstream_dir, "rev-parse", "HEAD"), stdout = TRUE)

# SDTM's nonclinical sibling (SEND) and the Timing Implementation Guide
# share the same tabular, domain-based dataset shape our engine already
# reads/evaluates - genuinely extractable, not just "more data". ADaMIG is
# also kept (a small number of Published/Deprecated rules already cite it
# alongside SDTMIG) - see data-raw's own README/CLAUDE.md notes for why the
# much larger Unpublished/ADAMIG draft folder is deliberately NOT pulled in:
# every one of its 93 rules has test data but zero reference results.csv,
# so nothing there can be verified against real CDISC output, unlike every
# other tier here. USDM (a JSON study-design model, not a tabular dataset
# format at all) is excluded outright - read_study() has no way to read it
# as SDTM-shaped domains, so extracting it would only ever produce rules
# with 0% possible coverage.
want_standards <- c("SDTMIG", "SENDIG", "SENDIG-AR", "SENDIG-DART", "SENDIG-GENETOX", "TIG", "ADaMIG")

# yaml::yaml.load_file() silently returns NA for whole numbers that overflow
# 32-bit integer (e.g. byte-size thresholds like 5368709120), instead of
# falling back to double. Override the "int" handler to do that fallback.
int_handler <- function(x) {
  v <- suppressWarnings(as.integer(x))
  if (is.na(v)) as.numeric(x) else v
}

# YAML 1.1 (which this R parser follows) treats bare y/Y/yes/on/true and
# n/N/no/off/false as booleans - but the REFERENCE ENGINE (Python, PyYAML)
# does NOT: PyYAML's own bool resolver regex only matches the FULL words
# yes/Yes/YES/no/No/NO/true/True/TRUE/false/False/FALSE/on/On/ON/off/Off/OFF
# - a bare single-letter "Y" or "N" is never one of them and stays a plain
# string there. SDTM Y/N flag literals (`value: Y`, `value: N` - extremely
# common: DTHFL, *PRESP, *OCCUR, ...) would otherwise get silently
# corrupted into logical TRUE/FALSE here, diverging from what the
# reference engine actually sees.
#
# So single-letter Y/N must stay text (matching Python's own non-boolean
# treatment), but a genuine full-word boolean like `value: true` should
# become a REAL logical - confirmed necessary against CORE-000291's real
# fixture: `$EXVAMT_EXISTS equal_to true` compares a boolean Operations
# binding (TRUE/FALSE) against this literal, and PyYAML parses `true` as
# Python's real `True`, not the string "true" (which would never
# case-sensitively equal R's `as.character(TRUE)` = "TRUE" anyway).
# `normalize_flags()` below separately re-coerces schema flag fields
# (value_is_literal, negative, ...) that always carry a fixed boolean
# semantics regardless of this text/logical split.
preserve_bool_text <- function(x) {
  if (tolower(x) %in% c("yes", "no", "true", "false", "on", "off")) {
    isTRUE(tolower(x) %in% c("yes", "true", "on"))
  } else {
    x
  }
}

FLAG_KEYS <- c(
  "value_is_literal", "negative", "type_insensitive", "value_is_reference",
  "include_split_datasets"
)

normalize_flags <- function(x) {
  if (!is.list(x)) {
    return(x)
  }
  nm <- names(x)
  for (i in seq_along(x)) {
    key <- if (!is.null(nm)) nm[i] else NA
    if (!is.na(key) && key %in% FLAG_KEYS) {
      x[[i]] <- isTRUE(as.logical(x[[i]]))
    } else {
      x[[i]] <- normalize_flags(x[[i]])
    }
  }
  x
}

has_results_csv <- function(rule_dir) {
  length(list.files(rule_dir, pattern = "^results\\.csv$", recursive = TRUE)) > 0
}

extract_one <- function(path, source) {
  d <- yaml::yaml.load_file(path, handlers = list(
    int = int_handler,
    `bool#yes` = preserve_bool_text,
    `bool#no` = preserve_bool_text
  ))
  d <- normalize_flags(d)

  standards <- unique(unlist(lapply(d$Authorities, function(a) {
    vapply(a$Standards, function(s) s$Name, character(1))
  })))
  if (!any(standards %in% want_standards)) {
    return(NULL)
  }

  matched_standards <- standards[standards %in% want_standards]

  authorities <- unique(unlist(lapply(d$Authorities, function(a) {
    std_names <- vapply(a$Standards, function(s) s$Name, character(1))
    if (any(std_names %in% want_standards)) a$Organization else NA_character_
  })))
  authorities <- authorities[!is.na(authorities)]

  # A handful of FDA Business Rules drafts (only surfaced now that SENDIG is
  # in want_standards) have no Core.Id at all - unlike every other rule.yml
  # here, which all declare one explicitly. Their directory name (e.g.
  # "FB6501") doesn't use the "FDA.<standard>.FBxxxx" convention the rest of
  # this tier follows, so build the same shape rather than leaving a bare,
  # potentially-collision-prone folder name as the id.
  rule_id <- if (!is.null(d$Core$Id)) d$Core$Id else paste0("FDA.", matched_standards[1], ".", basename(dirname(path)))

  list(
    id = rule_id,
    source = source,
    status = d$Core$Status,
    core_version = d$Core$Version,
    description = d$Description,
    executability = d$Executability,
    rule_type = d[["Rule Type"]],
    sensitivity = d$Sensitivity,
    grouping_variables = d[["Grouping_Variables"]],
    standards = matched_standards,
    authorities = authorities,
    scope = d$Scope,
    check = d$Check,
    operations = d$Operations,
    match_datasets = d[["Match Datasets"]],
    outcome = d$Outcome
  )
}

published_files <- Sys.glob(file.path(upstream_dir, "Published", "*", "rule.yml"))
published <- lapply(published_files, extract_one, source = "published")

deprecated_files <- Sys.glob(file.path(upstream_dir, "Deprecated", "*", "rule.yml"))
deprecated <- lapply(deprecated_files, extract_one, source = "deprecated_dir")

fda_draft_files <- Sys.glob(
  file.path(upstream_dir, "Unpublished", "FDA Business Rules", "*", "rule.yml")
)
fda_draft_files <- Filter(function(f) has_results_csv(dirname(f)), fda_draft_files)
fda_draft <- lapply(fda_draft_files, extract_one, source = "fda_business_rules_draft")

rules <- c(published, deprecated, fda_draft)
rules <- Filter(Negate(is.null), rules)
names(rules) <- vapply(rules, function(r) r$id, character(1))

stopifnot(
  "duplicate rule ids across sources" = !anyDuplicated(names(rules)),
  "expected 566 published rules" = sum(vapply(rules, function(r) r$source == "published", logical(1))) == 566,
  "expected 163 deprecated_dir rules" = sum(vapply(rules, function(r) r$source == "deprecated_dir", logical(1))) == 163,
  "expected 27 fda_business_rules_draft rules" = sum(vapply(rules, function(r) r$source == "fda_business_rules_draft", logical(1))) == 27
)

rules_data <- list(
  upstream_sha = sha,
  rules = rules
)

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(rules_data, file.path("inst", "extdata", "rules.rds"), compress = "xz")

writeLines(sha, file.path("data-raw", "UPSTREAM_SHA"))

cat(sprintf("Extracted %d rules from upstream SHA %s\n", length(rules), sha))

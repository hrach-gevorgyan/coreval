# Regenerates inst/extdata/rules.rds from a local clone of cdisc-org/cdisc-open-rules.
# Requires the `yaml` package (not a runtime dependency of coreval).
#
# Usage (from the package root):
#   git clone --depth 1 https://github.com/cdisc-org/cdisc-open-rules.git data-raw/cdisc-open-rules
#   Rscript data-raw/extract_rules.R
#   rm -rf data-raw/cdisc-open-rules
#
# Delete the clone when done (or clone it outside the package directory to
# begin with) - leaving ~20k upstream files under data-raw/ makes every
# subsequent R CMD check noticeably slower, since it still has to walk and
# exclude them even though .Rbuildignore keeps them out of the built tarball.
#
# Sources combined, each tagged with a `source` field so downstream code
# (list_rules(), the conformance harness) can tell them apart:
#
#   - Published/*                       -> source "published"
#       Core$Status == "Published", full test data. The trusted core set.
#   - Deprecated/*                      -> source "deprecated_dir"
#       Despite the folder name, upstream's README says these are current
#       SDTM-only rules temporarily parked here during FDA Business Rules
#       integration work: Core$Status == "Published", full test data, but
#       upstream itself says "not fully validated - use discernment."
#   - Unpublished/FDA Business Rules/*  -> source "fda_business_rules_draft"
#       Core$Status == "Draft". Only the subset that already ships test data
#       (results.csv) is included, since untested rules can't be checked
#       against the conformance harness anyway.

library(yaml)

upstream_dir <- file.path("data-raw", "cdisc-open-rules")
sha <- system2("git", c("-C", upstream_dir, "rev-parse", "HEAD"), stdout = TRUE)

want_standards <- c("SDTMIG", "ADaMIG")

# yaml::yaml.load_file() silently returns NA for whole numbers that overflow
# 32-bit integer (e.g. byte-size thresholds like 5368709120), instead of
# falling back to double. Override the "int" handler to do that fallback.
int_handler <- function(x) {
  v <- suppressWarnings(as.integer(x))
  if (is.na(v)) as.numeric(x) else v
}

# YAML 1.1 (which this parser follows) treats bare y/Y/yes/on/true and
# n/N/no/off/false as booleans. SDTM Y/N flag literals (`value: Y`, `value: N`
# - extremely common: DTHFL, *PRESP, *OCCUR, ...) get silently corrupted into
# logical TRUE/FALSE instead of the strings "Y"/"N" they actually are.
# Override both boolean handlers to keep the original text, then re-coerce
# the schema's actual boolean flags (value_is_literal, negative, etc., which
# would otherwise also come through as strings like "true") back to logicals
# in normalize_flags() below.
preserve_bool_text <- function(x) x

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

  list(
    id = d$Core$Id,
    source = source,
    status = d$Core$Status,
    core_version = d$Core$Version,
    description = d$Description,
    executability = d$Executability,
    rule_type = d[["Rule Type"]],
    sensitivity = d$Sensitivity,
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
  "expected 332 published rules" = sum(vapply(rules, function(r) r$source == "published", logical(1))) == 332,
  "expected 163 deprecated_dir rules" = sum(vapply(rules, function(r) r$source == "deprecated_dir", logical(1))) == 163,
  "expected 12 fda_business_rules_draft rules" = sum(vapply(rules, function(r) r$source == "fda_business_rules_draft", logical(1))) == 12
)

rules_data <- list(
  upstream_sha = sha,
  rules = rules
)

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(rules_data, file.path("inst", "extdata", "rules.rds"), compress = "xz")

writeLines(sha, file.path("data-raw", "UPSTREAM_SHA"))

cat(sprintf("Extracted %d rules from upstream SHA %s\n", length(rules), sha))

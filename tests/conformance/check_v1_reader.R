# Check that v1_case.R reads CORE 1.0 test cases correctly, before any grade
# built on it is believed.
#
#   Rscript tests/conformance/check_v1_reader.R data-raw/upstream/core-contributor \
#     data-raw/upstream/cdisc-open-rules
#
# Four checks, each independent of the others:
#   1. Every case converts, or the reason it cannot is named.
#   2. Every cell value the reference engine reports in a finding in
#      results.json is the value the reader read from that cell. This is the
#      reference's own account of the data, so it tests the reader directly.
#      (The Validation sheets are written by hand and number their rows in
#      more than one way, so they are not used.)
#   3. Where cdisc-open-rules has the same case (same rule, same polarity and
#      number), each differing cell is classified. Verisian rebuilt much of the
#      test data, so substance differences are expected; a difference only of
#      format (1 against 1.0, a stray space, letter case, blank against
#      missing) is what a reader bug looks like, and is listed.
#   4. Column names with leading or trailing whitespace, which the reference
#      keeps and coreval's reader trims.
#
# Dev tooling only.

suppressMessages(devtools::load_all(quiet = TRUE))
source(file.path("tests", "conformance", "v1_case.R"))
args <- commandArgs(trailingOnly = TRUE)
v1_root <- file.path(args[[1]], "sdtm_rules")
old_root <- if (length(args) >= 2) args[[2]] else NA_character_

cases <- list.dirs(v1_root, recursive = TRUE)
cases <- sort(cases[grepl("/(positive|negative)/[^/]+$", cases)])
rules <- .coreval_env$data$rules
cat(length(cases), "cases\n\n")

# ---- 1. conversion ------------------------------------------------------------
stub_rule <- list(rule_type = "Record Data")
convert_errors <- character(0)
notes <- character(0)
converted <- list()
for (cs in cases) {
  out <- tempfile("chk_")
  r <- tryCatch(v1_convert_case(cs, stub_rule, out), error = function(e) e)
  if (inherits(r, "error")) {
    convert_errors <- c(convert_errors, sprintf("%s: %s", sub(".*sdtm_rules/", "", cs), conditionMessage(r)))
  } else {
    converted[[cs]] <- out
    if (!is.na(r$note)) notes <- c(notes, sprintf("%s: %s", sub(".*sdtm_rules/", "", cs), r$note))
  }
}
cat("== 1. conversion:", length(converted), "converted,", length(convert_errors), "could not be\n")
for (e in convert_errors) cat("   ", e, "\n")
for (n in notes) cat("   note:", n, "\n")

# ---- 2. the engine's own report of each cell ----------------------------------
# A finding in results.json carries the values the reference engine saw in the
# record it flagged. Where that value is a column of the dataset, the reader
# has to have read the same thing from the same cell. This is the strongest
# test available of the reader: it is the reference's own account of the data.
same_value <- function(ours, theirs, numeric) {
  if (is.null(theirs)) return(if (numeric) is.na(ours) else identical(ours, ""))
  theirs <- unlist(theirs)
  if (length(theirs) != 1) return(NA)
  if (numeric) {
    t <- suppressWarnings(as.numeric(theirs))
    return(!is.na(ours) && !is.na(t) && isTRUE(all.equal(ours, t)))
  }
  identical(ours, as.character(theirs))
}
checked <- 0L; matched <- 0L; mismatch <- character(0)
for (cs in names(converted)) {
  study <- tryCatch(read_study(file.path(converted[[cs]], "data")), error = function(e) NULL)
  if (is.null(study)) next
  r <- jsonlite::fromJSON(file.path(cs, "results", "results.json"), simplifyVector = FALSE)
  for (d in r$datasets) {
    ds <- study$datasets[[toupper(sub("[.][^.]*$", "", d$dataset %||% ""))]]
    if (is.null(ds)) next
    for (e in d$errors) {
      if (is.null(e$row) || e$row < 1 || e$row > nrow(ds$data)) next
      for (v in intersect(names(e$value), names(ds$data))) {
        ours <- ds$data[[v]][[e$row]]
        ok <- same_value(ours, e$value[[v]], is.numeric(ds$data[[v]]))
        if (is.na(ok)) next
        checked <- checked + 1L
        if (ok) matched <- matched + 1L else mismatch <- c(mismatch, sprintf(
          "%s %s row %d %s: read '%s', engine saw '%s'", sub(".*sdtm_rules/", "", cs), d$dataset, e$row, v,
          format(ours), if (is.null(e$value[[v]])) "NULL" else paste(unlist(e$value[[v]]), collapse = ",")))
      }
    }
  }
}
cat("\n== 2. cells the engine reported:", checked, "compared,", matched, "read the same,",
    length(mismatch), "differ\n")
for (m in utils::head(mismatch, 30)) cat("   ", m, "\n")

# ---- 3. against the same case in cdisc-open-rules ------------------------------
# A case in both repositories is often not the same case any more: Verisian
# rebuilt test data. So each differing cell is classified. A different number
# of rows or columns, or different values, is a fixture that changed. A value
# that differs only in format (1 against 1.0, a stray space, letter case, blank
# against missing) is what a reader bug looks like, and is listed.
classify <- function(x, y) {
  x <- as.character(x); y <- as.character(y)
  x[is.na(x)] <- "<NA>"; y[is.na(y)] <- "<NA>"
  d <- which(x != y)
  if (!length(d)) return(character(0))
  kind <- ifelse(trimws(x[d]) == trimws(y[d]), "whitespace",
          ifelse(tolower(x[d]) == tolower(y[d]), "case",
          ifelse(x[d] %in% c("", "<NA>") & y[d] %in% c("", "<NA>"), "blank vs missing",
          ifelse(!is.na(suppressWarnings(as.numeric(x[d]))) & !is.na(suppressWarnings(as.numeric(y[d]))) &
                   suppressWarnings(as.numeric(x[d])) == suppressWarnings(as.numeric(y[d])), "number format",
                 "substance"))))
  kind
}
if (!is.na(old_root)) {
  roots <- c("Published", "Deprecated", "Unpublished/FDA Business Rules", "Unpublished/SDTMIG")
  same <- 0L; changed <- 0L; compared <- 0L; suspicious <- character(0)
  kinds <- character(0)
  for (cs in names(converted)) {
    id <- basename(dirname(dirname(cs)))
    rel <- paste(basename(dirname(cs)), basename(cs), sep = "/")
    old <- NA_character_
    for (rt in roots) {
      cand <- file.path(old_root, rt, id, rel, "data")
      if (dir.exists(cand)) { old <- cand; break }
    }
    if (is.na(old)) next
    a <- tryCatch(read_study(old), error = function(e) NULL)
    b <- tryCatch(read_study(file.path(converted[[cs]], "data")), error = function(e) NULL)
    if (is.null(a) || is.null(b)) next
    compared <- compared + 1L
    case_kinds <- character(0); structural <- FALSE
    for (k in intersect(names(a$datasets), names(b$datasets))) {
      x <- a$datasets[[k]]$data; y <- b$datasets[[k]]$data
      if (!identical(sort(names(x)), sort(names(y))) || nrow(x) != nrow(y)) { structural <- TRUE; next }
      for (v in names(x)) case_kinds <- c(case_kinds, classify(x[[v]], y[[v]]))
    }
    if (!identical(sort(names(a$datasets)), sort(names(b$datasets)))) structural <- TRUE
    kinds <- c(kinds, case_kinds)
    if (!structural && !length(case_kinds)) { same <- same + 1L; next }
    changed <- changed + 1L
    odd <- setdiff(unique(case_kinds), "substance")
    if (length(odd)) suspicious <- c(suspicious, sprintf("%s/%s: %s", id, rel, paste(odd, collapse = ", ")))
  }
  cat("\n== 3. against cdisc-open-rules:", compared, "cases exist in both;", same, "identical,",
      changed, "changed\n")
  cat("   differing cells by kind (across cases with the same shape):\n")
  print(table(kinds))
  cat("   cases with a difference of format rather than substance:", length(suspicious), "\n")
  for (s in utils::head(suspicious, 30)) cat("    ", s, "\n")
}

# ---- 4. whitespace in column names ---------------------------------------------
padded <- character(0)
for (cs in names(converted)) {
  v <- data.table::fread(file.path(converted[[cs]], "data", "_variables.csv"), colClasses = "character")
  bad <- v$variable[v$variable != trimws(v$variable)]
  if (length(bad)) padded <- c(padded, sprintf("%s: '%s'", sub(".*sdtm_rules/", "", cs), paste(bad, collapse = "','")))
}
cat("\n== 4. column names with stray whitespace:", length(padded), "cases\n")
for (p in utils::head(padded, 10)) cat("   ", p, "\n")

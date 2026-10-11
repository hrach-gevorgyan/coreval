# Refresh the test suite's copies of CDISC's rule fixtures from the clone.
#
#   Rscript data-raw/sync_test_fixtures.R          # report what differs
#   Rscript data-raw/sync_test_fixtures.R --write   # refresh them
#
# tests/testthat/fixtures/core_rules/ holds a copy of selected CDISC test
# cases, so the unit tests can grade coreval against CDISC's own expected
# output without the clone being present. When CDISC changes a rule it usually
# changes that rule's expected output too, and a stale copy then tests coreval
# against an expectation nobody holds any more: adopting the October 2026 rule
# set left 33 of these copies behind, and the tests reading them failed while
# the conformance sweep against the live clone passed.
#
# Only cases ALREADY copied are refreshed. Which cases the suite keeps is a
# deliberate choice, so this never adds or removes a case; it mirrors the ones
# that are here, including files CDISC has added to them or removed from them.
#
# Maintainer tooling. Needs the clone described in CLAUDE.md. Not part of the
# package: data-raw/ is Rbuildignored.

args <- commandArgs(trailingOnly = TRUE)
write <- "--write" %in% args

local_root <- file.path("tests", "testthat", "fixtures", "core_rules")
upstream <- file.path("data-raw", "upstream", "cdisc-open-rules")
if (!dir.exists(local_root)) stop("no ", local_root, call. = FALSE)
if (!dir.exists(upstream)) stop("the rules clone is not at ", upstream, call. = FALSE)

# A rule's folder is not always its id, and it can sit under any of the three
# roots, so it is searched for rather than assumed.
roots <- c("Published", "Deprecated", file.path("Unpublished", "FDA Business Rules"),
           file.path("Unpublished", "SDTMIG"), file.path("Unpublished", "SENDIG"),
           "Unpublished")
find_rule_dir <- function(id) {
  for (root in roots) {
    for (folder in c(id, sub("^.*\\.", "", id))) {
      candidate <- file.path(upstream, root, folder)
      if (dir.exists(candidate)) return(candidate)
    }
  }
  NA_character_
}

file_list <- function(dir) {
  if (!dir.exists(dir)) return(character(0))
  sort(list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))
}

# CDISC's fixtures declare a case's standard in a file called `.env`. The copies
# here call it `_env`, because R CMD build leaves dotfiles out of the tarball
# and the file would then be missing from the installed package. The rename is
# the only difference allowed between a copy and its original, so it is applied
# on the way in rather than treated as a change.
local_name <- function(f) sub("(^|/)[.]env$", "\\1_env", f)

bytes <- function(path) readBin(path, "raw", file.size(path))

same <- function(here, there) {
  fa <- file_list(here)
  fb <- vapply(file_list(there), local_name, character(1), USE.NAMES = FALSE)
  if (!identical(fa, sort(fb))) return(FALSE)
  all(vapply(file_list(there), function(f) {
    identical(bytes(file.path(here, local_name(f))), bytes(file.path(there, f)))
  }, logical(1)))
}

ids <- sort(basename(list.dirs(local_root, recursive = FALSE)))
changed <- character(0)
missing <- character(0)

for (id in ids) {
  src_rule <- find_rule_dir(id)
  if (is.na(src_rule)) {
    missing <- c(missing, id)
    next
  }
  # Every case directory held locally, as "<positive|negative>/<nn>".
  cases <- list.dirs(file.path(local_root, id), recursive = TRUE, full.names = FALSE)
  cases <- cases[grepl("^(positive|negative)/[^/]+$", cases)]
  for (case in cases) {
    here <- file.path(local_root, id, case)
    there <- file.path(src_rule, case)
    if (!dir.exists(there)) {
      missing <- c(missing, paste0(id, "/", case))
      next
    }
    if (same(here, there)) next
    changed <- c(changed, paste0(id, "/", case))
    if (write) {
      unlink(here, recursive = TRUE)
      dir.create(here, recursive = TRUE, showWarnings = FALSE)
      for (f in file_list(there)) {
        target <- file.path(here, local_name(f))
        dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
        file.copy(file.path(there, f), target, overwrite = TRUE)
      }
    }
  }
}

cat(length(ids), "rules copied locally\n")
if (length(missing)) {
  cat("not found upstream (left alone):", paste(missing, collapse = ", "), "\n")
}
if (!length(changed)) {
  cat("every copy matches the clone\n")
} else {
  cat(length(changed), if (write) "refreshed:" else "differ from the clone:", "\n")
  for (c in changed) cat("  ", c, "\n")
  if (!write) cat("\nre-run with --write to refresh them\n")
}

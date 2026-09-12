# Shared helpers for the fixture-driven tests. testthat sources helper*.R
# before any test file, so these are available everywhere without being
# copy-pasted - `expected_violations_for()` was defined identically in eight
# separate test files.

#' Which records CDISC's own results.csv expects to be flagged
#'
#' For a `Sensitivity: Dataset` rule the sheet states a whole-dataset fact
#' rather than which rows, so every record carries the same answer.
#'
#' @param results_csv_path Path to a fixture's `results/results.csv`.
#' @param dataset_name Domain to read expectations for.
#' @param n Number of records in that dataset.
#' @param sensitivity The rule's declared `Sensitivity`.
#' @return A logical vector of length `n`.
expected_violations_for <- function(results_csv_path, dataset_name, n,
                                    sensitivity = "Record") {
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (identical(sensitivity, "Dataset")) {
    return(rep(nrow(results) > 0, n))
  }
  out <- rep(FALSE, n)
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

#' The case directories of one bundled fixture, asserting there are some
#'
#' A bare `Sys.glob()` returns `character(0)` for a directory that is not
#' there, and a `for` loop over nothing runs no assertions - so a fixture
#' going missing (renamed upstream, dropped from .Rbuildignore, lost in a
#' build) turned the test GREEN by doing nothing at all. That is this
#' package's characteristic failure mode living inside its own test suite,
#' so the glob asserts its result.
#'
#' @param id Rule id, e.g. `"CORE-000195"`.
#' @param polarity `"positive"` or `"negative"`.
#' @return A character vector of case directory paths, guaranteed non-empty.
fixture_cases <- function(id, polarity) {
  dirs <- Sys.glob(testthat::test_path("fixtures", "core_rules", id, polarity, "*"))
  testthat::expect_true(
    length(dirs) > 0,
    info = paste0("no ", polarity, " fixture cases found for ", id,
                  " - the fixture is missing, not the test passing")
  )
  dirs
}

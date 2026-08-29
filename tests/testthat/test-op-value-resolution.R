# Expected violation vector from a reference results.csv: one row per
# (Record, Variable) pair, filtered to one Dataset.
expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("value falls back to a literal when no column matches it, even with value_is_literal absent", {
  # CORE-000006: `DTHFL not_equal_to Y` has no value_is_literal at all, and
  # no column named "Y" exists in DM. Found via the conformance harness:
  # resolve_condition_value() used to return NULL whenever `value` wasn't a
  # literal AND wasn't a real column, silently making the condition always
  # false (NA -> FALSE) instead of falling back to the literal text "Y".
  rule <- .coreval_env$data$rules[["CORE-000006"]]
  expect_null(rule$check$all[[1]]$value_is_literal)

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000006", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$DM, domain = "DM")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DM", nrow(study$datasets$DM$data))
    )
  }
})

test_that("a multi-element literal value (e.g. is_not_contained_by: [Y, N]) resolves without value_is_literal", {
  # CORE-000123: `AESCAN is_not_contained_by [Y, N]` also has no
  # value_is_literal key. A multi-element `value` can never be a single
  # column reference, so it must fall through to the literal array on its
  # own - no length-based special-casing needed (an earlier, overly clever
  # version of resolve_condition_value() special-cased vectors for the
  # grouping operators and broke this case as a side effect).
  rule <- .coreval_env$data$rules[["CORE-000123"]]
  cond <- rule$check$all[[2]]
  expect_null(cond$value_is_literal)
  expect_equal(cond$value, c("Y", "N"))

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000123", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$AE, domain = "AE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "AE", nrow(study$datasets$AE$data))
    )
  }
})

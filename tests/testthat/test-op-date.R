expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("invalid_date rejects a syntactically-shaped but calendar-invalid date (Feb 30)", {
  # CORE-000505: TSVAL invalid_date. "2023-02-30" matches the date regex's
  # shape (day 3[01]|0[1-9]|[12][0-9] doesn't know which months have 30
  # days) but isn't a real calendar date - the reference engine's isoparse
  # rejects it. An earlier version of is_valid_date_str() only checked
  # regex shape and missed this.
  rule <- .coreval_env$data$rules[["CORE-000505"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000505", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$TS, domain = "TS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "TS", nrow(study$datasets$TS$data))
    )
  }
})

test_that("invalid_duration matches CDISC's reference results.csv", {
  rule <- .coreval_env$data$rules[["CORE-000294"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000294", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$TS, domain = "TS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "TS", nrow(study$datasets$TS$data))
    )
  }
})

test_that("contains matches CDISC's reference results.csv", {
  rule <- .coreval_env$data$rules[["CORE-000305"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000305", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$AE, domain = "AE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "AE", nrow(study$datasets$AE$data))
    )
  }
})

test_that("detect_precision_one handles the '2024---15' placeholder-dash convention", {
  # Month is unknown (--), but day is present. Precision caps at year-level
  # anyway, since the reference engine's own precision detection is
  # monotonic: once one component is missing, later ones don't count.
  expect_equal(detect_precision_one("2024---15"), 0L)
  expect_equal(detect_precision_one("2024-03-15"), 2L)
  expect_equal(detect_precision_one("2024-03"), 1L)
  expect_true(is.na(detect_precision_one("not-a-date")))
})

test_that("date comparisons truncate both sides to their common precision", {
  # "2024-03" (month precision) vs "2024-03-15" (day precision): truncated
  # to month precision, both become 2024-03 - equal, so lt is FALSE.
  expect_false(compare_dates_one("2024-03", "2024-03-15", "lt"))
  expect_true(compare_dates_one("2024-02", "2024-03-15", "lt"))
  expect_true(compare_dates_one("2024-03-15", "2024-03-15", "eq"))
  # Equal truncated values but different precision are never "equal".
  expect_false(compare_dates_one("2024", "2024-01-01", "eq"))
})

test_that("is_valid_date_str validates real calendar dates, not just regex shape", {
  expect_false(is_valid_date_str("2023-02-30"))
  expect_true(is_valid_date_str("2023-02-28"))
  expect_true(is_valid_date_str("2024-02-29")) # leap year
  expect_false(is_valid_date_str("2023-02-29")) # not a leap year
  expect_true(is_valid_date_str("2024---15")) # uncertain dates skip calendar check
})

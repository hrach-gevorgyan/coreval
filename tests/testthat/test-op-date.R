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

test_that("date comparisons apply the timezone offset instead of discarding it", {
  # Bug: the timezone component was parsed by the regex but never extracted
  # or applied - "10:00+02:00" (= 08:00 UTC) and "08:00Z" were compared as
  # if both were 10:00 and 08:00 wall-clock, giving a wrong ordering.
  # "2024-01-01T10:00:00+02:00" is truly 08:00 UTC = same instant as
  # "2024-01-01T08:00:00Z".
  expect_true(compare_dates_one("2024-01-01T10:00:00+02:00", "2024-01-01T08:00:00Z", "eq"))
  expect_false(compare_dates_one("2024-01-01T10:00:00+02:00", "2024-01-01T09:00:00Z", "eq"))
  expect_true(compare_dates_one("2024-01-01T10:00:00+02:00", "2024-01-01T09:00:00Z", "lt"))
  expect_true(compare_dates_one("2024-01-01T06:00:00-02:00", "2024-01-01T09:00:00Z", "lt"))
})

test_that("a bare year/month date does not borrow precision or value from a '/'-interval's second date", {
  # Bug: extract_date_components_one() fell back to the interval ("i...")
  # group per-component, so a primary date missing e.g. day precision would
  # incorrectly borrow the SECOND date's day/month/year from across the "/".
  # "2024-01/2024-06" must report month precision (from its own "01"), not
  # mix in "06" from the second date.
  expect_equal(detect_precision_one("2024-01/2024-06"), 1L)
  expect_true(compare_dates_one("2024-01/2024-06", "2024-02", "lt"))
})

test_that("invalid_duration rejects a comma used as a component separator", {
  # Bug: the duration regex allowed an optional comma BETWEEN components
  # (e.g. "P1Y,2M"), but ISO 8601 only allows a comma as a decimal
  # separator WITHIN one component (e.g. "P1,5Y").
  data <- data.table::data.table(X = c("P1Y2M3D", "P1Y,2M", "P1,5Y"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "invalid_duration")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, TRUE, FALSE))
})

test_that("is_complete_date's result carries no names (vapply() over a character vector defaults to USE.NAMES = TRUE)", {
  # Bug: vapply(ctx$target, ...) with a character ctx$target and no
  # USE.NAMES = FALSE names the result by the date strings themselves - a
  # cosmetic issue that nonetheless makes identical()/expect_equal() see a
  # named vs. unnamed vector as unequal even when every value matches.
  data <- data.table::data.table(X = c("2024-03-15", "2024-03"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "is_complete_date")
  result <- evaluate_check(check, dataset, "TS")
  expect_equal(result, c(TRUE, FALSE))
  expect_null(names(result))
})

test_that("is_valid_date_str validates real calendar dates, not just regex shape", {
  expect_false(is_valid_date_str("2023-02-30"))
  expect_true(is_valid_date_str("2023-02-28"))
  expect_true(is_valid_date_str("2024-02-29")) # leap year
  expect_false(is_valid_date_str("2023-02-29")) # not a leap year
  expect_true(is_valid_date_str("2024---15")) # uncertain dates skip calendar check
})

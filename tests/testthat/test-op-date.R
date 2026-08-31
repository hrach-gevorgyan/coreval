expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("invalid_date rejects a syntactically-shaped but calendar-invalid date (Feb 30), and a day without a month", {
  # CORE-000505: TSVAL invalid_date.
  #   negative/01, positive/01: "2023-02-30" matches the date regex's shape
  #     (day 3[01]|0[1-9]|[12][0-9] doesn't know which months have 30 days)
  #     but isn't a real calendar date - the reference engine's isoparse
  #     rejects it. An earlier version of is_valid_date_str() only checked
  #     regex shape and missed this.
  #   negative/02, positive/02: "2003-20" (a single dash, no uncertainty
  #     marker) matches the regex's shape too - "20" fits the DAY pattern,
  #     with the month group simply skipped - but isoparse can't parse
  #     "year-day" with no month, and the reference engine only falls back
  #     to the loose shape check for a string that actually contains an
  #     uncertainty marker ("/", "--", "-:"), which this one doesn't. An
  #     earlier version of is_valid_date_str() had no such gate at all.
  rule <- .coreval_env$data$rules[["CORE-000505"]]
  for (case in c("negative/01", "positive/01", "negative/02", "positive/02")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000505", case)
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$TS, domain = "TS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "TS", nrow(study$datasets$TS$data)),
      info = case
    )
  }
})

test_that("is_valid_date_str rejects a component skipped without an explicit uncertainty marker", {
  expect_false(is_valid_date_str("2003-20")) # single dash, day without month
  expect_true(is_valid_date_str("2024---15")) # "--" marks month as an explicit, known-missing placeholder
  expect_true(is_valid_date_str("2024-03"))
  expect_true(is_valid_date_str("2024-03-15"))
})

test_that("invalid_duration's negative flag is a per-operator parameter, not a generic result negation (CORE-000730/CORE-000731)", {
  # `negative: true` in these rules' Check ("TSVAL negative: true, operator:
  # invalid_duration") means "allow a negative duration sign", per
  # upstream's own comment - NOT "negate the whole condition result". An
  # earlier version of evaluate_condition() also generically negated the
  # result whenever `negative: true` was set, double-negating
  # invalid_duration's own already-negative-aware result and silently
  # flagging a perfectly valid duration like "P40Y" as invalid.
  for (id in c("CORE-000730", "CORE-000731")) {
    rule <- .coreval_env$data$rules[[id]]
    for (case in c("negative", "positive")) {
      dir <- test_path("fixtures", "core_rules", id, case, "01")
      study <- read_study(file.path(dir, "data"))
      actual <- evaluate_rule(rule, study$datasets$TS, domain = "TS")
      expect_equal(
        actual,
        expected_violations_for(file.path(dir, "results", "results.csv"), "TS", nrow(study$datasets$TS$data)),
        info = paste(id, case)
      )
    }
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

test_that("days_in_month is correct for vectors, not just single values", {
  # The one-liner it replaced built its lookup table with
  # `c(31, ifelse(leap, 29, 28), 31, ...)`, which yields ONE element per year
  # instead of one per month - so for n years the table was 11 + n long and
  # every month from March on indexed the wrong slot. Correct for a single
  # value, wrong for a column, and the per-row date operators hid it.
  expect_equal(
    days_in_month(c(2003, 2004, 2003, 2024, 1900, 2000), c(11, 2, 2, 2, 2, 2)),
    c(30, 29, 28, 29, 28, 29)
  )
  # Century rule both ways, since that is where a naive leap test fails.
  expect_equal(days_in_month(1900, 2), 28)
  expect_equal(days_in_month(2000, 2), 29)
})

test_that("the vectorised date helpers agree with checking one value at a time", {
  # The vectorised path must be a pure speed change. "2003-11-31" is the case
  # that caught the days_in_month bug: valid-looking, and November has 30 days.
  v <- c(
    "2003-11-31", "2003-02-31", "2004-02-29", "2003-02-28", "2024-02-30",
    "2003-20", "2023-02-30", "2024---15", "2024-03", "2024", "", NA,
    "2024-01-10T08:30:00", "2024-01-10T08:30:00+02:00", "not-a-date"
  )
  one_at_a_time <- vapply(v, function(z) is_valid_date_str(z), logical(1), USE.NAMES = FALSE)
  expect_equal(is_valid_date_str(v), one_at_a_time)

  expect_equal(
    detect_precision(v),
    vapply(v, detect_precision_one, integer(1), USE.NAMES = FALSE)
  )

  # And the comparison operator itself, pairwise against its scalar form.
  a <- c("2024-01-10", "2024-01-10", "2024", "2024-01-10", "")
  b <- c("2024-01-11", "2024-01-10", "2024-01-01", "", "2024-01-10")
  for (op in c("eq", "ne", "gt", "lt", "ge", "le")) {
    expect_equal(
      compare_dates(a, b, op),
      vapply(seq_along(a), function(i) compare_dates_one(a[i], b[i], op), logical(1)),
      info = op
    )
  }
})

test_that("the date helpers survive empty and all-missing input", {
  expect_equal(is_valid_date_str(character(0)), logical(0))
  expect_equal(detect_precision(character(0)), integer(0))
  expect_equal(compare_dates(character(0), character(0), "eq"), logical(0))
  expect_equal(is_valid_date_str(c(NA_character_, NA_character_)), c(FALSE, FALSE))
})

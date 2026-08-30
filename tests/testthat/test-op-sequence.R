expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("does_not_have_next_corresponding_record matches CDISC's reference results.csv (CORE-000352)", {
  # "SEENDTC does_not_have_next_corresponding_record ordering: SESEQ,
  # value: SESTDTC, within: USUBJID" - flags a subject's row whenever its
  # SEENDTC doesn't equal the following record's SESTDTC.
  rule <- .coreval_env$data$rules[["CORE-000352"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000352", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SE", nrow(study$datasets$SE$data))
    )
  }
})

test_that("does_not_have_next_corresponding_record never flags a group's last row", {
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    SESEQ = c(1, 2, 1),
    SESTDTC = c("2020-01-01", "2020-01-05", "2020-02-01"),
    SEENDTC = c("2020-01-05", "2020-01-10", "2020-02-01")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "SEENDTC", operator = "does_not_have_next_corresponding_record", ordering = "SESEQ", value = "SESTDTC", within = "USUBJID")
  # row1: SEENDTC == row2's SESTDTC -> not flagged. row2: last for S1 -> not flagged.
  # row3: last for S2 -> not flagged.
  expect_equal(evaluate_check(check, dataset, "SE"), c(FALSE, FALSE, FALSE))
})

test_that("empty_within_except_last_row matches CDISC's reference results.csv (CORE-000527)", {
  rule <- .coreval_env$data$rules[["CORE-000527"]]
  for (case in c("negative/01", "positive/01", "positive/02")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000527", case)
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SE", nrow(study$datasets$SE$data))
    )
  }
})

test_that("empty_within_except_last_row allows a blank target only on the group's last row", {
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    SESTDTC = c("2020-01-01", "2020-01-05", "2020-02-01"),
    SEENDTC = c("", "", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "SEENDTC", operator = "empty_within_except_last_row", ordering = "SESTDTC", value = "USUBJID")
  expect_equal(evaluate_check(check, dataset, "SE"), c(TRUE, FALSE, FALSE))
})

# Expected violation vector from a reference results.csv: one row per
# (Record, Variable) pair: distinct Record values are the violating rows.
expected_violations <- function(results_csv_path, n) {
  out <- rep(FALSE, n)
  if (file.exists(results_csv_path)) {
    results <- data.table::fread(results_csv_path, colClasses = "character")
    if (nrow(results) > 0) {
      out[as.integer(unique(results$Record))] <- TRUE
    }
  }
  out
}

test_that("evaluate_rule matches CDISC's reference results.csv - value_is_literal: true", {
  # CORE-000001: IECAT equal_to "INCLUSION" (literal) AND IEORRES not_equal_to
  # "N" (literal). Both conditions have value_is_literal: true.
  rule <- .coreval_env$data$rules[["CORE-000001"]]
  expect_true(isTRUE(rule$check$all[[1]]$value_is_literal))

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000001", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$IE, domain = "IE")
    expect_equal(
      actual,
      expected_violations(file.path(dir, "results", "results.csv"), nrow(study$datasets$IE$data))
    )
  }
})

test_that("evaluate_rule matches CDISC's reference results.csv - value_is_literal absent (column reference)", {
  # CORE-000025: IESTRESC not_equal_to IEORRES - value_is_literal is absent,
  # so `value: IEORRES` must be resolved as a column reference, not the
  # literal string "IEORRES".
  rule <- .coreval_env$data$rules[["CORE-000025"]]
  expect_null(rule$check$all[[1]]$value_is_literal)

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000025", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$IE, domain = "IE")
    expect_equal(
      actual,
      expected_violations(file.path(dir, "results", "results.csv"), nrow(study$datasets$IE$data))
    )
  }
})

test_that("evaluate_check combines all/any/not correctly", {
  data <- data.table::data.table(A = c("X", "Y", "X", "Y"), B = c(1, 2, 3, 4))
  dataset <- list(data = data, meta = NULL)

  all_check <- list(all = list(
    list(name = "A", operator = "equal_to", value = "X", value_is_literal = TRUE),
    list(name = "B", operator = "less_than", value = 3, value_is_literal = TRUE)
  ))
  expect_equal(evaluate_check(all_check, dataset, "TS"), c(TRUE, FALSE, FALSE, FALSE))

  any_check <- list(any = list(
    list(name = "A", operator = "equal_to", value = "X", value_is_literal = TRUE),
    list(name = "B", operator = "greater_than", value = 3, value_is_literal = TRUE)
  ))
  expect_equal(evaluate_check(any_check, dataset, "TS"), c(TRUE, FALSE, TRUE, TRUE))

  not_check <- list(not = list(name = "A", operator = "equal_to", value = "X", value_is_literal = TRUE))
  expect_equal(evaluate_check(not_check, dataset, "TS"), c(FALSE, TRUE, FALSE, TRUE))
})

test_that("exists/not_exists are dataset-level facts (a scalar), not per-row", {
  # A bare exists/not_exists condition describes the dataset, not any one
  # record, so it stays a length-1 scalar here. It only becomes per-row when
  # combined (via all/any) with a row-level condition, through R's normal
  # length-1 recycling in `&`/`|` - see the next test.
  data <- data.table::data.table(A = c("X", "Y"))
  dataset <- list(data = data, meta = NULL)

  expect_true(evaluate_check(list(name = "A", operator = "exists"), dataset, "TS"))
  expect_false(evaluate_check(list(name = "B", operator = "exists"), dataset, "TS"))
  expect_true(evaluate_check(list(name = "B", operator = "not_exists"), dataset, "TS"))
})

test_that("exists/not_exists resolve a Domain Presence Check's bare domain-code name against the study", {
  # "name: DM, operator: not_exists" in a Domain Presence Check asks whether
  # the DM dataset is present anywhere in the study, not whether a column
  # literally named "DM" exists in the dataset currently being checked.
  study_without_dm <- list(datasets = list(AE = list(data = data.table::data.table(A = "X"), meta = NULL)))
  expect_true(evaluate_check(list(name = "DM", operator = "not_exists"), study_without_dm$datasets$AE, "AE", study = study_without_dm))
  expect_false(evaluate_check(list(name = "DM", operator = "exists"), study_without_dm$datasets$AE, "AE", study = study_without_dm))

  study_with_dm <- list(datasets = list(
    AE = list(data = data.table::data.table(A = "X"), meta = NULL),
    DM = list(data = data.table::data.table(USUBJID = "S1"), meta = NULL)
  ))
  expect_false(evaluate_check(list(name = "DM", operator = "not_exists"), study_with_dm$datasets$AE, "AE", study = study_with_dm))

  # Without a study (e.g. a bare unit test dataset), falls back to the
  # ordinary "is this a real column" behavior rather than erroring.
  data <- data.table::data.table(A = "X")
  dataset <- list(data = data, meta = NULL)
  expect_true(evaluate_check(list(name = "DM", operator = "not_exists"), dataset, "AE"))
})

test_that("a dataset-level exists condition recycles correctly when combined with a row-level one", {
  data <- data.table::data.table(A = c("X", "Y", "X"))
  dataset <- list(data = data, meta = NULL)

  check <- list(all = list(
    list(name = "A", operator = "exists"),
    list(name = "A", operator = "equal_to", value = "X", value_is_literal = TRUE)
  ))
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, FALSE, TRUE))
})

test_that("-- variable name templates resolve to the dataset's domain code", {
  data <- data.table::data.table(AEOCCUR = c("Y", ""))
  dataset <- list(data = data, meta = NULL)

  expect_equal(
    evaluate_check(list(name = "--OCCUR", operator = "non_empty"), dataset, "AE"),
    c(TRUE, FALSE)
  )
})

test_that("empty/non_empty use '' for character blanks and NA for numeric", {
  data <- data.table::data.table(CHR = c("Y", ""), NUM = c(1, NA_real_))
  dataset <- list(data = data, meta = NULL)

  expect_equal(evaluate_check(list(name = "CHR", operator = "empty"), dataset, "TS"), c(FALSE, TRUE))
  expect_equal(evaluate_check(list(name = "NUM", operator = "non_empty"), dataset, "TS"), c(TRUE, FALSE))
})

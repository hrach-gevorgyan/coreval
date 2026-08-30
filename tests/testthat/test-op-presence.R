expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("inconsistent_enumerated_columns matches CDISC's reference results.csv (CORE-000780)", {
  # "--VAL inconsistent_enumerated_columns" - flags a gap in the
  # COVAL/COVAL1/COVAL2 family: once one is blank, every later one in the
  # sequence must be blank too.
  rule <- .coreval_env$data$rules[["CORE-000780"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000780", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "CO")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "CO", nrow(study$datasets$CO$data))
    )
  }
})

test_that("inconsistent_enumerated_columns flags a gap in either direction", {
  data <- data.table::data.table(
    COVAL = c("x", "", "y", "x"),
    COVAL1 = c("", "a", "", "y"),
    COVAL2 = c("", "b", "z", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "COVAL", operator = "inconsistent_enumerated_columns")
  # row1: x,"","" - populated then nothing but blanks - fine.
  # row2: "","a","b" - COVAL skipped but COVAL1/COVAL2 populated - gap.
  # row3: y,"","z" - COVAL1 skipped but COVAL2 populated - gap.
  # row4: x,y,"" - no gap (blank only at the end).
  expect_equal(evaluate_check(check, dataset, "CO"), c(FALSE, TRUE, TRUE, FALSE))
})

test_that("inconsistent_enumerated_columns is FALSE when there's no numbered sibling column", {
  data <- data.table::data.table(COVAL = c("x", ""))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "COVAL", operator = "inconsistent_enumerated_columns")
  expect_equal(evaluate_check(check, dataset, "CO"), c(FALSE, FALSE))
})

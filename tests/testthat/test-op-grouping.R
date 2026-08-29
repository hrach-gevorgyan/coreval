# Expected violation vector from a reference results.csv: one row per
# (Record, Variable) pair, filtered to one Dataset - distinct Record values
# are the violating rows.
expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("is_not_unique_set matches CDISC's reference results.csv (CORE-000186)", {
  # SUBJID is_not_unique_set [STUDYID]: flags duplicate (SUBJID, STUDYID)
  # combinations anywhere in the dataset.
  rule <- .coreval_env$data$rules[["CORE-000186"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000186", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$DM, domain = "DM")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DM", nrow(study$datasets$DM$data))
    )
  }
})

test_that("is_not_unique_relationship matches CDISC's reference results.csv (CORE-000132)", {
  # ETCD <-> ELEMENT must be a one-to-one mapping within the TE dataset.
  rule <- .coreval_env$data$rules[["CORE-000132"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000132", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$TE, domain = "TE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "TE", nrow(study$datasets$TE$data))
    )
  }
})

test_that("is_not_unique_set treats blanks as a real, matching value when grouping", {
  data <- data.table::data.table(A = c("", "", "X"), B = c("Y", "Y", "Y"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("is_not_unique_set supports a multi-column comparator", {
  data <- data.table::data.table(
    A = c("X", "X", "X"),
    B = c("Y", "Y", "Z"),
    C = c("1", "1", "1")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = c("B", "C"))
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("is_not_unique_relationship flags both sides of an inconsistent mapping", {
  # ETCD "LOW" maps to two different ELEMENTs -> both LOW rows flagged.
  # ETCD "HIGH" and "SCREEN" are consistent -> not flagged.
  data <- data.table::data.table(
    ETCD = c("SCREEN", "LOW", "HIGH", "LOW"),
    ELEMENT = c("Screening", "Elem A", "High Dose", "Elem B")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, TRUE, FALSE, TRUE))
})

test_that("is_not_unique_relationship flags a value paired with both a real value and a blank", {
  data <- data.table::data.table(
    ETCD = c("A", "A", "B"),
    ELEMENT = c("X", "", "Y")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  # ETCD "A" maps to "X" in one row and blank in another - inconsistent.
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("is_not_unique_relationship never flags a fully blank pair", {
  data <- data.table::data.table(ETCD = c("", "A"), ELEMENT = c("", "X"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE))
})

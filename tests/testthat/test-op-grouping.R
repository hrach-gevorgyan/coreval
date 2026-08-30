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

test_that("is_inconsistent_across_dataset matches CDISC's reference results.csv (CORE-000612)", {
  # PCSTRESU is_inconsistent_across_dataset [PCTESTCD]: flags rows whose
  # PCSTRESU differs from other rows sharing the same PCTESTCD.
  rule <- .coreval_env$data$rules[["CORE-000612"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000612", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$PC, domain = "PC")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "PC", nrow(study$datasets$PC$data))
    )
  }
})

test_that("is_inconsistent_across_dataset flags every row in a group with >1 distinct non-blank target value", {
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1, 2),
    ELTM = c("PT1H", "PT2H", "PT1H", "PT1H")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(TRUE, TRUE, TRUE, FALSE))
})

test_that("is_inconsistent_across_dataset ignores blank target values when checking consistency", {
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1),
    ELTM = c("PT1H", "PT1H", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(FALSE, FALSE, FALSE))
})

test_that("has_same_values matches CDISC's reference results.csv (CORE-000365)", {
  # "MHCAT non_empty AND MHCAT has_same_values" - flags every record when
  # the whole dataset's non-blank MHCAT values are all identical.
  rule <- .coreval_env$data$rules[["CORE-000365"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000365", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "MH")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "MH", nrow(study$datasets$MH$data))
    )
  }
})

test_that("has_same_values is dataset-level: FALSE for every row once >1 distinct non-blank value exists", {
  data <- data.table::data.table(CAT = c("A", "A", "B"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "CAT", operator = "has_same_values")
  expect_equal(evaluate_check(check, dataset, "MH"), c(FALSE, FALSE, FALSE))

  data2 <- data.table::data.table(CAT = c("A", "A", "A"))
  dataset2 <- list(data = data2, meta = NULL)
  expect_equal(evaluate_check(check, dataset2, "MH"), c(TRUE, TRUE, TRUE))
})

test_that("present_on_multiple_rows_within matches CDISC's reference results.csv (CORE-000363)", {
  # "DSDECOD present_on_multiple_rows_within: USUBJID" - flags every row
  # whose DSDECOD value appears on more than one row for the same subject.
  rule <- .coreval_env$data$rules[["CORE-000363"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000363", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "DS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DS", nrow(study$datasets$DS$data))
    )
  }
})

test_that("present_on_multiple_rows_within/not_present_on_multiple_rows_within flag the right rows", {
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S1", "S2"),
    DSDECOD = c("A", "A", "B", "A")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "DSDECOD", operator = "present_on_multiple_rows_within", within = "USUBJID")
  expect_equal(evaluate_check(check, dataset, "DS"), c(TRUE, TRUE, FALSE, FALSE))

  check2 <- list(name = "DSDECOD", operator = "not_present_on_multiple_rows_within", within = "USUBJID")
  expect_equal(evaluate_check(check2, dataset, "DS"), c(FALSE, FALSE, TRUE, TRUE))
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

test_that("is_not_unique_set does not collide the blank sentinel with a real value of the text \"NA\"", {
  # Bug: an earlier version used the literal string "NA" as its blank
  # sentinel, which collided with a genuine data value of "NA" - a row
  # with a real "NA" value and a row with an actual blank would be treated
  # as duplicates of each other even though they aren't.
  data <- data.table::data.table(A = c("NA", "", "X"), B = c("Y", "Y", "Y"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE, FALSE))
})

test_that("is_not_unique_set does not collide keys across a multi-column boundary", {
  # Bug: pasting columns together with no separator lets ("1", "23") and
  # ("12", "3") both collapse to the same key "123".
  data <- data.table::data.table(A = c("1", "12"), B = c("23", "3"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE))
})

test_that("is_not_unique_relationship never flags a fully blank pair", {
  data <- data.table::data.table(ETCD = c("", "A"), ELEMENT = c("", "X"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE))
})

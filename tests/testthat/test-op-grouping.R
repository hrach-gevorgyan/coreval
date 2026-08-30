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

test_that("is_inconsistent_across_dataset's positive (compliant) CDISC fixture still matches (CORE-000612)", {
  # PCSTRESU is_inconsistent_across_dataset [PCTESTCD]. CORE-000612's own
  # NEGATIVE fixture is stale relative to the pinned upstream engine: it
  # expects EVERY row in an inconsistent PCTESTCD group to be flagged (e.g.
  # a 5-ug/mL-vs-1-bottles split flags all 6 rows), but the engine's own
  # bundled unit tests (test_check_operators/test_value_set_checks.py::
  # test_is_inconsistent_across_dataset, parametrized case
  # ("STRESU", "TESTCD", ..., [False, False, True, False])) prove the real
  # algorithm (`_check_inconsistency()` in check_operators/
  # dataframe_operators.py) flags only the MINORITY value's rows, unless
  # there's a tie for the majority (then it flags everyone) - see
  # flag_inconsistent_minority() in op_grouping.R. Only the POSITIVE
  # (all-consistent, zero expected violations) fixture is asserted here;
  # the negative one is intentionally not, since coreval matches the
  # engine's own source and unit tests over a stale results.csv.
  rule <- .coreval_env$data$rules[["CORE-000612"]]
  dir <- test_path("fixtures", "core_rules", "CORE-000612", "positive", "01")
  study <- read_study(file.path(dir, "data"))
  actual <- evaluate_rule(rule, study$datasets$PC, domain = "PC")
  expect_equal(
    actual,
    expected_violations_for(file.path(dir, "results", "results.csv"), "PC", nrow(study$datasets$PC$data))
  )
})

test_that("is_inconsistent_across_dataset's minority-flagging matches CDISC's reference results.csv (CORE-000142)", {
  # --ELTM is_inconsistent_across_dataset [DOMAIN, VISITNUM, --TPTREF,
  # --TPTNUM], combined with sibling non_empty conditions on --TPT/--TPTNUM/
  # --ELTM. positive/01's FT data has a 3-PT1H-vs-1-PT2H group - the
  # single PT2H row is the minority, but it's excluded from the overall
  # Check anyway by a sibling non_empty(--TPT) condition, so NEITHER the
  # 3 majority rows nor the 1 (already-excluded) minority row end up
  # violating - the whole case is compliant, unlike what a
  # flag-everyone-in-an-inconsistent-group algorithm would wrongly report.
  rule <- .coreval_env$data$rules[["CORE-000142"]]
  for (case in c("negative/01", "positive/01", "positive/03")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000142", case)
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "FT")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "FT", nrow(study$datasets$FT$data)),
      info = case
    )
  }
})

test_that("is_inconsistent_across_dataset flags only the minority value's rows within a group", {
  # 3 "PT1H" vs 1 "PT2H" in the VISITNUM=1 group - PT1H is the majority, so
  # only the single PT2H row (the minority) is flagged, not every row.
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1, 2),
    ELTM = c("PT1H", "PT2H", "PT1H", "PT1H")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(FALSE, TRUE, FALSE, FALSE))
})

test_that("is_inconsistent_across_dataset flags every row in a group on a tie for the majority value", {
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1, 1),
    ELTM = c("PT1H", "PT1H", "PT2H", "PT2H")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(TRUE, TRUE, TRUE, TRUE))
})

test_that("is_inconsistent_across_dataset treats a blank target as its own value, not an exclusion", {
  # A blank ELTM is a distinct value like any other - here it's the
  # minority (1 blank vs 2 "PT1H"), so only the blank row is flagged.
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1),
    ELTM = c("PT1H", "PT1H", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(FALSE, FALSE, TRUE))
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

test_that("is_not_unique_set resolves \"--\" prefixes in its grouping columns (CORE-000914)", {
  # The reference engine's _resolve_prefixes() applies replace_all_prefixes()
  # to any LIST-valued operator argument, so a comparator like
  # ["--TESTCD", "USUBJID"] arrives fully resolved. Left raw, the "--"
  # entries match no real column, are silently dropped, and the uniqueness
  # key collapses to whatever happened to be literal - a far looser key
  # that reports masses of spurious duplicates.
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2", "S2"),
    LBTESTCD = c("NA", "K", "NA", "NA"),
    LBBLFL = c("Y", "Y", "Y", "Y")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(
    name = "LBBLFL", operator = "is_not_unique_set",
    value = c("--TESTCD", "USUBJID")
  )
  # Resolved key is (LBBLFL, LBTESTCD, USUBJID): only S2's two NA rows
  # duplicate. Unresolved, the key degrades to (LBBLFL, USUBJID) and would
  # wrongly flag all four rows.
  expect_equal(evaluate_check(check, dataset, "LB"), c(FALSE, FALSE, TRUE, TRUE))
})

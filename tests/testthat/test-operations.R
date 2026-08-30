expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("distinct (ungrouped) matches CDISC's reference results.csv - cross-dataset binding", {
  # CORE-000036: $tv_visit = distinct VISIT values from the TV dataset,
  # used to check SV.VISIT is_not_contained_by $tv_visit. Needs the full
  # study (TV and SV are different datasets) - the exact case that pushed
  # evaluate_rule() to accept a study, not just one dataset.
  rule <- .coreval_env$data$rules[["CORE-000036"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000036", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SV")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SV", nrow(study$datasets$SV$data))
    )
  }
})

test_that("record_count (grouped, filtered) matches CDISC's reference results.csv", {
  # CORE-000214: $disposition_event_count = record_count of DS rows where
  # DSCAT == "DISPOSITION EVENT", grouped by [USUBJID, EPOCH] - a grouped
  # binding joined back onto each row of the same (DS) dataset.
  rule <- .coreval_env$data$rules[["CORE-000214"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000214", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "DS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DS", nrow(study$datasets$DS$data))
    )
  }
})

test_that("evaluate_rule accepts a plain dataset (no Operations) as before", {
  # Backward compatibility: passing list(data=, meta=) directly, without a
  # $datasets wrapper, must keep working for rules with no Operations.
  data <- data.table::data.table(A = c("X", "Y"))
  dataset <- list(data = data, meta = NULL)
  rule <- list(check = list(name = "A", operator = "equal_to", value = "X", value_is_literal = TRUE))
  expect_equal(evaluate_rule(rule, dataset, "TS"), c(TRUE, FALSE))
})

test_that("compute_operation: distinct excludes blank/NA and sorts", {
  study <- list(datasets = list(TV = list(
    data = data.table::data.table(VISIT = c("WEEK 2", "SCREENING", "", "SCREENING")),
    meta = NULL
  )))
  op <- list(domain = "TV", id = "$v", name = "VISIT", operator = "distinct")
  binding <- compute_operation(op, study, "TV", study$datasets$TV)
  expect_equal(binding$kind, "scalar")
  expect_equal(binding$value, c("SCREENING", "WEEK 2"))
})

test_that("compute_operation: record_count with a filter and no grouping is a single count", {
  study <- list(datasets = list(DS = list(
    data = data.table::data.table(DSCAT = c("DISPOSITION EVENT", "OTHER", "DISPOSITION EVENT")),
    meta = NULL
  )))
  op <- list(domain = "DS", id = "$n", name = "DSCAT", operator = "record_count", filter = list(DSCAT = "DISPOSITION EVENT"))
  binding <- compute_operation(op, study, "DS", study$datasets$DS)
  expect_equal(binding$kind, "scalar")
  expect_equal(binding$value, 2)
})

test_that("compute_operation: record_count grouped joins back per-row via resolve_binding", {
  ds_data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    EPOCH = c("A", "A", "A"),
    DSCAT = c("DISPOSITION EVENT", "OTHER", "OTHER")
  )
  study <- list(datasets = list(DS = list(data = ds_data, meta = NULL)))
  op <- list(
    domain = "DS", id = "$n", name = "DSCAT", operator = "record_count",
    group = c("USUBJID", "EPOCH"), filter = list(DSCAT = "DISPOSITION EVENT")
  )
  binding <- compute_operation(op, study, "DS", study$datasets$DS)
  expect_equal(binding$kind, "grouped")
  resolved <- resolve_binding(binding, study$datasets$DS)
  expect_equal(resolved, c(1, 1, 0))
})

test_that("compute_dy returns NA (not a crash) for a USUBJID with no matching DM record", {
  # Bug: `rfstdtc_by_subject[[usubjid[i]]]` on an atomic named vector errors
  # ("subscript out of bounds") for a name that isn't present, instead of
  # returning NULL like list indexing would - crashing the whole `dy`
  # computation for the entire dataset instead of yielding NA for that row.
  study <- list(datasets = list(
    DM = list(data = data.table::data.table(USUBJID = "S1", RFSTDTC = "2024-01-01"), meta = NULL),
    AE = list(data = data.table::data.table(USUBJID = c("S1", "S2"), AESTDTC = c("2024-01-05", "2024-01-05")), meta = NULL)
  ))
  op <- list(domain = "AE", id = "$dy", name = "AESTDTC", operator = "dy")
  binding <- compute_operation(op, study, "AE", study$datasets$AE)
  expect_equal(binding$kind, "per_row")
  expect_equal(binding$value, c(5, NA_real_))
})

test_that("resolve_binding does not collide grouped-join keys across a multi-column boundary", {
  # Bug: pasting group columns together with no separator lets ("1", "23")
  # and ("12", "3") key to the same string "123", joining the wrong group's
  # aggregate onto a row.
  ds_data <- data.table::data.table(A = c("1", "12"), B = c("23", "3"))
  study <- list(datasets = list(DS = list(data = ds_data, meta = NULL)))
  table <- data.table::data.table(A = c("1", "12"), B = c("23", "3"), .value = c(10, 20))
  binding <- grouped_binding(c("A", "B"), table, ".value")
  expect_equal(resolve_binding(binding, study$datasets$DS), c(10, 20))
})

test_that("study_domains/dataset_names/variable_exists/domain_is_custom are local, no Library needed", {
  study <- list(datasets = list(
    AE = list(data = data.table::data.table(AETERM = "X", AESCAN = "Y"), meta = NULL),
    ZZ = list(data = data.table::data.table(A = 1), meta = NULL)
  ))
  expect_equal(compute_operation(list(id = "$d", operator = "study_domains"), study, "AE", study$datasets$AE)$value, c("AE", "ZZ"))
  expect_true(compute_operation(list(id = "$e", name = "AESCAN", operator = "variable_exists"), study, "AE", study$datasets$AE)$value)
  expect_false(compute_operation(list(id = "$e2", name = "NOPE", operator = "variable_exists"), study, "AE", study$datasets$AE)$value)
  expect_false(compute_operation(list(id = "$c", operator = "domain_is_custom"), study, "AE", study$datasets$AE)$value)
  expect_true(compute_operation(list(id = "$c2", operator = "domain_is_custom"), study, "ZZ", study$datasets$ZZ)$value)
})

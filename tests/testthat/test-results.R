test_that("get_output_variables falls back to Check condition names, in order, when Outcome has none", {
  # CORE-000001 has no explicit Output Variables. Its reference results.csv
  # lists exactly IECAT then IEORRES (Check order) for every violating
  # record - confirmed back in Phase 4.
  rule <- .coreval_env$data$rules[["CORE-000001"]]
  expect_null(rule$outcome[["Output Variables"]])
  expect_equal(get_output_variables(rule, "IE"), c("IECAT", "IEORRES"))
})

test_that("get_output_variables uses the declared Output Variables when present, resolving -- templates", {
  rule <- .coreval_env$data$rules[["CORE-000004"]]
  expect_equal(rule$outcome[["Output Variables"]], c("ECDOSE", "ECOCCUR"))
  expect_equal(get_output_variables(rule, "EC"), c("ECDOSE", "ECOCCUR"))
})

test_that("assemble_findings matches CDISC's reference results.csv for a Record-sensitivity rule", {
  rule <- .coreval_env$data$rules[["CORE-000001"]]
  dir <- test_path("fixtures", "core_rules", "CORE-000001", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  violations <- evaluate_rule(rule, study, "IE")
  findings <- assemble_findings(rule, study$datasets$IE, "IE", violations)

  expected <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
  expected$Record <- as.integer(expected$Record)
  data.table::setorder(expected, Record, Variable)
  data.table::setorder(findings, Record, Variable)

  expect_equal(findings$Dataset, expected$Dataset)
  expect_equal(findings$Record, expected$Record)
  expect_equal(findings$Variable, expected$Variable)
  expect_equal(findings$Value, expected$Value)
})

test_that("assemble_findings emits one row per Variable with blank Record for Sensitivity: Dataset", {
  data <- data.table::data.table(A = c("X", "Y", "Z"), B = c("1", "2", "3"))
  dataset <- list(data = data, meta = NULL)
  rule <- list(
    sensitivity = "Dataset",
    outcome = list(`Output Variables` = c("A", "B"))
  )
  violations <- c(FALSE, TRUE, TRUE)
  findings <- assemble_findings(rule, dataset, "TS", violations)

  expect_equal(nrow(findings), 2)
  expect_true(all(is.na(findings$Record)))
  expect_equal(findings$Variable, c("A", "B"))
  expect_equal(findings$Value, c("Y", "2")) # from the FIRST violating row (2)
})

test_that("assemble_findings returns an empty table when nothing violates", {
  data <- data.table::data.table(A = c("X", "Y"))
  dataset <- list(data = data, meta = NULL)
  rule <- list(sensitivity = "Record", outcome = list(`Output Variables` = "A"))
  findings <- assemble_findings(rule, dataset, "TS", c(FALSE, FALSE))
  expect_equal(nrow(findings), 0)
  expect_equal(names(findings), c("Dataset", "Record", "Variable", "Value"))
})

test_that("assemble_findings reports a missing numeric Output Variable as blank, not the text \"NA\"", {
  # Bug: as.character(NA_real_) is NA_character_, not "" - this package's
  # own blank contract says a missing numeric value must report as "",
  # matching how a missing character column already reports.
  data <- data.table::data.table(A = c("X", "Y"), N = c(1, NA_real_))
  dataset <- list(data = data, meta = NULL)
  rule <- list(sensitivity = "Record", outcome = list(`Output Variables` = c("A", "N")))
  findings <- assemble_findings(rule, dataset, "TS", c(FALSE, TRUE))
  expect_equal(findings$Value[findings$Variable == "N"], "")
})

test_that("check_study runs end-to-end on a real test case and reports the expected finding", {
  dir <- test_path("fixtures", "core_rules", "CORE-000001", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  result <- check_study(study)

  expect_true(all(c("findings", "skipped") %in% names(result)))
  ie_findings <- result$findings[result$findings$rule_id == "CORE-000001", ]
  expect_equal(nrow(ie_findings), 6) # 3 records x 2 output variables
  expect_setequal(unique(ie_findings$Record), 1:3)
})

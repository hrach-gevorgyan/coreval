# Expected violation vector from a reference results.csv: one row per
# (Record, Variable) pair, filtered to one Dataset - distinct Record values
# are the violating rows. For a Sensitivity: Dataset rule, any row at all
# means "violates" for every row of the (possibly synthetic) dataset being
# checked. `n` must be the length of evaluate_rule()'s own result (the
# synthetic per-variable/per-(record,variable) dataset's row count for these
# rule types), NOT the real dataset's row count - they usually differ.
expected_violations_for <- function(results_csv_path, dataset_name, n, sensitivity = "Record") {
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (identical(sensitivity, "Dataset")) {
    return(rep(nrow(results) > 0, n))
  }
  out <- rep(FALSE, n)
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("Variable Metadata Check evaluates one row per variable, not per record (CORE-000182)", {
  # "variable_name longer_than 8", Sensitivity: Dataset - confirmed against
  # real fixtures that "Record" for this rule type (when Sensitivity:
  # Record) is the variable's 1-based position within that dataset's
  # variable list, matching _variables.csv's own row order.
  rule <- .coreval_env$data$rules[["CORE-000182"]]
  expect_equal(rule$rule_type, "Variable Metadata Check")
  dir <- test_path("fixtures", "core_rules", "CORE-000182", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  actual <- evaluate_rule(rule, study, domain = "AE")
  expect_true(any(actual)) # AEDECOD00 (9 chars) exceeds the 8-char limit
})

test_that("a 'Variable Metadata Check against Library Metadata' rule still gets the per-variable dataset shape (CORE-000902)", {
  # rule_type is "Variable Metadata Check against Library Metadata", not
  # plain "Variable Metadata Check" - but this specific rule's Check only
  # needs the LOCAL get_model_column_order Operations binding (no real
  # CDISC Library data at all). An earlier version of
  # prepare_dataset_for_rule() matched rule_type by exact string, sending
  # this rule down the ordinary record-level path instead, where its
  # pseudo-field `variable_name` isn't a real column - silently resolving
  # to "no violation" instead of actually evaluating the rule.
  rule <- .coreval_env$data$rules[["CORE-000902"]]
  expect_equal(rule$rule_type, "Variable Metadata Check against Library Metadata")
  for (case in c("negative/01", "negative/02", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000902", case)
    study <- read_study(file.path(dir, "data"))
    actual <- which(evaluate_rule(rule, study, "VS"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    expected <- sort(unique(as.integer(results$Record[results$Dataset == "VS"])))
    expect_equal(sort(unname(actual)), expected, info = case)
  }
})

test_that("Variable Metadata Check resolves a literal array value (CORE-000376)", {
  rule <- .coreval_env$data$rules[["CORE-000376"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000376", case, "01")
    study <- read_study(file.path(dir, "data"))
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- evaluate_rule(rule, study, domain)
      expect_equal(
        actual,
        expected_violations_for(file.path(dir, "results", "results.csv"), domain, length(actual), rule$sensitivity)
      )
    }
  }
})

test_that("Variable Metadata Check supports a full regex against variable_label (CORE-000594)", {
  rule <- .coreval_env$data$rules[["CORE-000594"]]
  dir <- test_path("fixtures", "core_rules", "CORE-000594", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  for (domain in names(study$datasets)) {
    if (!rule_applies_to_domain(rule, domain)) next
    actual <- evaluate_rule(rule, study, domain)
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), domain, length(actual), rule$sensitivity)
    )
  }
})

test_that("build_variable_metadata_dataset builds one row per variable with the right columns", {
  real_dataset <- list(
    data = data.table::data.table(A = 1),
    meta = data.table::data.table(variable = c("USUBJID", "AGE"), label = c("Subject ID", "Age"), type = c("Char", "Num"))
  )
  synthetic <- build_variable_metadata_dataset(real_dataset)
  expect_equal(nrow(synthetic$data), 2)
  expect_equal(synthetic$data$variable_name, c("USUBJID", "AGE"))
  expect_equal(synthetic$data$variable_label, c("Subject ID", "Age"))
  expect_equal(synthetic$data$variable_data_type, c("Char", "Num"))
})

test_that("Dataset Metadata Check matches CDISC's reference results.csv (CORE-000293, CORE-000357)", {
  # "dataset_name longer_than 8" (Sensitivity: Dataset) and Sensitivity:
  # Record for a dataset-level fact - confirmed that Record-sensitivity
  # here reports exactly Record = 1 regardless of the real record count,
  # since the underlying fact is constant across every real record.
  for (id in c("CORE-000293", "CORE-000357")) {
    rule <- .coreval_env$data$rules[[id]]
    expect_equal(rule$rule_type, "Dataset Metadata Check")
    for (case in c("negative", "positive")) {
      case_dirs <- Sys.glob(test_path("fixtures", "core_rules", id, case, "*"))
      for (dir in case_dirs) {
        study <- read_study(file.path(dir, "data"))
        for (domain in names(study$datasets)) {
          if (!rule_applies_to_domain(rule, domain)) next
          actual <- evaluate_rule(rule, study, domain)
          expect_equal(
            actual,
            expected_violations_for(file.path(dir, "results", "results.csv"), domain, length(actual), rule$sensitivity)
          )
        }
      }
    }
  }
})

test_that("Dataset Metadata Check resolves a Check condition against the real DOMAIN column (CORE-000598)", {
  # "dataset_name prefix_not_equal_to 2 DOMAIN" - "DOMAIN" here is a
  # reference to the real dataset's own DOMAIN variable value (e.g. a split
  # dataset "AB" legitimately has DOMAIN == "LB"), not the literal text
  # "DOMAIN".
  rule <- .coreval_env$data$rules[["CORE-000598"]]
  for (case in c("negative/01", "negative/02", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000598", case)
    study <- read_study(file.path(dir, "data"))
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- evaluate_rule(rule, study, domain)
      expect_equal(
        actual,
        expected_violations_for(file.path(dir, "results", "results.csv"), domain, length(actual), rule$sensitivity)
      )
    }
  }
})

test_that("build_dataset_metadata_dataset carries through the real DOMAIN column", {
  real_dataset <- list(data = data.table::data.table(DOMAIN = c("LB", "LB"), X = 1:2), meta = NULL)
  synthetic <- build_dataset_metadata_dataset(real_dataset, "AB")
  expect_equal(synthetic$data$dataset_name, "AB")
  expect_equal(synthetic$data$DOMAIN, "LB")
})

test_that("Value Check with Variable Metadata matches CDISC's reference results.csv (CORE-000890)", {
  # One row per (record, variable) pair - confirmed a record can be flagged
  # via a DIFFERENT variable than another record in the same dataset.
  rule <- .coreval_env$data$rules[["CORE-000890"]]
  expect_equal(rule$rule_type, "Value Check with Variable Metadata")
  dir <- test_path("fixtures", "core_rules", "CORE-000890", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  for (domain in names(study$datasets)) {
    if (!rule_applies_to_domain(rule, domain)) next
    actual <- evaluate_rule(rule, study, domain)
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), domain, length(actual))
    )
  }
})

test_that("Variable Metadata Check preserves a real trailing space in a variable's label (CORE-000019)", {
  # "variable_label longer_than 40", Sensitivity: Dataset. ML.USUBJID's real
  # label is "...Unique Subject " (41 chars, WITH a trailing space) -
  # fread()'s default strip.white = TRUE on _variables.csv would silently
  # trim that space, making the label look 40 chars long and missing the
  # violation entirely.
  rule <- .coreval_env$data$rules[["CORE-000019"]]
  expect_equal(rule$rule_type, "Variable Metadata Check")
  dir <- test_path("fixtures", "core_rules", "CORE-000019", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  actual <- evaluate_rule(rule, study, domain = "ML")
  results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
  expect_true(any(actual)) # matches the reference: at least one violation (USUBJID's label)
  expect_true(nrow(results[results$Dataset == "ML", ]) > 0)
})

test_that("build_variable_value_check_dataset melts to one row per (record, variable) with the original record id", {
  real_dataset <- list(
    data = data.table::data.table(A = c("x", " y"), B = c(1, 2)),
    meta = data.table::data.table(variable = c("A", "B"), label = c("A lbl", "B lbl"), type = c("Char", "Num"))
  )
  melted <- build_variable_value_check_dataset(real_dataset)
  expect_equal(nrow(melted$data), 4)
  expect_equal(melted$data$.coreval_row_id, c(1, 2, 1, 2))
  expect_equal(melted$data$variable_name, c("A", "A", "B", "B"))
  expect_equal(melted$data$variable_value[melted$data$variable_name == "A"], c("x", " y"))
})

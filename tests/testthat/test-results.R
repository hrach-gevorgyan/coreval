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

test_that("assemble_findings reports a real, non-$-binding Output Variable absent from this domain as \"Not in dataset\" (CORE-000750)", {
  # A rule scoped to "Domains: Include: ALL" can have Output Variables that
  # only exist for SOME of those domains (e.g. USUBJID- vs POOLID-keyed
  # domains) - the reference engine still reports a row for every declared
  # Output Variable, with the literal text "Not in dataset" for one that
  # isn't a real column here, rather than silently dropping it. Confirmed
  # against CORE-000750's real fixture: AE's findings report
  # `USUBJID = "Not in dataset"` (AE is POOLID-keyed) right alongside CM's
  # findings reporting `POOLID = "Not in dataset"` (CM is USUBJID-keyed).
  data <- data.table::data.table(AESEQ = c(2, 2), POOLID = c("CDISC001", "CDISC001"))
  dataset <- list(data = data, meta = NULL)
  rule <- list(sensitivity = "Record", outcome = list(`Output Variables` = c("AESEQ", "POOLID", "USUBJID")))
  findings <- assemble_findings(rule, dataset, "AE", c(TRUE, TRUE))
  expect_equal(findings$Value[findings$Record == 1 & findings$Variable == "USUBJID"], "Not in dataset")
  expect_equal(findings$Value[findings$Record == 1 & findings$Variable == "POOLID"], "CDISC001")
})

test_that("group_first_violations collapses per-row violations to one flagged row per group (CORE-000888)", {
  # SETCD groups SET1(1-4)/SET2(5-7)/SET3(8): only SET2 and SET3 violate,
  # every row within a violating group shares the same result (the check is
  # driven by a grouped `distinct` binding, constant per group) - the
  # reference reports exactly one finding per violating group, at its
  # first row: record 5 for SET2, record 8 for SET3.
  rule <- .coreval_env$data$rules[["CORE-000888"]]
  dir <- test_path("fixtures", "core_rules", "CORE-000888", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  dataset <- prepare_dataset_for_rule(rule, study, "TX")
  bindings <- operation_bindings_for_rule(rule, study, "TX", dataset)
  violations <- evaluate_check(rule$check, dataset, "TX", bindings, study)
  actual <- group_first_violations(dataset, violations, rule$grouping_variables, "TX")

  results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
  expected <- sort(unique(as.integer(results$Record[results$Dataset == "TX"])))
  expect_equal(sort(actual), expected)
})

test_that("assemble_findings reports one finding per group for Sensitivity: Group, including a $-bound set Output Variable (CORE-000888/CORE-000993)", {
  for (id in c("CORE-000888", "CORE-000993")) {
    rule <- .coreval_env$data$rules[[id]]
    for (case in c("negative/01", "positive/01")) {
      dir <- test_path("fixtures", "core_rules", id, case)
      study <- read_study(file.path(dir, "data"))
      dataset <- prepare_dataset_for_rule(rule, study, "TX")
      bindings <- operation_bindings_for_rule(rule, study, "TX", dataset)
      violations <- evaluate_check(rule$check, dataset, "TX", bindings, study)
      violations[is.na(violations)] <- FALSE
      findings <- assemble_findings(rule, dataset, "TX", violations, bindings)

      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      expected_records <- sort(unique(as.integer(results$Record[results$Dataset == "TX"])))
      expect_equal(sort(unique(findings$Record)), expected_records, info = paste(id, case))
      if (nrow(findings) > 0) {
        expect_setequal(findings$Variable, c("SETCD", "$txparmcd"))
      }
    }
  }
})

test_that("assemble_findings treats a Domain Presence Check as Dataset-sensitivity regardless of its declared Sensitivity field", {
  # CORE-000183/CORE-000188 declare "Sensitivity: Record" despite being
  # Domain Presence Check rules - a whole-study-level FACT (is this domain
  # present anywhere?) has no per-record concept at all. Every currently-
  # passing rule of this type declares Sensitivity: Dataset; these two are
  # authoring inconsistencies, not a genuinely different evaluation shape.
  data <- data.table::data.table(A = c("X", "Y"))
  dataset <- list(data = data, meta = NULL)
  rule <- list(
    sensitivity = "Record", rule_type = "Domain Presence Check",
    outcome = list(`Output Variables` = "A")
  )
  violations <- c(TRUE, TRUE) # e.g. a dataset-level fact recycled to every row
  findings <- assemble_findings(rule, dataset, "TS", violations)
  expect_equal(nrow(findings), 1)
  expect_true(is.na(findings$Record))
})

test_that("Domain Presence Check matches CDISC's reference results.csv despite declaring Sensitivity: Record (CORE-000183)", {
  rule <- .coreval_env$data$rules[["CORE-000183"]]
  expect_equal(rule$rule_type, "Domain Presence Check")
  expect_equal(rule$sensitivity, "Record")
  for (case in c("negative/01", "positive/01", "positive/02")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000183", case)
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual_any <- any(evaluate_rule(rule, study, domain))
      expected_any <- nrow(results[results$Dataset == domain, ]) > 0 ||
        nrow(results[results$Dataset == "STUDY", ]) > 0
      expect_equal(actual_any, expected_any, info = paste(case, domain))
    }
  }
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

test_that("check_study evaluates the metadata rule types, not just Record Data", {
  # These rule types each need a different "one row" model, all of which
  # prepare_dataset_for_rule() already builds and the conformance harness
  # verifies against CDISC's reference output. check_study() used to run
  # only "Record Data", so ~29 rules that demonstrably work were silently
  # unavailable through the package's main entry point.
  expect_true(rule_type_is_supported("Record Data"))
  expect_true(rule_type_is_supported("Domain Presence Check"))
  expect_true(rule_type_is_supported("Dataset Metadata Check"))
  expect_true(rule_type_is_supported("Variable Metadata Check"))
  expect_true(rule_type_is_supported("Value Check with Variable Metadata"))

  # define.xml IS read (R/define.R), so those types are supported too;
  # evaluate_rule() refuses per-study when a study has no define.xml,
  # rather than evaluating against absent columns.
  expect_true(rule_type_is_supported("Variable Metadata Check against Define XML"))
  expect_true(rule_type_is_supported("Domain Presence Check against Define XML"))

  # Still out: needs CDISC Library metadata on top of define.xml, and
  # there is no bundled data for it.
  expect_false(rule_type_is_supported("Define Item Metadata Check against Library Metadata"))
  expect_false(rule_type_is_supported(NULL))
})

test_that("check_study reports a Domain Presence Check once, under the STUDY sentinel", {
  # It asks one question about the whole study ("is DM present?"), so it
  # must not be re-answered under every domain its scope matches. The
  # reference results.csv uses `STUDY,,DM,Not in dataset` - confirmed
  # against CORE-000581/CORE-000183's own fixtures.
  dir <- test_path("fixtures", "core_rules", "CORE-000183", "negative", "01")
  skip_if_not(dir.exists(file.path(dir, "data")))
  study <- read_study(file.path(dir, "data"))
  res <- check_study(study)

  dpc_ids <- unique(res$findings$rule_id[res$findings$Dataset == "STUDY"])
  expect_true(length(dpc_ids) > 0)
  for (id in dpc_ids) {
    # exactly one Dataset value for this rule, and it is the sentinel
    expect_equal(unique(res$findings$Dataset[res$findings$rule_id == id]), "STUDY")
  }
  expect_true(all(is.na(res$findings$Record[res$findings$Dataset == "STUDY"])))
})

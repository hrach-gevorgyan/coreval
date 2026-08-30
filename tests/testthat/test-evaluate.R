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

test_that("exists/not_exists are dataset-level facts, recycled to one value per row", {
  # A bare exists/not_exists condition describes the dataset, not any one
  # record, but evaluate_condition() still recycles it to one value per row
  # (evaluate_check()'s own documented contract) - needed for a Check whose
  # EVERY leaf is dataset-level, where there's no per-row sibling condition
  # left for R's ordinary `&`/`|` recycling to broadcast against (confirmed
  # necessary against CORE-000291's real fixture, a Match Datasets self-join
  # combined with two all-scalar conditions).
  data <- data.table::data.table(A = c("X", "Y"))
  dataset <- list(data = data, meta = NULL)

  expect_equal(evaluate_check(list(name = "A", operator = "exists"), dataset, "TS"), c(TRUE, TRUE))
  expect_equal(evaluate_check(list(name = "B", operator = "exists"), dataset, "TS"), c(FALSE, FALSE))
  expect_equal(evaluate_check(list(name = "B", operator = "not_exists"), dataset, "TS"), c(TRUE, TRUE))
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

test_that("evaluate_rule refuses a define.xml rule instead of fabricating findings", {
  # coreval has no define.xml reader, so a define-side pseudo-column like
  # `define_variable_label` is absent, and resolve_condition_value()'s
  # "not a real column -> literal text" fallback would turn the check into
  # `variable_label != "define_variable_label"` - true for every variable,
  # in the compliant and non-compliant case alike. Manufacturing confident
  # findings from missing input is worse than declining to run.
  rule <- list(
    rule_type = "Variable Metadata Check against Define XML",
    check = list(all = list(list(
      name = "variable_label", operator = "not_equal_to", value = "define_variable_label"
    )))
  )
  data <- data.table::data.table(STUDYID = "S1")
  meta <- data.table::data.table(variable = "STUDYID", label = "Study Identifier", type = "Char")
  study <- list(datasets = list(DM = list(data = data, meta = meta)))
  expect_error(evaluate_rule(rule, study, "DM"), "define.xml", fixed = TRUE)
})

test_that("resolve_var_name keeps its character type for a zero-length input", {
  # ifelse() returns logical(0), not character(0), for an empty input -
  # with nothing to test it never inspects the yes/no branches to learn
  # their type. That silently changed this function's return type and
  # errored several frames later inside startsWith(). Reachable for real:
  # a rule declaring no Output Variables whose Check references only
  # `$`-bound Operations bindings (CORE-000893) produces exactly that
  # empty set, which crashed check_study() on any study with a TX domain.
  expect_identical(resolve_var_name(character(0), "TX"), character(0))
  expect_identical(resolve_var_name(c("--SEQ", "USUBJID"), "AE"), c("AESEQ", "USUBJID"))
})

test_that("a \"--\" template expands to the DOMAIN column's value, not the file name", {
  # The reference engine's wildcard_replacement is
  # `ap_suffix or <DOMAIN column value>`, and its own documented table
  # shows a domain SPLIT ACROSS FILES (QSX, QSXX - both carrying
  # DOMAIN=QS) expanding "--" to QS for every one of them. Using the file
  # name instead silently mis-resolves every "--" template on a split
  # dataset: lbae.csv with DOMAIN=LB gave LBAESEQ, which is not a column,
  # so the condition quietly became unresolvable rather than checking
  # anything. 251 of the bundled rules use a "--" template and splitting a
  # large domain across files is routine, so this reached well beyond the
  # conformance fixtures.
  split_a <- list(
    data = data.table::data.table(DOMAIN = c("LB", "LB"), LBSEQ = c(1, 2)),
    meta = NULL
  )
  expect_equal(dataset_wildcard(split_a, "LBAE"), "LB")
  expect_equal(resolve_var_name("--SEQ", dataset_wildcard(split_a, "LBAE")), "LBSEQ")
  # and end to end, the condition now actually resolves
  expect_equal(
    evaluate_check(list(name = "--SEQ", operator = "non_empty"), split_a, "LBAE"),
    c(TRUE, TRUE)
  )

  # An unsplit dataset is unaffected: name and DOMAIN agree.
  plain <- list(data = data.table::data.table(DOMAIN = "AE", AESEQ = 1), meta = NULL)
  expect_equal(dataset_wildcard(plain, "AE"), "AE")

  # An Associated Persons dataset expands to the domain it is associated
  # with (APQS -> QS), per the reference's ap_suffix.
  ap <- list(data = data.table::data.table(APID = "1", QSSEQ = 1), meta = NULL)
  expect_equal(dataset_wildcard(ap, "APQS"), "QS")

  # No DOMAIN column (RELREC, SUPPxx): fall back to the dataset's own name
  # rather than the reference's "", which would yield a bare, prefix-less
  # column name like "SEQ".
  no_domain <- list(data = data.table::data.table(X = 1), meta = NULL)
  expect_equal(dataset_wildcard(no_domain, "RELREC"), "RELREC")

  # A blank DOMAIN value also falls back rather than producing "".
  blank_domain <- list(data = data.table::data.table(DOMAIN = "", X = 1), meta = NULL)
  expect_equal(dataset_wildcard(blank_domain, "AE"), "AE")
})

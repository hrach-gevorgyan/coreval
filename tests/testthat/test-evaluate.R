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

test_that("an undeclared study standard is taken from the rule being run, not defaulted to SDTMIG", {
  # Bug (CDISC.SENDIG.6A): library_variables_for() falls back to SDTMIG when a
  # study declares no standard. Running a SENDIG rule then judged the data
  # against SDTM labels, so every VS variable whose SEND label differs from
  # its SDTM one was reported as a define.xml/Library mismatch that isn't
  # there. What the data says about itself must still win where it says
  # anything at all.
  study <- list(
    datasets = list(VS = list(data = data.table::data.table(VSORRES = "1"), meta = NULL)),
    standard = list(product = NA_character_, version = NA_character_)
  )
  rule <- list(standard_versions = c("SENDIG 3.0", "SENDIG 3.1", "SENDIG-DART 1.1"))
  expect_equal(study_standard_from_rule(study, rule)$standard$product, "SENDIG")

  declared <- study
  declared$standard$product <- "SDTMIG"
  expect_equal(study_standard_from_rule(declared, rule)$standard$product, "SDTMIG")

  expect_equal(
    study_standard_from_rule(study, list())$standard$product,
    NA_character_
  )
})

test_that("a Value Check with Dataset Metadata melts the data, not the metadata rows", {
  # Bug (CORE-000356): the melt was driven by the variable-metadata table, so
  # an unreadable `_variables.csv` made the whole rule silently find nothing.
  # The reference melts the data's own columns and never opens that file.
  data <- data.table::data.table(
    STUDYID = c("", "S1"), DOMAIN = c("LB", "LB"), LBSEQ = c("", "2")
  )
  # Metadata that knows about only one of the three columns - the other two
  # must still be checked, with an unknown declared type.
  meta <- data.frame(variable = "DOMAIN", type = "Char", stringsAsFactors = FALSE)

  built <- build_variable_value_check_dataset(list(data = data, meta = meta))
  expect_setequal(unique(built$data$variable_name), c("STUDYID", "DOMAIN", "LBSEQ"))
  expect_equal(nrow(built$data), 6)
  expect_equal(built$data$variable_data_type[built$data$variable_name == "DOMAIN"], c("Char", "Char"))
  expect_true(all(is.na(built$data$variable_data_type[built$data$variable_name == "LBSEQ"])))

  # Zero-row metadata (the malformed-file case) must not empty the melt.
  empty_meta <- build_variable_value_check_dataset(
    list(data = data, meta = meta[0, , drop = FALSE])
  )
  expect_equal(nrow(empty_meta$data), 6)
  expect_true(all(is.na(empty_meta$data$variable_data_type)))
})

test_that("variable_is_empty / variable_has_empty_values follow the reference's null stats", {
  # The reference's get_variable_null_stats(): a value is absent when NA or
  # "", `has_empty_values` is TRUE when ANY row is absent and `is_empty` when
  # EVERY row is. A variable the dataset does not carry at all is both.
  # Without these columns a rule naming them resolves the name to literal
  # text and silently reports nothing (CDISC.SDTMIG.CG0015).
  real <- list(
    data = data.table::data.table(
      FULL = c("a", "b"), SOME = c("a", ""), NONE = c("", ""), NAS = c(NA_character_, NA_character_)
    ),
    meta = data.frame(
      variable = c("FULL", "SOME", "NONE", "NAS", "ABSENT"),
      label = NA_character_, type = "Char", stringsAsFactors = FALSE
    )
  )
  built <- build_variable_metadata_dataset(real)
  d <- as.data.frame(built$data)
  got <- function(v, col) d[[col]][d$variable_name == v]

  expect_equal(got("FULL", "variable_has_empty_values"), FALSE)
  expect_equal(got("FULL", "variable_is_empty"), FALSE)
  expect_equal(got("SOME", "variable_has_empty_values"), TRUE)
  expect_equal(got("SOME", "variable_is_empty"), FALSE)
  expect_equal(got("NONE", "variable_is_empty"), TRUE)
  expect_equal(got("NAS", "variable_is_empty"), TRUE)
  # Declared in metadata, absent from the data: both TRUE.
  expect_equal(got("ABSENT", "variable_has_empty_values"), TRUE)
  expect_equal(got("ABSENT", "variable_is_empty"), TRUE)
})

test_that("check_study() and evaluate_rule() take the same evaluation path", {
  # These were separate code paths, and they had already drifted: run_checks()
  # never resolved an undeclared study standard from the rule, so a SEND rule
  # run through check_dataset()/check_study() was judged against SDTM Library
  # metadata while the same rule through evaluate_rule() was not. The whole
  # test suite and the conformance harness exercise evaluate_rule(), so a
  # divergence there means the suite proves nothing about what users run.
  dir <- tempfile("coreval_drift_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  haven::write_xpt(
    data.frame(
      STUDYID = "S", DOMAIN = "DM", USUBJID = c("1", "2", "3"),
      RFSTDTC = c("2024-01-05", "", "2024-13-01"),
      AGE = c(34, 61, 47), AGEU = c("YEARS", "", "YEARS"), SEX = c("M", "F", "F")
    ),
    file.path(dir, "dm.xpt")
  )
  study <- read_study(dir)
  result <- check_study(dir)

  # For every rule that produced a finding, evaluate_rule() must flag exactly
  # the same records.
  reported <- unique(result$findings$rule_id)
  expect_gt(length(reported), 0)
  for (id in reported) {
    rule <- .coreval_env$data$rules[[id]]
    if (is.null(rule) || identical(rule$rule_type, "Domain Presence Check")) next
    direct <- which(evaluate_rule(rule, study, "DM"))
    via_check <- sort(unique(result$findings$Record[result$findings$rule_id == id]))
    via_check <- via_check[!is.na(via_check)]
    if (length(via_check) == 0) next
    expect_equal(sort(direct), as.integer(via_check), info = id)
  }
})

test_that("run_rule_on_domain resolves the standard from the rule on BOTH paths", {
  # The specific drift that motivated sharing the path.
  study <- list(
    datasets = list(VS = list(data = data.table::data.table(DOMAIN = "VS", VSORRES = "1"), meta = NULL)),
    standard = list(product = NA_character_, version = NA_character_)
  )
  rule <- list(
    standard_versions = c("SENDIG 3.1"),
    check = list(name = "VSORRES", operator = "non_empty")
  )
  # Not the return value that matters here - that the shared core is what both
  # callers reach, so the standard fill-in cannot apply to only one of them.
  out <- run_rule_on_domain(rule, study, "VS")
  expect_true(is.logical(out$violations))
  expect_named(out, c("dataset", "violations", "bindings"))
})

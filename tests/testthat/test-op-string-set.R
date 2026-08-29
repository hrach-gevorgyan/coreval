test_that("contains/does_not_contain check substring membership", {
  data <- data.table::data.table(X = c("P-1DT2H", "P10D", ""))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "contains", value = "-", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, FALSE, FALSE))

  check2 <- list(name = "X", operator = "does_not_contain", value = "-", value_is_literal = TRUE)
  expect_equal(evaluate_check(check2, dataset, "TS"), c(FALSE, TRUE, TRUE))
})

test_that("starts_with/ends_with check literal prefix/suffix, any of a vector", {
  data <- data.table::data.table(X = c("RACE1", "SEX", "RACEORIG"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "starts_with", value = "RACE", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, FALSE, TRUE))

  data2 <- data.table::data.table(X = c("AESEQ", "AETERM", "DOSESEQ"))
  dataset2 <- list(data = data2, meta = NULL)
  check2 <- list(name = "X", operator = "ends_with", value = "SEQ", value_is_literal = TRUE)
  expect_equal(evaluate_check(check2, dataset2, "TS"), c(TRUE, FALSE, TRUE))
})

test_that("has_equal_length/has_not_equal_length compare nchar to a literal or another column", {
  data <- data.table::data.table(DOMAIN = c("AE", "DM", "SUPPAE"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "DOMAIN", operator = "has_not_equal_length", value = 2, value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE, TRUE))
})

test_that("is_contained_by_case_insensitive/is_not_contained_by_case_insensitive ignore case", {
  data <- data.table::data.table(ARM = c("Screen Failure", "screen failure", "Active"))
  dataset <- list(data = data, meta = NULL)
  check <- list(
    name = "ARM", operator = "is_contained_by_case_insensitive",
    value = c("Screen Failure", "Not Assigned"), value_is_literal = TRUE
  )
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("prefix_matches_regex/suffix_matches_regex search only the first/last N characters", {
  data <- data.table::data.table(DOMAIN = c("APDM", "ap01", "AEDM"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "DOMAIN", operator = "prefix_matches_regex", prefix = 2, value = "(AP|ap)")
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))

  data2 <- data.table::data.table(IDVAR = c("AESEQ", "AETERM", "USUBJID"))
  dataset2 <- list(data = data2, meta = NULL)
  check2 <- list(name = "IDVAR", operator = "suffix_matches_regex", suffix = 3, value = "SEQ")
  expect_equal(evaluate_check(check2, dataset2, "TS"), c(TRUE, FALSE, FALSE))
})

test_that("contains_all/not_contains_all are dataset-level checks on the column's full value set", {
  data <- data.table::data.table(TSPARMCD = c("AGEMAX", "AGEMIN", "SEXPOP"))
  dataset <- list(data = data, meta = NULL)
  check <- list(
    name = "TSPARMCD", operator = "not_contains_all",
    value = c("AGEMAX", "AGEMIN"), value_is_literal = TRUE
  )
  expect_false(evaluate_check(check, dataset, "TS")) # both present -> contains_all TRUE -> not_ FALSE

  check2 <- list(
    name = "TSPARMCD", operator = "not_contains_all",
    value = c("AGEMAX", "MISSING_ONE"), value_is_literal = TRUE
  )
  expect_true(evaluate_check(check2, dataset, "TS"))
})

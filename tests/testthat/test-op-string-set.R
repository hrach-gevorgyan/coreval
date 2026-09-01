test_that("matches_regex/not_matches_regex anchor at the string's start (CORE-000576)", {
  # A pattern with no leading "^" but a trailing "$" (e.g.
  # "[+-]?([0-9]*[.])?[0-9]+$") must match the WHOLE string from position 0,
  # not just a trailing substring - confirmed against CORE-000576's real
  # fixtures: "-5.18,3.1416,2,2.88" must NOT match this number-format regex
  # (it's a comma-separated list, not a single number), even though the
  # regex's own trailing "2.88" substring would satisfy an unanchored search.
  rule <- .coreval_env$data$rules[["CORE-000576"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000576", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "TX")
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    expected <- rep(FALSE, nrow(study$datasets$TX$data))
    if (nrow(results) > 0) {
      expected[as.integer(unique(results$Record))] <- TRUE
    }
    expect_equal(actual, expected)
  }
})

test_that("matches_regex only matches a suffix when the pattern lacks a leading anchor and no start-anchored match exists", {
  data <- data.table::data.table(X = c("-5.18,3.1416,2,2.88", "33.5", "invalid"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "matches_regex", value = "[+-]?([0-9]*[.])?[0-9]+$", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "TX"), c(FALSE, TRUE, FALSE))
})

test_that("matches_regex/not_matches_regex are FALSE (not a forced result) for a blank target", {
  # The reference engine's own implementation ANDs both operators with
  # `converted_strings.notna()` - a blank/NA value is exempt from format
  # validation entirely, for BOTH operators independently (not a simple
  # negation of each other). Confirmed against CORE-000558's real fixture:
  # a numeric --DY value left blank must not be flagged by
  # "not_matches_regex ^-?[1-9]{1}\\d*$" - an empty string trivially fails
  # that digit-requiring pattern, but a MISSING value isn't a formatting
  # violation.
  data <- data.table::data.table(X = c(NA_real_, 0, 5))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "not_matches_regex", value = "^-?[1-9]{1}\\d*$", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, TRUE, FALSE))

  check2 <- list(name = "X", operator = "matches_regex", value = "^-?[1-9]{1}\\d*$", value_is_literal = TRUE)
  expect_equal(evaluate_check(check2, dataset, "TS"), c(FALSE, FALSE, TRUE))
})

test_that("not_matches_regex matches CDISC's reference results.csv, exempting blank values (CORE-000558)", {
  rule <- .coreval_env$data$rules[["CORE-000558"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000558", case, "01")
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    actual <- which(evaluate_rule(rule, study, domain = "DS"))
    expected <- sort(unique(as.integer(results$Record[results$Dataset == "DS"])))
    expect_equal(sort(unname(actual)), expected, info = case)
  }
})

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

test_that("does_not_equal_string_part matches CDISC's reference results.csv (CORE-000538)", {
  # "RDOMAIN does_not_equal_string_part regex: .{4}(..).*, value: $dataset_name"
  # extracts characters 5-6 of the dataset name (e.g. "AE" from "SUPPAE")
  # and flags every row where RDOMAIN doesn't match it.
  rule <- .coreval_env$data$rules[["CORE-000538"]]
  for (case in c("negative/01", "negative/02", "negative/03", "positive/01", "positive/02", "positive/03")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000538", case)
    study <- read_study(file.path(dir, "data"))
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- which(evaluate_rule(rule, study, domain))
      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
      expect_equal(sort(unname(actual)), expected)
    }
  }
})

test_that("does_not_equal_string_part extracts a regex capture group from value and compares to target", {
  data <- data.table::data.table(RDOMAIN = c("AE", "CM"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "RDOMAIN", operator = "does_not_equal_string_part", regex = ".{4}(..).*", value = "SUPPAE", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "SUPPAE"), c(FALSE, TRUE))
})

test_that("contains/does_not_contain use exact set membership (not substring search) against a list target", {
  # A `$`-bound grouped `distinct` Operations binding resolves to a LIST
  # target (one set of values per row). "contains" there means "value is a
  # member of the row's set" - confirmed against CORE-000888/CORE-000993's
  # real fixtures: a set containing only "PLANFSUBxxx" is NOT considered to
  # contain "PLANFSUB" (a substring match would wrongly say it does).
  ctx <- list(
    target = list(c("ARMCD", "PLANFSUBxxx", "SPGRPCD"), c("ARMCD", "PLANFSUB")),
    value = "PLANFSUB", exists = TRUE, n = 2
  )
  expect_equal(get_operator("contains")(ctx), c(FALSE, TRUE))
  expect_equal(get_operator("does_not_contain")(ctx), c(TRUE, FALSE))
})

test_that("contains_all/not_contains_all attach their dataset-level verdict to record 1 only", {
  # The verdict is a whole-column fact, but it is reported against the
  # FIRST RECORD ONLY - it is NOT broadcast to every row. The reference
  # engine returns `convert_to_series(<bare bool>)`, i.e. a LENGTH-1
  # pandas Series, and pandas index alignment then fills rows 2..n with
  # NaN (which its boolean ops read as FALSE) when that series meets a
  # length-n sibling condition. Operators that genuinely mean "every row"
  # broadcast explicitly instead (`exists` writes
  # `convert_to_series([True] * len(self.value))`); contains_all
  # pointedly does not, and upstream's own test_contains_all asserts the
  # scalar/length-1 shape against a 3-row dataset. Confirmed against
  # CORE-000737/740/741's real fixtures, whose results.csv each report
  # exactly ONE record even though every row satisfies the check.
  data <- data.table::data.table(TSPARMCD = c("AGEMAX", "AGEMIN", "SEXPOP"))
  dataset <- list(data = data, meta = NULL)
  check <- list(
    name = "TSPARMCD", operator = "not_contains_all",
    value = c("AGEMAX", "AGEMIN"), value_is_literal = TRUE
  )
  # both present -> contains_all TRUE -> not_ FALSE everywhere
  expect_equal(evaluate_check(check, dataset, "TS"), rep(FALSE, 3))

  check2 <- list(
    name = "TSPARMCD", operator = "not_contains_all",
    value = c("AGEMAX", "MISSING_ONE"), value_is_literal = TRUE
  )
  # violated -> flagged on record 1 alone, never rows 2-3
  expect_equal(evaluate_check(check2, dataset, "TS"), c(TRUE, FALSE, FALSE))

  check3 <- list(
    name = "TSPARMCD", operator = "contains_all",
    value = c("AGEMAX", "AGEMIN"), value_is_literal = TRUE
  )
  expect_equal(evaluate_check(check3, dataset, "TS"), c(TRUE, FALSE, FALSE))
})

test_that("contains_all/not_contains_all are NA (unresolvable), not a forced FALSE/TRUE, when value is unresolvable", {
  # Bug: contains_all() hard-coded FALSE for an unresolvable (NULL) value -
  # e.g. a $required_variables binding that returns NULL for a non-SDTMIG
  # study. Its negation, not_contains_all, then came out TRUE (a
  # fabricated violation) instead of staying unresolvable. Confirmed
  # against CORE-000355's real fixture.
  data <- data.table::data.table(TSPARMCD = c("AGEMAX", "AGEMIN"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "TSPARMCD", operator = "not_contains_all", value = "$unresolvable")
  expect_equal(evaluate_check(check, dataset, "TS", bindings = list()), rep(NA, 2))
})

test_that("shares_no_elements_with treats a scalar binding as ONE collection, not one per row", {
  # A `$`-bound scalar Operations binding (e.g. $dataset_variables) IS the
  # whole collection and applies to every row; only a grouped binding is
  # already one collection per row. Splitting the vector into one element
  # per row instead made the intersection almost always empty, so a dataset
  # that clearly does share elements reported that it shares none.
  ctx <- list(
    target = c("STUDYID", "AEENRF", "AETERM"),
    value = c("VISITNUM", "AEENRF", "AEDTC"),
    exists = TRUE, n = 3L, condition = list(operator = "shares_no_elements_with")
  )
  # AEENRF is shared, so every row reports FALSE.
  expect_equal(get_operator("shares_no_elements_with")(ctx), rep(FALSE, 3))

  ctx$value <- c("VISITNUM", "AEDTC")
  expect_equal(get_operator("shares_no_elements_with")(ctx), rep(TRUE, 3))
})

test_that("is_ordered_subset_of requires every element present AND in ascending order", {
  base <- list(exists = TRUE, n = 1L, condition = list(operator = "is_ordered_subset_of"))
  ordered <- utils::modifyList(base, list(
    target = c("A", "C"), value = c("A", "B", "C", "D")
  ))
  expect_true(get_operator("is_ordered_subset_of")(ordered))

  # Present, but out of order relative to the comparator.
  out_of_order <- utils::modifyList(base, list(
    target = c("C", "A"), value = c("A", "B", "C", "D")
  ))
  expect_false(get_operator("is_ordered_subset_of")(out_of_order))

  # An element missing from the comparator is FALSE outright, matching the
  # reference's own early return rather than being skipped over.
  missing <- utils::modifyList(base, list(
    target = c("A", "Z"), value = c("A", "B", "C")
  ))
  expect_false(get_operator("is_ordered_subset_of")(missing))

  expect_true(get_operator("is_not_ordered_subset_of")(out_of_order))
})

test_that("contains_case_insensitive matches regardless of case, both ways", {
  ctx <- function(target, value) {
    list(target = target, value = value, exists = TRUE, n = length(target),
         condition = list(operator = "contains_case_insensitive"))
  }
  op <- get_operator("contains_case_insensitive")

  expect_equal(op(ctx(c("HEADACHE", "rash"), "head")), c(TRUE, FALSE))
  expect_equal(op(ctx(c("Headache", "RASH"), "RASH")), c(FALSE, TRUE))
  expect_equal(op(ctx("headache", "HEADACHE")), TRUE)

  # It must agree with the case-sensitive operator whenever case already
  # matches - otherwise it is not the same comparison with case folded.
  same <- get_operator("contains")
  plain <- ctx(c("abc", "def"), "abc")
  expect_equal(op(plain), same(plain))
})

test_that("contains_case_insensitive keeps the set/substring distinction", {
  # A SET target (from a `distinct` Operation) matches whole elements, not
  # substrings - so a variable list holding "PLANFSUBxxx" does NOT contain
  # "PLANFSUB". Folding case must not quietly turn that into a substring
  # match, which would break the rule the distinction exists for.
  op <- get_operator("contains_case_insensitive")
  set_ctx <- list(
    target = list(c("planfsubxxx", "armcd")), value = "PLANFSUB",
    exists = TRUE, n = 1,
    condition = list(operator = "contains_case_insensitive")
  )
  expect_false(op(set_ctx))

  exact <- set_ctx
  exact$target <- list(c("planfsub", "armcd"))
  expect_true(op(exact))
})

test_that("does_not_contain_case_insensitive is the exact negation", {
  ctx <- list(
    target = c("HEADACHE", "rash"), value = "head", exists = TRUE, n = 2,
    condition = list(operator = "does_not_contain_case_insensitive")
  )
  expect_equal(
    get_operator("does_not_contain_case_insensitive")(ctx),
    !get_operator("contains_case_insensitive")(ctx)
  )
})

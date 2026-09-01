test_that("ordinal comparisons coerce a numeric-looking literal against a numeric column", {
  # Bug: R's `<`/`>`/etc. silently coerce the NUMBER to a STRING when the
  # other side is character, then compare lexicographically - "9" > "65" is
  # TRUE character-wise even though 9 > 65 is FALSE numerically. A quoted
  # numeric literal like `value: "65"` in a rule's YAML hits this.
  data <- data.table::data.table(AGE = c(9, 65, 100))
  dataset <- list(data = data, meta = NULL)

  check <- list(name = "AGE", operator = "greater_than", value = "65", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "DM"), c(FALSE, FALSE, TRUE))

  check2 <- list(name = "AGE", operator = "less_than", value = "65", value_is_literal = TRUE)
  expect_equal(evaluate_check(check2, dataset, "DM"), c(TRUE, FALSE, FALSE))

  check3 <- list(name = "AGE", operator = "greater_than_or_equal_to", value = "65", value_is_literal = TRUE)
  expect_equal(evaluate_check(check3, dataset, "DM"), c(FALSE, TRUE, TRUE))

  check4 <- list(name = "AGE", operator = "less_than_or_equal_to", value = "65", value_is_literal = TRUE)
  expect_equal(evaluate_check(check4, dataset, "DM"), c(TRUE, TRUE, FALSE))
})

test_that("ordinal comparisons still work between two genuinely text columns", {
  data <- data.table::data.table(X = c("apple", "banana", "cherry"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "X", operator = "less_than", value = "banana", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, FALSE, FALSE))
})

test_that("equal_to/not_equal_to are unaffected by numeric/character type mismatch", {
  data <- data.table::data.table(AGE = c(65, 9))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "AGE", operator = "equal_to", value = "65", value_is_literal = TRUE)
  expect_equal(evaluate_check(check, dataset, "DM"), c(TRUE, FALSE))
})

test_that("type_insensitive makes not_equal_to compare numeric-looking values by value, not formatting (CORE-000542)", {
  # "LBSTRESC not_equal_to, type_insensitive: true, value: LBSTRESN" -
  # "200.00" and 200 must compare EQUAL (not_equal_to = FALSE), even though
  # they differ as raw strings. An earlier version had no type_insensitive
  # handling at all, so this compared "200.00" != "200" as plain strings.
  data <- data.table::data.table(LBSTRESC = c("200.00", "200.01"), LBSTRESN = c(200, 200))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "LBSTRESC", operator = "not_equal_to", value = "LBSTRESN", type_insensitive = TRUE)
  expect_equal(evaluate_check(check, dataset, "LB"), c(FALSE, TRUE))
})

test_that("not_equal_to applies the blank truth table to a per-row comparator (CORE-001082)", {
  # With a genuine per-row COLUMN on both sides, the reference's truth table
  # applies in full: exactly one side blank is a real difference, both blank
  # is not. CORE-001082 pins this - a variable defined in neither the IG nor
  # the SDTM Model has no library_variable_data_type to compare against, and
  # that counts as a mismatch.
  data <- data.table::data.table(TARGET = c(NA_real_, 5, NA_real_), VALUE = c(45, NA_real_, NA_real_))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "TARGET", operator = "not_equal_to", value = "VALUE")
  expect_equal(
    evaluate_check(check, dataset, "TS"),
    # row1: target blank, value populated -> TRUE
    # row2: target populated, value blank -> TRUE (a real difference)
    # row3: both blank                    -> FALSE (not a difference)
    c(TRUE, TRUE, FALSE)
  )
})

test_that("not_equal_to does NOT force on a blank Operations AGGREGATE comparator (CORE-000454)", {
  # The same blankness means something different when the comparator is an
  # aggregate that resolved to nothing, rather than a per-row column:
  # "could not be computed" is not a difference between two values.
  # CORE-000454's RFXENDTC (populated) vs $max_ex_exendtc (a max_date over
  # an all-blank column) must stay unresolved rather than be forced TRUE.
  # is_blank() can't tell the two apart - the SHAPE can, since an aggregate
  # is a scalar broadcast across rows.
  data <- data.table::data.table(TARGET = c("2020-01-01", "2020-02-01", ""))
  dataset <- list(data = data, meta = NULL)
  ctx <- list(
    name = "TARGET", exists = TRUE, target = data$TARGET,
    value = NA_character_, n = 3L,
    condition = list(operator = "not_equal_to"), dataset = dataset, domain = "EX"
  )
  res <- get_operator("not_equal_to")(ctx)
  # Rows 1-2: populated target vs an unresolvable scalar -> NOT forced.
  expect_true(all(is.na(res[1:2])))
})

test_that("equal_to/equal_to_case_insensitive treat two blank values as never equal (CORE-000195)", {
  # The reference engine's own truth table: equal_to("" or null, "" or
  # null) -> False, even though "" == "" is naturally TRUE in R. Confirmed
  # against CORE-000195's real fixture: a row with AESCAT and AEDECOD both
  # blank must not be flagged by "--SCAT equal_to_case_insensitive --DECOD".
  data <- data.table::data.table(A = c("", "X", "x"), B = c("", "X", "X"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "equal_to_case_insensitive", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, TRUE, TRUE))
})

test_that("equal_to_case_insensitive matches CDISC's reference results.csv (CORE-000195)", {
  rule <- .coreval_env$data$rules[["CORE-000195"]]
  for (case in c("negative", "positive")) {
    cases <- Sys.glob(test_path("fixtures", "core_rules", "CORE-000195", case, "*"))
    for (dir in cases) {
      study <- read_study(file.path(dir, "data"))
      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      for (domain in names(study$datasets)) {
        if (!rule_applies_to_domain(rule, domain)) next
        actual <- which(evaluate_rule(rule, study, domain))
        expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
        expect_equal(sort(unname(actual)), expected, info = paste(dir, domain))
      }
    }
  }
})

test_that("not_equal_to matches CDISC's reference results.csv across all domains (CORE-000542)", {
  rule <- .coreval_env$data$rules[["CORE-000542"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000542", case, "01")
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- which(evaluate_rule(rule, study, domain))
      expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
      expect_equal(sort(unname(actual)), expected, info = paste(case, domain))
    }
  }
})

test_that("ordinal comparisons between two character columns compare numbers as numbers", {
  # Bug (CORE-000698, PDVALTRG vs PDVALMIN): every variable read from an XPT
  # is character, so BOTH sides of a column-to-column ordinal comparison are
  # strings and nothing was coerced. Lexicographically "1000" < "999" is TRUE,
  # so coreval reported a target below its own minimum where there was none.
  data <- data.table::data.table(
    PDVALTRG = c("1000", "999", "9", "-69"),
    PDVALMIN = c("999", "1000", "65", "-69")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "PDVALTRG", operator = "less_than", value = "PDVALMIN")
  expect_equal(evaluate_check(check, dataset, "PD"), c(FALSE, TRUE, TRUE, FALSE))
})

test_that("a column mixing numbers and text keeps text comparisons as text", {
  # The columns these rules compare are mixed - numbers on the rows the rule
  # cares about, text elsewhere - so the numeric decision is made per row.
  # Rows where either side is not a number must behave exactly as before.
  data <- data.table::data.table(
    A = c("1000", "apple", "9"),
    B = c("999", "banana", "65")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "less_than", value = "B")
  expect_equal(evaluate_check(check, dataset, "PD"), c(FALSE, TRUE, TRUE))
})

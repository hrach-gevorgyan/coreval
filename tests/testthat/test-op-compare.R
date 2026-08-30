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

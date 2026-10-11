# Expected violation vector from a reference results.csv: one row per
# (Record, Variable) pair, filtered to one Dataset.
test_that("value falls back to a literal when no column matches it, even with value_is_literal absent", {
  # CORE-000006: `DTHFL not_equal_to Y` has no value_is_literal at all, and
  # no column named "Y" exists in DM. Found via the conformance harness:
  # resolve_condition_value() used to return NULL whenever `value` wasn't a
  # literal AND wasn't a real column, silently making the condition always
  # false (NA -> FALSE) instead of falling back to the literal text "Y".
  # CDISC's October 2026 release added `value_is_literal: true` to this rule,
  # which is what the fallback had been inferring all along. The fallback
  # itself is still what runs for a rule that omits the key, so it is checked
  # on a condition built here, where upstream cannot take it away.
  rule <- .coreval_env$data$rules[["CORE-000006"]]
  bare <- list(name = "DTHFL", operator = "not_equal_to", value = "Y")
  expect_null(bare$value_is_literal)
  dm <- list(data = data.table::data.table(DTHFL = c("Y", "N")), meta = NULL)
  expect_equal(
    evaluate_rule(list(check = list(all = list(bare))), dm, domain = "DM"),
    c(FALSE, TRUE)
  )

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000006", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$DM, domain = "DM")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DM", nrow(study$datasets$DM$data))
    )
  }
})

test_that("a multi-element literal value (e.g. is_not_contained_by: [Y, N]) resolves without value_is_literal", {
  # CORE-000123: `AESCAN is_not_contained_by [Y, N]` also has no
  # value_is_literal key. A multi-element `value` can never be a single
  # column reference, so it must fall through to the literal array on its
  # own - no length-based special-casing needed (an earlier, overly clever
  # version of resolve_condition_value() special-cased vectors for the
  # grouping operators and broke this case as a side effect).
  # As above, CDISC now states `value_is_literal` on this rule. A
  # multi-element value can never be a single column reference, so the
  # fallback has to reach the literal array on its own: checked on a condition
  # built here, then the rule itself is still graded against its fixtures.
  rule <- .coreval_env$data$rules[["CORE-000123"]]
  cond <- rule$check$all[[2]]
  expect_equal(cond$value, c("Y", "N"))
  bare <- list(name = "AESCAN", operator = "is_not_contained_by", value = c("Y", "N"))
  expect_null(bare$value_is_literal)
  ae <- list(data = data.table::data.table(AESCAN = c("Y", "N", "U")), meta = NULL)
  expect_equal(
    evaluate_rule(list(check = list(all = list(bare))), ae, domain = "AE"),
    c(FALSE, FALSE, TRUE)
  )

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000123", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$AE, domain = "AE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "AE", nrow(study$datasets$AE$data))
    )
  }
})

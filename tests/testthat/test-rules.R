test_that("list_rules returns the combined SDTMIG/ADaMIG rule set", {
  rules <- list_rules()
  expect_equal(nrow(rules), 507)
  expect_true(all(
    c("id", "source", "status", "standard", "authority", "rule_type",
      "executability", "sensitivity") %in% names(rules)
  ))
  expect_equal(length(unique(rules$id)), 507)

  by_source <- table(rules$source)
  expect_equal(unname(by_source[["published"]]), 332)
  expect_equal(unname(by_source[["deprecated_dir"]]), 163)
  expect_equal(unname(by_source[["fda_business_rules_draft"]]), 12)
})

test_that("rules_version reports the pinned upstream SHA", {
  expect_true(nzchar(rules_version()))
})

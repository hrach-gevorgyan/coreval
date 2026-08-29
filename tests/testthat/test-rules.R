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

test_that("YAML 1.1 boolean literals in `value` are preserved as text, not coerced", {
  # Regression test: bare Y/N (and yes/no/true/false/on/off) are YAML 1.1
  # booleans. Extremely common SDTM Y/N flag literals like `value: Y` were
  # silently corrupted into logical TRUE/FALSE by the default yaml parser.
  rules <- .coreval_env$data$rules

  c6 <- rules[["CORE-000006"]]$check$all[[1]]
  expect_identical(c6$value, "Y")
  expect_type(c6$value, "character")

  # The schema's actual boolean flags must still come through as real
  # logicals, not as the literal strings "true"/"TRUE".
  c1 <- rules[["CORE-000001"]]$check$all[[1]]
  expect_identical(c1$value_is_literal, TRUE)

  walk_check <- function(check, hits = list()) {
    if (is.null(check)) {
      return(hits)
    }
    if (!is.null(check$name) && !is.null(check$value) && is.logical(check$value)) {
      hits[[length(hits) + 1]] <- check
    }
    for (key in c("all", "any", "not")) {
      sub <- check[[key]]
      if (!is.null(sub)) {
        if (is.list(sub) && is.null(names(sub))) {
          for (item in sub) hits <- walk_check(item, hits)
        } else {
          hits <- walk_check(sub, hits)
        }
      }
    }
    hits
  }
  bad <- list()
  for (r in rules) bad <- c(bad, walk_check(r$check))
  expect_length(bad, 0)
})

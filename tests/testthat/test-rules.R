test_that("list_rules returns the combined SDTMIG/SENDIG/TIG/ADaMIG rule set", {
  rules <- list_rules()
  expect_equal(nrow(rules), 756)
  expect_true(all(
    c("id", "source", "status", "standard", "authority", "rule_type",
      "executability", "sensitivity") %in% names(rules)
  ))
  expect_equal(length(unique(rules$id)), 756)

  by_source <- table(rules$source)
  expect_equal(unname(by_source[["published"]]), 566)
  expect_equal(unname(by_source[["deprecated_dir"]]), 163)
  expect_equal(unname(by_source[["fda_business_rules_draft"]]), 27)
})

test_that("rules_version reports the pinned upstream SHA", {
  expect_true(nzchar(rules_version()))
})

test_that("YAML 1.1 single-letter Y/N is preserved as text, but a full-word boolean becomes a real logical", {
  # Regression test: bare Y/N (and yes/no/true/false/on/off) are YAML 1.1
  # booleans under R's yaml package. But the reference engine (Python,
  # PyYAML) is NOT this permissive - PyYAML's own bool resolver regex only
  # matches the FULL words yes/no/true/false/on/off (in various cases),
  # never a bare single-letter Y/N. So a genuine SDTM flag literal like
  # `value: Y` must stay the string "Y" (matching Python's own non-boolean
  # treatment), but a full-word boolean like `value: true` (used to compare
  # against an Operations binding like $EXVAMT_EXISTS) must become a REAL
  # logical, matching what PyYAML actually hands the reference engine -
  # confirmed necessary against CORE-000291's real fixture, where treating
  # `true` as the literal string "true" made a boolean comparison always
  # false (R's as.character(TRUE) is "TRUE", not "true").
  rules <- .coreval_env$data$rules

  c6 <- rules[["CORE-000006"]]$check$all[[1]]
  expect_identical(c6$value, "Y")
  expect_type(c6$value, "character")

  # The schema's actual boolean flags must still come through as real
  # logicals, not as the literal strings "true"/"TRUE".
  c1 <- rules[["CORE-000001"]]$check$all[[1]]
  expect_identical(c1$value_is_literal, TRUE)

  # A genuine full-word boolean Check value is a real logical, and every
  # occurrence found is legitimately a boolean-natured comparator (an
  # Operations binding like $EXVAMT_EXISTS/$domain_is_custom, or
  # define_dataset_has_no_data) - never an accidentally-corrupted SDTM
  # value literal.
  ev <- rules[["CORE-000291"]]$check$all[[1]]
  expect_identical(ev$name, "$EXVAMT_EXISTS")
  expect_identical(ev$value, TRUE)

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
  logical_value_checks <- list()
  for (r in rules) logical_value_checks <- c(logical_value_checks, walk_check(r$check))
  expect_true(all(vapply(logical_value_checks, function(h) startsWith(h$name, "$") || grepl("_exists|is_custom|has_no_data", h$name, ignore.case = TRUE), logical(1))))
})

test_that("the bundled CDISC material ships with its required licence notice", {
  # cdisc-open-rules is MIT, and MIT requires the copyright and permission
  # notice to travel with "substantial portions of the Software". coreval
  # bundles 756 extracted rules plus CDISC standards metadata, so the notice
  # has to be IN THE INSTALLED PACKAGE - NOTICE.md at the repo root is
  # Rbuildignored and never reaches anyone who installs it.
  path <- system.file("COPYRIGHTS", package = "coreval")
  expect_true(nzchar(path))
  expect_true(file.exists(path))

  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_match(txt, "MIT License", fixed = TRUE)
  expect_match(txt, "Copyright (c) 2026 cdisc", fixed = TRUE)
  # The permission notice itself, not merely a reference to it.
  expect_match(txt, "shall be included in all", fixed = TRUE)
  # And it must name what is actually bundled.
  expect_match(txt, "rules.rds", fixed = TRUE)
})

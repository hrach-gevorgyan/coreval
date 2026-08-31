demo <- function() {
  data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02", "03"),
    RFSTDTC = c("2024-01-05", "2024-13-01", ""),
    AGE = c(34, 61, 47), AGEU = c("YEARS", "", ""),
    SEX = c("M", "F", "F"), stringsAsFactors = FALSE
  )
}

test_that("rule_info answers the question the report raises", {
  # The report hands you "CORE-000547". Before this there was no way to ask R
  # what that means: list_rules() carried sensitivity and executability but
  # not what the rule actually CHECKS.
  info <- rule_info("CORE-000547")
  expect_equal(nrow(info), 1)
  expect_match(info$issue, "ISO 8601")
  expect_true(nzchar(info$description))
  expect_true(all(c("standard", "authority", "source", "sensitivity") %in% names(info)))

  # Several at once, in the order asked for - so it composes with a result.
  many <- rule_info(c("CORE-000189", "CORE-000547"))
  expect_equal(many$id, c("CORE-000189", "CORE-000547"))

  # An unknown id says so, and says what an id looks like.
  expect_error(rule_info("CORE-999999"), "no such rule")
  expect_error(rule_info("CORE-999999"), "CORE-000547")
})

test_that("list_rules now carries what each rule checks", {
  rules <- list_rules()
  expect_true("issue" %in% names(rules))
  expect_true(all(nzchar(rules$issue)))
  expect_match(rules$issue[rules$id == "CORE-000547"], "ISO 8601")
})

test_that("summary reports the same counts the full report does", {
  result <- check_dataset(demo(), standard = "SDTMIG")
  out <- capture.output(s <- summary(result))
  joined <- paste(out, collapse = "\n")

  expect_match(joined, "problem")
  expect_match(joined, "checks ran")

  # The returned row must agree with the findings it summarized, or it is
  # worse than useless for logging.
  expect_equal(s$problems, length(unique(paste(
    result$findings$Dataset, result$findings$rule_id
  ))))
  expect_equal(s$could_not_run, nrow(result$skipped))
  expect_equal(
    s$wrong_value + s$missing_required + s$missing_optional,
    s$problems
  )
})

test_that("summary handles a clean result without erroring", {
  clean <- structure(
    list(
      findings = data.table::data.table(
        Dataset = character(0), Record = integer(0), Variable = character(0),
        Value = character(0), issue = character(0), triage = character(0),
        rule_id = character(0)
      ),
      skipped = data.table::data.table(
        rule_id = character(0), domain = character(0), reason = character(0)
      ),
      truncated = data.table::data.table(
        rule_id = character(0), domain = character(0),
        records_found = integer(0), records_kept = integer(0)
      )
    ),
    class = "coreval_result", checks_run = 100L, domains = "DM"
  )
  out <- capture.output(s <- summary(clean))
  expect_equal(s$problems, 0)
  expect_equal(s$records, 0)
})

test_that("filter_findings narrows, and what comes back still reads as a report", {
  result <- check_dataset(demo(), standard = "SDTMIG")

  wrong <- filter_findings(result, triage = "wrong value")
  expect_s3_class(wrong, "coreval_result")
  expect_true(all(wrong$findings$triage == "wrong value"))
  expect_true(nrow(wrong$findings) < nrow(result$findings))

  out <- paste(capture.output(print(wrong)), collapse = "\n")
  expect_match(out, "coreval")
  # It must SAY it is a subset: a screenshot of "2 problems" would otherwise
  # read as the whole picture.
  expect_match(out, "filtered")

  # What could not be checked does not become less true because you narrowed
  # what you are looking at.
  expect_equal(nrow(wrong$skipped), nrow(result$skipped))
})

test_that("filter_findings accepts the other selectors, and refuses nonsense", {
  result <- check_dataset(demo(), standard = "SDTMIG")

  by_rule <- filter_findings(result, rule = "CORE-000189")
  expect_equal(unique(by_rule$findings$rule_id), "CORE-000189")

  by_var <- filter_findings(result, variable = "AGEU")
  expect_equal(unique(by_var$findings$Variable), "AGEU")

  # Case-insensitive dataset, since people type "dm".
  expect_equal(
    nrow(filter_findings(result, dataset = "dm")$findings),
    nrow(filter_findings(result, dataset = "DM")$findings)
  )

  # Combined selectors intersect.
  both <- filter_findings(result, triage = "wrong value", rule = "CORE-000189")
  expect_true(all(both$findings$rule_id == "CORE-000189"))

  expect_error(filter_findings(result, triage = "critical"), "no such triage level")
  expect_error(filter_findings(result, triage = "critical"), "wrong value")
  expect_error(filter_findings(list()), "check_dataset")
})

test_that("filtering to nothing gives an empty result that still prints", {
  result <- check_dataset(demo(), standard = "SDTMIG")
  none <- filter_findings(result, rule = "CORE-000001")
  expect_equal(nrow(none$findings), 0)
  expect_no_error(capture.output(print(none)))
})

test_that("every rule carries the ids Pinnacle 21 uses, and the guidance it enforces", {
  # CDISC publishes no severity, so the practical substitute is the legacy
  # conformance-rule id - what P21 and the Conformance Rules spreadsheets call
  # the same rule - plus the IG sentence explaining WHY it exists.
  rules <- .coreval_env$data$rules
  expect_true(all(vapply(rules, function(r) length(r$legacy_ids) > 0, logical(1))))
  expect_true(all(vapply(rules, function(r) length(r$citations) > 0, logical(1))))

  info <- rule_info("CORE-000189")
  expect_match(info$legacy_ids, "CG0665")
  expect_true(nzchar(info$guidance))

  # Scoped to the standards the rule was kept for: quoting a SEND id on an
  # SDTM-only rule would send the reader to the wrong row of the spreadsheet.
  iso <- .coreval_env$data$rules[["CORE-000547"]]
  expect_true(all(grepl("^(SEND|TIG)", iso$legacy_ids)))
  expect_false(any(grepl("^CG", iso$legacy_ids)))
})

test_that("the report shows the legacy ids, and guidance only when asked", {
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02"),
    RFSTDTC = c("2024-01-05", "2024-13-01"), AGE = c(34, 61),
    AGEU = c("YEARS", ""), SEX = c("M", "F"), stringsAsFactors = FALSE
  )
  result <- check_dataset(dm)

  plain <- paste(capture.output(print(result)), collapse = "\n")
  expect_match(plain, "also CG0665")

  # Guidance roughly doubles the report, so it is opt-in.
  expect_false(grepl("Variable Qualifier of AGE", plain, fixed = TRUE))
  verbose <- paste(capture.output(print(result, guidance = TRUE)), collapse = "\n")
  expect_match(verbose, "Variable Qualifier of AGE", fixed = TRUE)
  expect_true(nchar(verbose) > nchar(plain))
})

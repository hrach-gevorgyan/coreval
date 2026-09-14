# The conformance harness grades rules by calling the evaluator directly, and
# supplies things a user never does. Three times that let a rule pass every
# score while doing nothing for a real user: a USDM study declaring "4.0.0"
# matched no rule and was reported clean, the JSONata rules were never reached
# from check_study() at all, and 37 terminology rules demanded a study-wide
# setting the harness always filled in. These tests go through the functions a
# user calls, with nothing supplied that a user would not supply.

skip_if_no_usdm <- function() {
  testthat::skip_if_not(
    requireNamespace("jsonlite", quietly = TRUE) &&
      requireNamespace("QuickJSR", quietly = TRUE),
    "jsonlite and QuickJSR are needed to check a USDM study"
  )
}

write_usdm_study <- function(version = "4.0.0") {
  dir <- tempfile("coreval_user_usdm_")
  dir.create(dir)
  # One study design with no main timeline, which CORE-000407 forbids.
  writeLines(paste0(
    '{"usdmVersion": "', version, '", "systemName": "test", "systemVersion": "1",',
    ' "study": {"id": "S1", "name": "Study", "instanceType": "Study",',
    '  "versions": [{"id": "SV1", "instanceType": "StudyVersion",',
    '   "studyDesigns": [{"id": "SD1", "name": "Design 1",',
    '     "instanceType": "InterventionalStudyDesign",',
    '     "scheduleTimelines": []}]}]}}'
  ), file.path(dir, "study.json"))
  dir
}

test_that("a USDM study is actually checked, and its problems are found", {
  skip_if_no_usdm()
  dir <- write_usdm_study()
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  result <- check_study(dir)
  expect_gt(attr(result, "checks_run"), 0)
  expect_true("CORE-000407" %in% result$findings$rule_id)
  # Reported against the entity and row the finding is about, the same numbers
  # the record-data USDM rules use.
  hit <- result$findings[result$findings$rule_id == "CORE-000407", ]
  expect_true(all(hit$Dataset == "INTERVENTIONALSTUDYDESIGN"))
  expect_true(all(hit$Record == 1L))
})

test_that("a rule written as an expression runs once per study, not once per table", {
  skip_if_no_usdm()
  dir <- write_usdm_study()
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  result <- check_study(dir)
  # The unsupported schema rules are listed once each, not once per entity.
  schema <- result$skipped[grepl("JSON Schema Check", result$skipped$reason), ]
  expect_equal(nrow(schema), length(unique(schema$rule_id)))
})

test_that("a version written with extra zeros still selects its rules", {
  expect_equal(coreval:::normalise_version(c("4.0.0", "4.0", "4", "3-4", "3.10")),
               c("4", "4", "4", "3.4", "3.10"))
  expect_true(coreval:::targets_standard_version("USDM 4.0", "usdm", "4.0.0"))
  expect_false(coreval:::targets_standard_version("SDTMIG 3.1", "SDTMIG", "3.10"))
})

test_that("a check where no rule applies is refused rather than reported clean", {
  # A made-up domain under a declared standard selects nothing to run.
  expect_error(
    check_dataset(data.frame(STUDYID = "S1", ZZTESTCD = "A"), domain = "ZZ",
                  standard = "USDM"),
    "nothing was checked"
  )
})

test_that("one dataset is not told what the rest of the study lacks", {
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("S1-1", "S1-2"),
    AGE = c(30, 40), AGEU = c("YEARS", "YEARS")
  )
  result <- check_dataset(dm)
  presence <- vapply(result$findings$rule_id, function(id) {
    startsWith(coreval:::.coreval_env$data$rules[[id]]$rule_type, "Domain Presence Check")
  }, logical(1))
  expect_false(any(presence))
  expect_true(any(grepl("whole study contains", result$skipped$reason)))
})

test_that("a data frame with no labels is not reported for wrong labels", {
  dm <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = "S1-1")
  result <- check_dataset(dm)
  label_rules <- c("CORE-000019", "CORE-000398", "CORE-000507", "CORE-000594",
                   "CORE-000690", "CDISC.SENDIG.6A")
  expect_false(any(result$findings$rule_id %in% label_rules))

  # With labels present, a wrong one is still reported.
  labelled <- dm
  attr(labelled$STUDYID, "label") <- "Not the right label"
  attr(labelled$DOMAIN, "label") <- "Domain Abbreviation"
  attr(labelled$USUBJID, "label") <- "Unique Subject Identifier"
  result <- check_dataset(labelled)
  expect_true("CORE-000398" %in% result$findings$rule_id)
})

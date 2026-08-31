demo_dm <- function() {
  data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02"),
    RFSTDTC = c("2024-01-05", "2024-13-01"), # month 13
    AGE = c(34, 61), AGEU = c("YEARS", ""),
    SEX = c("M", "F"), stringsAsFactors = FALSE
  )
}

test_that("every finding carries a plain-language description of the problem", {
  # The reason this column exists: "CORE-000547" is not actionable on its own.
  result <- check_dataset(demo_dm())
  expect_true("issue" %in% names(result$findings))
  expect_true(all(nzchar(result$findings$issue)))

  iso <- result$findings[result$findings$rule_id == "CORE-000547", ]
  expect_match(iso$issue[1], "ISO 8601")
})

test_that("rule_message prefers the rule's Message, and falls back to its description", {
  rule <- .coreval_env$data$rules[["CORE-000547"]]
  expect_equal(rule_message(rule), rule$outcome[["Message"]])

  # Every bundled rule has a Message today, so the fallback is only reachable
  # with a hand-made rule - but it must not print an empty line if that ever
  # changes upstream.
  expect_equal(rule_message(list(description = "some rule text")), "some rule text")
  expect_match(rule_message(list()), "no description")
})

test_that("the printed report explains the problem, not just the rule number", {
  result <- check_dataset(demo_dm())
  out <- paste(capture.output(print(result)), collapse = "\n")

  expect_match(out, "ISO 8601")             # what is wrong, in words
  expect_match(out, "RFSTDTC")              # which variable
  expect_match(out, "2024-13-01")           # the offending value
  expect_match(out, "CORE-000547")          # still traceable to the rule
  expect_match(out, "checks ran")           # how much actually ran
  expect_match(out, "could not run")        # and how much did not
  expect_match(out, "write_findings")       # what to do next
})

test_that("the report hides coreval's internal bindings from the reader", {
  # `$dataset_variables` is an Operations binding, not a column of anyone's
  # data. Printing "$dataset_variables = STUDYID" is noise.
  result <- check_dataset(demo_dm())
  out <- paste(capture.output(print(result)), collapse = "\n")
  expect_false(grepl("$dataset_variables", out, fixed = TRUE))
})

test_that("a variable absent from the dataset is said once, not once per row", {
  # Repeating 'row 1 SUBJID = Not in dataset' for every row says the same
  # thing N times and pushes the useful findings off the screen.
  result <- check_dataset(demo_dm())
  out <- paste(capture.output(print(result)), collapse = "\n")
  expect_match(out, "not in the dataset: ")
  expect_lt(lengths(regmatches(out, gregexpr("Not in dataset", out)))[1], 3)
})

test_that("a clean result says so plainly instead of printing an empty table", {
  clean <- structure(
    list(
      findings = data.table::data.table(
        Dataset = character(0), Record = integer(0), Variable = character(0),
        Value = character(0), issue = character(0), rule_id = character(0)
      ),
      skipped = data.table::data.table(
        rule_id = character(0), domain = character(0), reason = character(0)
      )
    ),
    class = "coreval_result", checks_run = 120L, domains = "DM"
  )
  out <- paste(capture.output(print(clean)), collapse = "\n")
  expect_match(out, "Nothing to fix")
  expect_match(out, "120")
})

test_that("print returns its input invisibly, so it composes normally", {
  result <- check_dataset(demo_dm())
  capture.output(expect_invisible(print(result)))
  capture.output(back <- print(result))
  expect_identical(back$findings, result$findings)
})

test_that("write_findings adds empty columns to fill in, and can leave them out", {
  result <- check_dataset(demo_dm())
  dir <- tempfile("coreval_track_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  paths <- write_findings(result, file.path(dir, "issues.csv"))
  back <- data.table::fread(paths[1], colClasses = "character")
  expect_true(all(c("Status", "Owner", "Notes") %in% names(back)))
  expect_true(all(back$Status == ""))
  # The issue text has to survive the round trip, or the spreadsheet is as
  # useless as the console output was.
  expect_true("issue" %in% names(back))
  expect_true(all(nzchar(back$issue)))

  # Skipped rules get the same columns: deciding "we accept this gap" is a
  # tracked decision too.
  skipped_back <- data.table::fread(paths[2], colClasses = "character")
  expect_true(all(c("Status", "Owner", "Notes") %in% names(skipped_back)))

  plain <- write_findings(result, file.path(dir, "plain.csv"), tracking = FALSE)
  expect_false("Status" %in% names(data.table::fread(plain[1])))
})

test_that("write_findings does not mutate the result it was given", {
  # The tracking columns are added to a copy; a second call, or any later use
  # of result$findings, must not see Status/Owner/Notes bolted on.
  result <- check_dataset(demo_dm())
  before <- names(result$findings)
  dir <- tempfile("coreval_nomutate_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  write_findings(result, file.path(dir, "issues.csv"))
  expect_equal(names(result$findings), before)
})

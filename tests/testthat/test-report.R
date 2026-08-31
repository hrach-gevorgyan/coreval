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

test_that("a set-valued binding reports the whole set, not its first element", {
  # The bug this guards: value_at() indexed an atomic binding by row number.
  # $expected_variables holds 17 names; row 1 gave "RFSTDTC", which was then
  # reported as if RFSTDTC were the finding - while the variables actually
  # missing were never named anywhere.
  result <- check_dataset(demo_dm())
  req <- result$findings[result$findings$Variable == "$required_variables", ]
  skip_if(nrow(req) == 0)
  expect_match(req$Value[1], "^\\[")           # a set, rendered as ['A', 'B']
  parsed <- parse_set_value(req$Value[1])
  expect_gt(length(parsed), 1)
  expect_true("SUBJID" %in% parsed)
})

test_that("parse_set_value understands the reference engine's set format", {
  expect_equal(parse_set_value("['A', 'B', 'C']"), c("A", "B", "C"))
  expect_equal(parse_set_value("['A']"), "A")
  expect_equal(parse_set_value("[]"), character(0))
  # A plain value is not a set and comes back untouched.
  expect_equal(parse_set_value("AESTDTC"), "AESTDTC")
  expect_equal(parse_set_value(NA_character_), NA_character_)
})

test_that("binding_gap names what is missing, and stays quiet when it cannot tell", {
  sets <- list(
    `$required_variables` = c("STUDYID", "SUBJID", "SITEID"),
    `$dataset_variables` = c("STUDYID", "AGE")
  )
  gap <- binding_gap(sets)
  expect_equal(gap$missing, c("SUBJID", "SITEID"))
  expect_equal(gap$label, "required variables")

  # Nothing missing -> nothing to say.
  expect_null(binding_gap(list(
    `$required_variables` = "STUDYID",
    `$dataset_variables` = c("STUDYID", "AGE")
  )))
  # No binding identifiable as "what the dataset has" -> do not guess.
  expect_null(binding_gap(list(`$a` = "X", `$b` = "Y")))
  expect_null(binding_gap(list(`$dataset_variables` = "X")))
})

test_that("the report names the missing variables instead of saying 'at least one'", {
  # CDISC's own wording is "At least one required variable is missing from
  # dataset", which does not say which. Both sets are in the finding, so the
  # difference between them can be shown.
  result <- check_dataset(demo_dm())
  out <- paste(capture.output(print(result)), collapse = "\n")
  expect_match(out, "missing required variables: ")
  expect_match(out, "SUBJID")
})

test_that("a finding reports every variable on the row that holds a value", {
  # Rules that compare a variable's label against the IG's label are useless
  # if only one side is shown.
  result <- check_dataset(demo_dm())
  out <- paste(capture.output(print(result)), collapse = "\n")
  expect_match(out, 'AGE = "61", AGEU = \\(empty\\)')
})

test_that("a whole-study report is grouped by dataset, worst first", {
  dir <- tempfile("coreval_studyrep_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  haven::write_xpt(demo_dm(), file.path(dir, "dm.xpt"))
  haven::write_xpt(
    data.frame(
      STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
      AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
      AESTDTC = c("2024-01-10", "2024-02-30"), stringsAsFactors = FALSE
    ),
    file.path(dir, "ae.xpt")
  )

  result <- check_study(read_study(dir))
  out <- capture.output(print(result))
  joined <- paste(out, collapse = "\n")

  # A summary of where the trouble is, before any detail.
  expect_match(joined, "in \\d+ datasets")
  expect_match(joined, "DM\\s+\\d+ problems")
  expect_match(joined, "AE\\s+\\d+ problems")

  # Then a banner per dataset, and the summary comes first.
  dm_banner <- grep("^\\S+ DM ", out)
  ae_banner <- grep("^\\S+ AE ", out)
  expect_length(dm_banner, 1)
  expect_length(ae_banner, 1)
  expect_lt(grep("problems", out)[1], min(dm_banner, ae_banner))

  # Findings appear under their own dataset's banner, not mixed together.
  iso_lines <- grep("CORE-000547", out)
  expect_true(length(iso_lines) > 0)
})

test_that("n limits problems per dataset, not across the whole study", {
  dir <- tempfile("coreval_limit_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  haven::write_xpt(demo_dm(), file.path(dir, "dm.xpt"))
  haven::write_xpt(
    data.frame(
      STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
      AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
      AESTDTC = c("2024-01-10", "2024-02-30"), stringsAsFactors = FALSE
    ),
    file.path(dir, "ae.xpt")
  )
  result <- check_study(read_study(dir))
  out <- capture.output(print(result, n = 1))
  # Each dataset that had more than one problem says so separately.
  expect_gt(length(grep("more here", out)), 1)
})

test_that("triage separates values that are wrong from things merely absent", {
  # The distinction that governs what you look at first. A month of 13 is
  # never right. An empty RFSTDTC may be a screen-failure subject, or raw data
  # you have not received - coreval cannot know, and must not pretend to.
  result <- check_dataset(demo_dm())
  expect_true("triage" %in% names(result$findings))
  expect_true(all(result$findings$triage %in% TRIAGE_LEVELS))

  iso <- result$findings[result$findings$rule_id == "CORE-000547", ]
  expect_equal(unique(iso$triage), "wrong value")
})

test_that("finding_triage classifies from the finding itself", {
  wrong <- data.table::data.table(
    Variable = "RFSTDTC", Value = "2024-13-01", issue = "bad date"
  )
  expect_equal(finding_triage(wrong), "wrong value")

  # A required variable set that is short: the binding the rule used says
  # "required" outright, so no guessing from wording is needed.
  req <- data.table::data.table(
    Variable = c("$required_variables", "$dataset_variables"),
    Value = c("['A']", "['B']"), issue = "at least one required variable"
  )
  expect_equal(finding_triage(req), "missing required")

  exp <- data.table::data.table(
    Variable = c("$expected_variables", "$dataset_variables"),
    Value = c("['A']", "['B']"), issue = "at least one expected variable"
  )
  expect_equal(finding_triage(exp), "missing optional")

  # A variable simply absent, with nothing marking it required, is the
  # lowest tier - it may be entirely legitimate for this study.
  absent <- data.table::data.table(
    Variable = "EPOCH", Value = "Not in dataset", issue = "EPOCH is missing"
  )
  expect_equal(finding_triage(absent), "missing optional")

  # A blank value is absent, not wrong.
  blank <- data.table::data.table(
    Variable = "RFSTDTC", Value = "", issue = "no value"
  )
  expect_equal(finding_triage(blank), "missing optional")
})

test_that("the report leads with wrong values, not with things merely absent", {
  result <- check_dataset(demo_dm())
  out <- capture.output(print(result))

  # The summary names each tier with a plain-language hint.
  expect_match(paste(out, collapse = "\n"), "wrong value\\s+\\d+\\s+the data breaks the rule")
  expect_match(paste(out, collapse = "\n"), "often legitimate")

  # Every "wrong value" problem is printed before any "missing optional" one.
  first_wrong <- grep("[wrong value]", out, fixed = TRUE)[1]
  first_optional <- grep("[missing optional]", out, fixed = TRUE)[1]
  expect_lt(first_wrong, first_optional)
})

test_that("within a problem, the record holding a real bad value is shown first", {
  # RFSTDTC is EMPTY on an earlier row and "2024-13-01" on a later one, so the
  # natural row order puts the harmless-looking one first. Leading with an
  # empty value buries the one that certainly is wrong - the complaint that
  # prompted triage in the first place.
  #
  # The empty row has to come FIRST in the data or this asserts nothing, which
  # is exactly what happened when this test was written against a fixture that
  # had no empty value at all: its skip_if() guard made it vacuous.
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02", "03"),
    RFSTDTC = c("2024-01-05", "", "2024-13-01"),
    AGE = c(34, 61, 47), AGEU = c("YEARS", "YEARS", "YEARS"),
    SEX = c("M", "F", "F"), stringsAsFactors = FALSE
  )
  result <- check_dataset(dm)
  out <- capture.output(print(result))

  iso_block <- out[grep("ISO 8601", out)[1]:length(out)]
  bad <- grep("2024-13-01", iso_block)[1]
  empty <- grep("RFSTDTC = \\(empty\\)", iso_block)[1]
  expect_false(is.na(bad))
  expect_false(is.na(empty))
  expect_lt(bad, empty)
})

test_that("triage survives export, so a spreadsheet can be sorted by it", {
  result <- check_dataset(demo_dm())
  dir <- tempfile("coreval_triage_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  paths <- write_findings(result, file.path(dir, "issues.csv"))
  back <- data.table::fread(paths[1], colClasses = "character")
  expect_true("triage" %in% names(back))
  expect_true(all(back$triage %in% TRIAGE_LEVELS))
})

test_that("a rule flagging every row is capped, and the true count is still reported", {
  # A missing variable on a large dataset is one finding per row. Keeping them
  # all is unreadable, exceeds Excel's row limit, and dominated the runtime -
  # but a capped count must never be mistaken for the real one.
  n <- 300
  d <- data.frame(
    STUDYID = "S1", DOMAIN = "LB", USUBJID = sprintf("%03d", seq_len(n) %% 50),
    LBSEQ = seq_len(n), LBTESTCD = "ALT",
    LBDTC = "2024-01-10", stringsAsFactors = FALSE
  )
  capped <- check_dataset(d, max_records = 10)

  expect_true(nrow(capped$truncated) > 0)
  expect_true(all(capped$truncated$records_kept <= 10))
  expect_true(all(capped$truncated$records_found > capped$truncated$records_kept))

  # No rule keeps more than the cap.
  per_rule <- tapply(capped$findings$Record, capped$findings$rule_id,
                     function(r) length(unique(r)))
  expect_true(all(per_rule <= 10))

  # The report states the true number, not the kept one, and says it is cut.
  out <- paste(capture.output(print(capped)), collapse = "\n")
  biggest <- capped$truncated$records_found[which.max(capped$truncated$records_found)]
  expect_match(out, paste0(biggest, " records"))
  expect_match(out, "first 10 kept")
})

test_that("max_records = Inf keeps everything, and the cap changes nothing else", {
  n <- 60
  d <- data.frame(
    STUDYID = "S1", DOMAIN = "LB", USUBJID = sprintf("%03d", seq_len(n) %% 20),
    LBSEQ = seq_len(n), LBTESTCD = "ALT", LBDTC = "2024-01-10",
    stringsAsFactors = FALSE
  )
  full <- check_dataset(d, max_records = Inf)
  expect_equal(nrow(full$truncated), 0)

  # Capping must only ever DROP records - never change which rules fire, nor
  # what any kept finding says.
  capped <- check_dataset(d, max_records = 5)
  expect_setequal(unique(capped$findings$rule_id), unique(full$findings$rule_id))
  expect_setequal(unique(capped$findings$issue), unique(full$findings$issue))
  expect_true(nrow(capped$findings) < nrow(full$findings))
})

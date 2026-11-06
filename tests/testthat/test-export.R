test_that("write_findings writes both tables to CSV, not just the findings", {
  # A short findings table can mean clean data OR that many rules were
  # skipped, and those look identical if the skipped table is dropped - so
  # both are always written.
  result <- list(
    findings = data.table::data.table(
      rule_id = "CORE-000001", Dataset = "AE", Record = 1L,
      Variable = "AETERM", Value = "x"
    ),
    skipped = data.table::data.table(
      rule_id = "CORE-000002", domain = "AE", reason = "unsupported rule type"
    )
  )
  dir <- tempfile("coreval_out_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))

  out <- file.path(dir, "issues.csv")
  written <- write_findings(result, out)

  # findings, skipped, and an `about` file carrying provenance. `truncated`
  # joins them only when a rule actually matched more records than were kept.
  expect_length(written, 4)
  expect_true(all(file.exists(written)))
  # each lands in a sibling file, with the suffix before the extension
  expect_equal(basename(written[2]), "issues_skipped.csv")
  expect_equal(basename(written[3]), "issues_about.csv")

  back <- data.table::fread(written[1])
  expect_equal(back$rule_id, "CORE-000001")
  expect_equal(data.table::fread(written[2])$reason, "unsupported rule type")
})

test_that("write_findings gives an actionable error for .xlsx without writexl", {
  result <- list(
    findings = data.table::data.table(Dataset = "AE", rule_id = "CORE-000001"),
    skipped = data.table::data.table(rule_id = character(0))
  )
  path <- file.path(tempdir(), "x.xlsx")
  if (requireNamespace("writexl", quietly = TRUE)) {
    on.exit(unlink(path))
    expect_equal(write_findings(result, path), path)
    expect_true(file.exists(path))
    # Assert the CONTENTS, not merely that a file appeared - a workbook with
    # the right name and the wrong sheets passed before. An .xlsx is a zip,
    # so this reads the sheet names out of xl/workbook.xml and the cell text
    # out of sharedStrings.xml with base R: no readxl, so the assertion
    # actually runs rather than skipping on a machine that lacks it.
    unpacked <- file.path(tempdir(), "coreval_xlsx_check")
    on.exit(unlink(unpacked, recursive = TRUE), add = TRUE)
    utils::unzip(path, exdir = unpacked)

    workbook <- paste(readLines(file.path(unpacked, "xl", "workbook.xml"),
                                warn = FALSE), collapse = "")
    for (sheet in c("Problems", "Records", "Not checked", "Rules")) {
      expect_match(workbook, paste0('name="', sheet, '"'), fixed = TRUE, info = sheet)
    }

    strings <- paste(readLines(file.path(unpacked, "xl", "sharedStrings.xml"),
                               warn = FALSE), collapse = "")
    expect_match(strings, "CORE-000001", fixed = TRUE)
  } else {
    # The point is that it fails BEFORE writing anything, and says how to
    # fix it - not that it fails part-way through.
    expect_error(write_findings(result, path), "writexl")
    expect_false(file.exists(path))
  }
})

test_that("write_findings rejects something that isn't a check_study() result", {
  expect_error(write_findings(list(), tempfile()), "check_study")
  expect_error(write_findings("not a result", tempfile()), "check_study")
})

test_that("write_findings rejects a path that isn't a single string", {
  result <- check_dataset(
    data.frame(STUDYID = "S", DOMAIN = "DM", USUBJID = "1"),
    "DM", standard = "SDTMIG"
  )
  # Left to fwrite, a number came back as
  # "is.character(file) && length(file) == 1L ... is not TRUE", and two paths
  # failed inside the `if` choosing the format with "the condition has
  # length > 1". Both should name the argument instead.
  expect_error(write_findings(result, 1), "`path` must be a single file path")
  expect_error(
    write_findings(result, c("a.csv", "b.csv")),
    "`path` must be a single file path"
  )
  expect_error(write_findings(result, NA_character_), "`path` must be a single file path")
  expect_error(write_findings(result, ""), "`path` must be a single file path")
  expect_error(write_findings(result, NULL), "`path` must be a single file path")
})

test_that("write_findings stops CSV cells from running as spreadsheet formulas", {
  # Findings quote the submission data, so a value beginning with `=` reached
  # the CSV as written and Excel ran it on opening.
  result <- list(
    findings = data.table::data.table(
      rule_id = "CORE-000001", Dataset = "AE", Record = 1:5,
      Variable = "AESTDTC",
      Value = c("=cmd|' /C calc'!A0", "+1+1", "@SUM(A1)", "-5", "2024-01-01")
    ),
    skipped = data.table::data.table(rule_id = character(0), domain = character(0),
                                     reason = character(0))
  )
  dir <- tempfile("coreval_out_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  out <- file.path(dir, "issues.csv")
  write_findings(result, out, tracking = FALSE)

  back <- data.table::fread(out, colClasses = "character")
  expect_equal(back$Value, c("'=cmd|' /C calc'!A0", "'+1+1", "'@SUM(A1)", "-5", "2024-01-01"))
  # UTF-8 with a byte order mark, so Excel shows non-English text correctly.
  expect_equal(readBin(out, "raw", 3), as.raw(c(0xEF, 0xBB, 0xBF)))
})

test_that("write_findings puts CSV siblings next to the file even in a dotted folder", {
  result <- list(
    findings = data.table::data.table(rule_id = "CORE-000001"),
    skipped = data.table::data.table(rule_id = character(0), domain = character(0),
                                     reason = character(0))
  )
  dir <- file.path(tempfile("coreval_out_"), "study.v2")
  dir.create(dir, recursive = TRUE)
  on.exit(unlink(dirname(dir), recursive = TRUE))

  written <- write_findings(result, file.path(dir, "issues"))
  # Compared by basename and folder so the test can fail on any platform.
  expect_equal(basename(written), c("issues", "issues_skipped", "issues_about", "issues_summary"))
  expect_true(all(basename(dirname(written)) == "study.v2"))
  expect_true(all(file.exists(written)))
})

test_that("without writexl an Excel export stops before writing, and says what to do", {
  local_mocked_bindings(writexl_available = function() FALSE)
  result <- list(findings = data.table::data.table(rule_id = "CORE-000001"),
                 skipped = data.table::data.table(rule_id = character(0)))
  path <- tempfile(fileext = ".xlsx")
  expect_error(write_findings(result, path), "install.packages\\(\"writexl\"\\)")
  expect_false(file.exists(path))
})

test_that("the about sheet records where the findings came from", {
  ae <- data.frame(STUDYID = "S", DOMAIN = "AE", USUBJID = "S-1", AESEQ = 1,
                   AETERM = "X", AESTDTC = "2024-13-01")
  result <- filter_findings(check_dataset(ae, standard = "SDTMIG"), triage = "wrong value")
  dir <- tempfile("coreval_about_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  written <- write_findings(result, file.path(dir, "issues.csv"))
  about <- data.table::fread(written[3], colClasses = "character")
  value <- function(item) about$value[about$item == item]
  expect_equal(value("rules"), rules_version())
  expect_equal(value("standard"), "SDTMIG")
  expect_equal(value("is this the whole result?"), "No: it was filtered before it was saved")
  expect_match(value("checked with"), "^coreval ")
  expect_match(value("checked on"), "^[0-9]{4}-[0-9]{2}-[0-9]{2} ")
})

test_that("a stale _truncated.csv is removed when nothing is capped", {
  dir <- tempfile("out_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  result <- check_dataset(data.frame(STUDYID = "S", DOMAIN = "DM", USUBJID = "1"), standard = "SDTMIG")
  stale <- file.path(dir, "x_truncated.csv")
  writeLines("rule_id,domain", stale)
  write_findings(result, file.path(dir, "x.csv"))
  expect_false(file.exists(stale))
})

test_that("an Excel export refuses a value longer than a cell can hold", {
  skip_if_not_installed("writexl")
  result <- check_dataset(data.frame(STUDYID = "S", DOMAIN = "AE", USUBJID = "1", AESEQ = 1,
                                     AETERM = strrep("x", 40000)), standard = "SDTMIG")
  skip_if(!any(nchar(result$findings$Value) > 32767))
  expect_error(write_findings(result, tempfile(fileext = ".xlsx")), "32,767")
})

# A whole made-up study with known mistakes, written to a real workbook and
# read back cell by cell. What a reviewer opens is the file, not the R object,
# so the file is what is checked.
demo_ae_dates <- function() {
  data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = c("S1-1", "S1-2"), AESEQ = c(1, 2),
             AETERM = c("Headache", "Rash"), AESTDTC = c("2024-01-10", "2024-02-30"))
}

demo_study_dir <- function() {
  dir <- tempfile("coreval_xlsx_study_")
  dir.create(dir)
  haven::write_xpt(data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("S1-001", "S1-002", "S1-003"),
    SUBJID = c("001", "002", "003"), RFSTDTC = c("2024-01-15", "2024-13-01", "2024-02-03"),
    AGE = c(34, 51, 47), AGEU = c("YEARS", "YEARS", ""), SEX = c("F", "M", "F"),
    stringsAsFactors = FALSE
  ), file.path(dir, "dm.xpt"))
  haven::write_xpt(data.frame(
    STUDYID = "S1", DOMAIN = "AE", USUBJID = c("S1-001", "S1-002", "S1-002"),
    AESEQ = c(1, 1, 3), AETERM = c("Headache", "Rash & itch", "Nausea"),
    AESTDTC = c("2024-01-20", "2024-02-01", "2024-02-30"),
    stringsAsFactors = FALSE
  ), file.path(dir, "ae.xpt"))
  dir
}

test_that("an Excel export reads as the report does, sheet by sheet", {
  skip_if_not_installed("writexl")
  dir <- demo_study_dir()
  on.exit(unlink(dir, recursive = TRUE))
  result <- check_study(dir, standard = "SDTMIG", version = "3.4")
  path <- file.path(dir, "issues.xlsx")
  write_findings(result, path)
  book <- read_xlsx_text(path)

  expect_equal(names(book), c("Problems", "Records", "Not checked", "Rules"))

  # One row per problem, as many as the report counts, in plain headings.
  s <- book$Problems
  expect_equal(nrow(s), summary(result)$problems)
  expect_equal(names(s), c("Priority", "Dataset", "Problem", "Details", "Records", "Status", "Notes"))
  # Definite errors before anything that may be legitimate.
  expect_false(is.unsorted(match(s$Priority, TRIAGE_LEVELS)))
  # Nothing a person cannot read: no internal names, no code-like lists.
  for (sheet in c("Problems", "Records")) {
    cells <- unlist(book[[sheet]])
    expect_false(any(grepl("[$][a-z_]+|[[]'|variable_value|variable_name", cells)), info = sheet)
  }

  # The missing required variables are named, not left to another sheet.
  req <- s[s$Dataset == "DM" & grepl("CORE-000355", s$Problem, fixed = TRUE), ]
  expect_equal(req$Details, "SITEID, COUNTRY")
  expect_equal(req$Records, "whole dataset")

  # The planted impossible date: one problem, one record, found by subject and
  # sequence number, named as the variable itself.
  date <- s[s$Dataset == "AE" & grepl("CORE-002121", s$Problem, fixed = TRUE), ]
  expect_equal(date$Priority, "wrong value")
  expect_equal(date$Details, "AESTDTC")
  expect_equal(date$Records, "1")
  r <- book$Records
  expect_equal(names(r), c("Dataset", "USUBJID", "SEQ", "Problem", "Values", "Notes"))
  hit <- r[r$Values == "AESTDTC = \"2024-02-30\"", ]
  expect_equal(nrow(hit), 1L)
  expect_equal(c(hit$Dataset, hit$USUBJID, hit$SEQ), c("AE", "S1-002", "3"))
  # The month 13 in DM, which has no --SEQ.
  rf <- r[r$Values == "RFSTDTC = \"2024-13-01\"", ]
  expect_equal(c(rf$USUBJID, rf$SEQ), c("S1-002", ""))
  # A blank shows as blank, not as nothing.
  expect_true("AGE = \"47\"; AGEU = (empty)" %in% r$Values)

  # Every affected record of the result is a row, and no other.
  f <- result$findings
  keyed <- unique(f[!is.na(f$Record) & !rule_rows_are_metadata(f$rule_id), c("Dataset", "rule_id", "Record")])
  expect_equal(nrow(r), nrow(keyed))
  # Each problem's count is the rows it has on Records, in the same order.
  sentence <- sub(" [(]CORE-[0-9]+[)]$", "", s$Problem)
  counted <- grepl("^[0-9]+$", s$Records)
  expect_equal(sum(as.integer(s$Records[counted])), nrow(r))
  expect_equal(unique(paste(r$Dataset, r$Problem)), paste(s$Dataset, sentence)[counted])

  # What could not run: every check counted once, then how it was run.
  nc <- book$`Not checked`
  groups <- nc[seq_len(which(nc[[1]] == "")[1] - 1L), ]
  expect_equal(sum(as.integer(groups$Checks)), nrow(result$skipped))
  expect_false(any(groups$Checks == "0"))
  expect_true("need a define.xml" %in% groups[[1]])
  facts <- setNames(nc$Checks, nc[[1]])
  expect_equal(facts[["Standard"]], "SDTMIG")
  expect_equal(facts[["Checks that ran"]], as.character(attr(result, "checks_run")))
  expect_equal(facts[["Is this the whole result?"]], "Yes")
  expect_match(facts[["Rules"]], "core-contributor", fixed = TRUE)

  # Every rule, with what happened to it.
  rules <- book$Rules
  expect_equal(names(rules), c("Rule", "What it checks", "Result", "Datasets", "Why not run"))
  ran <- attr(result, "ran")
  expect_equal(nrow(ran), attr(result, "checks_run"))
  expect_setequal(rules$Rule, c(ran$rule_id, result$skipped$rule_id))
  expect_false(anyDuplicated(rules$Rule) > 0)
  result_of <- setNames(rules$Result, rules$Rule)
  expect_setequal(rules$Rule[rules$Result == "problems found"], unique(f$rule_id))
  # Ran and found nothing, as the planted data leaves AGE alone.
  clean <- setdiff(ran$rule_id, f$rule_id)
  expect_true(all(result_of[clean] == "no problems"))
  # Could not run anywhere: says why.
  never <- setdiff(result$skipped$rule_id, c(ran$rule_id, f$rule_id))
  expect_gt(length(never), 0)
  expect_true(all(result_of[never] == "could not run"))
  expect_true(all(nzchar(rules$`Why not run`[rules$Rule %in% never])))
  expect_false(any(startsWith(rules$`Why not run`, "evaluation failed")))
  expect_false(any(rules$`What it checks` == "(no description available)"))

  # The CSV keeps the raw tables, and writes the same problems.
  written <- write_findings(result, file.path(dir, "issues.csv"))
  raw <- data.table::fread(written[1], colClasses = "character")
  expect_equal(nrow(raw), nrow(result$findings))
  csv <- data.table::fread(written[basename(written) == "issues_summary.csv"], colClasses = "character")
  expect_equal(paste0(csv$issue, " (", csv$rule_id, ")"), s$Problem)
})

test_that("a filtered file does not say a rule found nothing", {
  # The rule found something; the filter took it out. Reading "no problems"
  # would turn a filter into a clean bill of health.
  skip_if_not_installed("writexl")
  result <- filter_findings(check_dataset(demo_ae_dates(), standard = "SDTMIG"), triage = "missing required")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path))
  write_findings(result, path)
  book <- read_xlsx_text(path)
  rules <- setNames(book$Rules$Result, book$Rules$Rule)
  expect_equal(rules[["CORE-002121"]], "ran, filtered out of this file")
  expect_false("no problems" %in% rules)
  facts <- setNames(book$`Not checked`$Checks, book$`Not checked`[[1]])
  expect_match(facts[["Is this the whole result?"]], "^No")
})

test_that("a record with no subject is found by its row", {
  skip_if_not_installed("writexl")
  f <- data.table::data.table(
    Dataset = "TS", Record = 7L, USUBJID = NA_character_, SEQ = NA_real_,
    Variable = "TSVAL", Value = "26 weeks", issue = "x", triage = "wrong value", rule_id = "CORE-000001"
  )
  expect_equal(record_rows(f, problem_summary(f))$values, "row 7: TSVAL = \"26 weeks\"")
})

test_that("a rule over variable metadata names the variables, on Problems alone", {
  f <- data.table::data.table(
    Dataset = "AE", Record = c(1L, 1L, 2L, 2L), USUBJID = NA_character_, SEQ = NA_real_,
    Variable = rep(c("variable_name", "variable_label"), 2),
    Value = c("AETERM", "Term", "AESEQ", "Seq"), issue = "x", triage = "wrong value",
    rule_id = "CORE-000398"
  )
  expect_true(rule_rows_are_metadata("CORE-000398"))
  p <- problem_summary(f)
  expect_equal(p$details, "AETERM, AESEQ")
  expect_equal(p$affects, "2 variables")
  expect_equal(nrow(record_rows(f, p)), 0L)
})

test_that("a SEND result's workbook uses SEND's rule set", {
  skip_if_not_installed("writexl")
  result <- check_dataset(demo_ae_dates(), standard = "SENDIG")
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path))
  before <- .coreval_env$rule_family
  write_findings(result, path)
  expect_identical(.coreval_env$rule_family, before)
  rules <- read_xlsx_text(path)$Rules
  expect_gt(nrow(rules), 0)
  expect_false(any(rules$`What it checks` == "(no description available)"))
})

test_that("an Excel export gives the true count of a capped problem", {
  skip_if_not_installed("writexl")
  dm <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = paste0("S1-", 1:5),
                   SUBJID = as.character(1:5), RFSTDTC = "2024-13-01", AGE = 30, AGEU = "YEARS")
  result <- check_dataset(dm, standard = "SDTMIG", max_records = 1)
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path))
  write_findings(result, path)
  book <- read_xlsx_text(path)
  date <- book$Problems[grepl("CORE-002121", book$Problems$Problem, fixed = TRUE), ]
  expect_equal(date$Records, "5 (first 1 listed)")
  expect_equal(sum(grepl("RFSTDTC", book$Records$Values, fixed = TRUE)), 1L)
})

test_that("the summary sheet gives a capped problem's true record count", {
  dm <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = paste0("S1-", 1:5),
                   SUBJID = as.character(1:5), RFSTDTC = "2024-13-01", AGE = 30, AGEU = "YEARS")
  result <- check_dataset(dm, standard = "SDTMIG", max_records = 1)
  s <- problem_summary(result$findings, result$truncated)
  date <- s[s$rule_id == "CORE-002121", ]
  expect_equal(date$records, 5L)
  expect_equal(nrow(result$findings[result$findings$rule_id == "CORE-002121", ]), 1L)
})

test_that("an empty result gives an empty summary, not an error", {
  f <- data.table::data.table(Dataset = character(0), Record = integer(0), Variable = character(0),
                              Value = character(0), issue = character(0), triage = character(0),
                              rule_id = character(0))
  expect_equal(nrow(problem_summary(f)), 0L)
})

test_that("a saved file says what was used and whether it is complete", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("xml2")
  n <- 30
  big <- data.frame(STUDYID = "S", DOMAIN = "LB", USUBJID = sprintf("S-%03d", seq_len(n)),
                    LBSEQ = seq_len(n), LBTESTCD = "ALT", LBDTC = "2024-01-10")
  r <- check_dataset(big, standard = "SDTMIG", version = "3.4", max_records = 10)
  expect_gt(nrow(r$truncated), 0)
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  write_findings(r, path)
  sheet <- read_xlsx_text(path)[["Not checked"]]
  facts <- stats::setNames(sheet[[2]], tolower(sheet[[1]]))
  expect_equal(facts[["version"]], "3.4")
  expect_equal(facts[["terminology"]], "none named")
  expect_match(facts[["is this the whole result?"]], "^No")
  expect_equal(as.integer(facts[["problems with more records than listed"]]), nrow(r$truncated))
})

test_that("a problem about several variables names them", {
  sub <- data.frame(Record = c(1L, 1L, 2L, 2L),
                    Variable = c("variable_name", "$max", "variable_name", "$max"),
                    Value = c("AETERM", "46", "AEDECOD", "20"), stringsAsFactors = FALSE)
  expect_equal(problem_details(sub), "AETERM, AEDECOD")
})

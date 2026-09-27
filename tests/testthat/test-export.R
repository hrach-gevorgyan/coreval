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
  expect_length(written, 3)
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
    findings = data.table::data.table(rule_id = "CORE-000001"),
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
    for (sheet in c("findings", "skipped", "about")) {
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
    "DM"
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
  expect_equal(basename(written), c("issues", "issues_skipped", "issues_about"))
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
  expect_equal(value("rules version"), rules_version())
  expect_equal(value("scoped to standard"), "SDTMIG")
  expect_equal(value("is this a subset of the full result?"), "YES - filtered before export")
  expect_match(value("generated by"), "^coreval ")
})

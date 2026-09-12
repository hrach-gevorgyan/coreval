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

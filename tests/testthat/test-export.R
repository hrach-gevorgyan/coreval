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

  expect_length(written, 2)
  expect_true(all(file.exists(written)))
  # skipped lands in a sibling file, with the suffix before the extension
  expect_equal(basename(written[2]), "issues_skipped.csv")

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

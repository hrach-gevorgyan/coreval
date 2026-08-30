test_that("read_study reads a CORE test-case data/ directory", {
  study <- read_study(test_path("fixtures", "test_case", "data"))

  expect_equal(names(study), c("datasets", "define", "ct", "standard"))
  expect_equal(names(study$datasets), "DM")

  dm <- study$datasets$DM
  expect_equal(nrow(dm$data), 3)
  expect_equal(dm$data$SEX, c("M", "", "F"))
  expect_equal(dm$data$AGE, c(45, NA, 7))
  expect_true(is.character(dm$data$SEX))
  expect_true(is.numeric(dm$data$AGE))

  expect_equal(dm$meta[variable == "AGE", type], "Num")
  expect_equal(dm$meta[variable == "SEX", type], "Char")
})

test_that("read_study preserves a literal character value of 'NA', not just true blanks", {
  # Bug: fread()'s default na.strings = "NA" silently turned a genuine
  # CDISC null-flavor value like TSVALNF = "NA" (real, meaningful text -
  # "Not Applicable") into R's NA, which then got rewritten to "" by the
  # blank-fill loop - indistinguishable from an actually blank field.
  dir <- tempfile("coreval_na_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("Filename,Label\nts,Trial Summary", file.path(dir, "_datasets.csv"))
  writeLines(
    "dataset,variable,label,type,length\nTS,TSVALNF,Null Flavor,Char,10\nTS,TSVAL,Value,Char,10",
    file.path(dir, "_variables.csv")
  )
  writeLines("TSVALNF,TSVAL\nNA,\n,some value", file.path(dir, "ts.csv"))

  study <- read_study(dir)
  ts <- study$datasets$TS
  expect_equal(ts$data$TSVALNF, c("NA", ""))
  expect_equal(ts$data$TSVAL, c("", "some value"))
})

test_that("read_study preserves leading/trailing whitespace in character values", {
  # Bug: fread()'s default strip.white = TRUE silently trimmed leading/
  # trailing whitespace from unquoted character fields - destroying exactly
  # the kind of data-quality defect CORE conformance rules exist to catch
  # (e.g. CORE-000867's "text variable must not have leading spaces").
  dir <- tempfile("coreval_ws_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("Filename,Label\ncm,Concomitant Medications", file.path(dir, "_datasets.csv"))
  writeLines("dataset,variable,label,type,length\nCM,CMTRT,Reported Name,Char,10", file.path(dir, "_variables.csv"))
  writeLines("CMTRT\n HYTRIN ", file.path(dir, "cm.csv"))

  study <- read_study(dir)
  expect_equal(study$datasets$CM$data$CMTRT, " HYTRIN ")
})

test_that("read_study captures a CORE test case's declared standard from .env", {
  dir <- tempfile("coreval_env_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("Filename,Label\ndm,Demographics", file.path(dir, "_datasets.csv"))
  writeLines("dataset,variable,label,type,length\nDM,USUBJID,Subject,Char,20", file.path(dir, "_variables.csv"))
  writeLines("USUBJID\n1", file.path(dir, "dm.csv"))
  writeLines("PRODUCT=SDTMIG\nVERSION=3-4", file.path(dir, ".env"))
  study <- read_study(dir)
  expect_equal(study$standard, list(product = "SDTMIG", version = "3-4"))
})

test_that("read_study's standard is NA/NA when .env is absent (a real XPT study, or a test case without one)", {
  dir <- tempfile("coreval_noenv_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("Filename,Label\ndm,Demographics", file.path(dir, "_datasets.csv"))
  writeLines("dataset,variable,label,type,length\nDM,USUBJID,Subject,Char,20", file.path(dir, "_variables.csv"))
  writeLines("USUBJID\n1", file.path(dir, "dm.csv"))
  study <- read_study(dir)
  expect_true(is.na(study$standard$product))
  expect_true(is.na(study$standard$version))
})

test_that("read_study infers the dataset list from _variables.csv when _datasets.csv is absent", {
  # A handful of real CORE test cases (e.g. CORE-000395's SENDIG fixtures)
  # ship _variables.csv and the per-dataset CSVs but no _datasets.csv
  # manifest at all.
  dir <- tempfile("coreval_nomanifest_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("dataset,variable,label,type,length\nTS,STUDYID,Study Identifier,Char,10", file.path(dir, "_variables.csv"))
  writeLines("STUDYID\nABC", file.path(dir, "ts.csv"))
  study <- read_study(dir)
  expect_equal(names(study$datasets), "TS")
  expect_equal(study$datasets$TS$data$STUDYID, "ABC")
  expect_true(is.na(study$datasets$TS$label))
})

test_that("evaluate_rule matches CDISC's reference results.csv for a fixture with no _datasets.csv (CORE-000395)", {
  rule <- .coreval_env$data$rules[["CORE-000395"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000395", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- which(evaluate_rule(rule, study, "TS"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    expected <- sort(unique(as.integer(results$Record[results$Dataset == "TS"])))
    expect_equal(sort(unname(actual)), expected)
  }
})

test_that("read_study doesn't crash the whole study when one dataset has zero _variables.csv rows", {
  # A dataset can be listed in _datasets.csv with zero matching rows in
  # _variables.csv at all (a real upstream data gap, confirmed for
  # CORE-000094's own "ec" dataset) - fread() errors on an empty-but-typed
  # colClasses list, which used to crash the ENTIRE study read.
  dir <- tempfile("coreval_notypes_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("Filename,Label\ndm,Demographics\nec,Exposure as Collected", file.path(dir, "_datasets.csv"))
  writeLines("dataset,variable,label,type,length\nDM,USUBJID,Subject,Char,20", file.path(dir, "_variables.csv"))
  writeLines("USUBJID\n1", file.path(dir, "dm.csv"))
  writeLines("USUBJID,ECTRT\n1,DRUGX", file.path(dir, "ec.csv")) # no _variables.csv rows for EC at all
  study <- read_study(dir)
  expect_equal(sort(names(study$datasets)), c("DM", "EC"))
  expect_equal(study$datasets$EC$data$ECTRT, "DRUGX") # auto-detected type, still readable
  expect_equal(nrow(study$datasets$EC$meta), 0)
})

test_that("evaluate_rule matches CDISC's reference results.csv for a fixture with an untyped dataset (CORE-000094)", {
  rule <- .coreval_env$data$rules[["CORE-000094"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000094", case, "01")
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- which(evaluate_rule(rule, study, domain))
      expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
      expect_equal(sort(unname(actual)), expected)
    }
  }
})

test_that("read_study reads a directory of XPT files with the same semantics", {
  dir <- tempfile("coreval_xpt_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  df <- data.frame(
    STUDYID = "STUDY01",
    DOMAIN = "DM",
    USUBJID = c("STUDY01-001", "STUDY01-002", "STUDY01-003"),
    SEX = c("M", NA, "F"),
    AGE = c(45, NA, 7),
    stringsAsFactors = FALSE
  )
  haven::write_xpt(df, file.path(dir, "dm.xpt"))

  study <- read_study(dir)

  expect_equal(names(study$datasets), "DM")
  dm <- study$datasets$DM
  expect_equal(nrow(dm$data), 3)
  # XPT has no character NA - both "" and NA round-trip to "".
  expect_equal(dm$data$SEX, c("M", "", "F"))
  expect_equal(dm$data$AGE, c(45, NA, 7))
  expect_equal(dm$meta[variable == "AGE", type], "Num")
  expect_equal(dm$meta[variable == "SEX", type], "Char")
})

test_that("read_env_standard tolerates an empty value, a blank line and a comment", {
  # A blank value ("VERSION=") is legitimate and common. strsplit() drops the
  # trailing empty piece, so such a line yields a length-1 vector - and
  # returning NULL for it made vapply reject a zero-length result and abort
  # the ENTIRE study read over one blank field. Any real study whose .env
  # left a value empty would fail to load at all.
  dir <- tempfile("coreval_env_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))

  writeLines(c("PRODUCT=ADAMIG", "VERSION="), file.path(dir, ".env"))
  std <- read_env_standard(dir)
  expect_equal(std$product, "ADAMIG")
  expect_true(is.na(std$version))

  # Blank lines and comments carry no "=" at all and must be ignored rather
  # than parsed as a malformed assignment.
  writeLines(
    c("# study standard", "", "PRODUCT=sdtmig", "VERSION=3-4", ""),
    file.path(dir, ".env")
  )
  std2 <- read_env_standard(dir)
  expect_equal(std2$product, "SDTMIG")
  expect_equal(std2$version, "3-4")

  # A file with nothing assignable is "no declared standard", not an error.
  writeLines(c("# nothing here", ""), file.path(dir, ".env"))
  std3 <- read_env_standard(dir)
  expect_true(is.na(std3$product))
  expect_true(is.na(std3$version))
})

test_that("read_study reads a CORE test-case data/ directory", {
  study <- read_study(test_path("fixtures", "test_case", "data"))

  expect_equal(names(study), c("datasets", "define", "ct"))
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

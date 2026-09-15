# Broken and odd input must be refused with a message that names the problem,
# never checked in part or reported as clean.

small_dm <- function() {
  data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = sprintf("S1-%03d", 1:40),
    RFSTDTC = "2020-01-02T10:00", AGE = 30, stringsAsFactors = FALSE
  )
}

temp_folder <- function(prefix) {
  dir <- tempfile(prefix)
  dir.create(dir)
  dir
}

test_that("a transport file cut off part-way is refused, not checked in part", {
  dir <- temp_folder("coreval_cut_")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  whole <- file.path(dir, "whole.xpt")
  haven::write_xpt(small_dm(), whole, name = "DM")
  bytes <- readBin(whole, "raw", file.size(whole))
  expect_equal(length(bytes) %% 80, 0)

  study <- temp_folder("coreval_cut_study_")
  on.exit(unlink(study, recursive = TRUE), add = TRUE)
  writeBin(bytes[seq_len(length(bytes) - 100)], file.path(study, "dm.xpt"))
  expect_error(check_study(study), "'dm.xpt' is damaged")
  expect_error(check_dataset(file.path(study, "dm.xpt")), "'dm.xpt' is damaged")
})

test_that("empty and unreadable files are named in the error", {
  dir <- temp_folder("coreval_bad_files_")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file.create(file.path(dir, "dm.xpt"))
  expect_error(check_study(dir), "'dm.xpt' is empty")

  utils::write.csv(small_dm(), file.path(dir, "dm.xpt"), row.names = FALSE)
  expect_error(check_study(dir), "'dm.xpt' is not a SAS transport file")

  good <- tempfile("coreval_good_", fileext = ".xpt")
  on.exit(unlink(good), add = TRUE)
  haven::write_xpt(small_dm(), good, name = "DM")
  bytes <- readBin(good, "raw", file.size(good))
  bytes[801:880] <- as.raw(0L)
  writeBin(bytes, file.path(dir, "dm.xpt"))
  expect_error(check_study(dir), "could not read 'dm.xpt'")

  file.create(file.path(dir, "ae.csv"))
  expect_error(check_dataset(file.path(dir, "ae.csv")), "'ae.csv' is empty")
})

test_that("a folder with no readable datasets says what it does hold", {
  dir <- temp_folder("coreval_csv_folder_")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  utils::write.csv(small_dm(), file.path(dir, "dm.csv"), row.names = FALSE)
  expect_error(check_study(dir), "check_dataset")

  sub <- file.path(dir, "sdtm")
  dir.create(sub)
  haven::write_xpt(small_dm(), file.path(sub, "dm.xpt"), name = "DM")
  expect_error(check_study(dir), "found in a subfolder")
})

test_that("a CSV row with the wrong number of values stops the check", {
  path <- tempfile("coreval_ragged_", fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c("STUDYID,DOMAIN,USUBJID", "S1,DM,S1-1", "S1,DM", "S1,DM,S1-3"), path)
  expect_error(check_dataset(path), "could not read all of")
})

test_that("a CSV gives the same findings as the data frame it was written from", {
  # The shape of the pilot DM that exposed both faults: ISO dates, which fread
  # would turn into R dates, some left blank, and a numeric study day that is
  # missing throughout, which write.csv() writes as the text NA.
  dm <- small_dm()
  dm$RFSTDTC <- rep(c("2020-01-02", ""), 20)
  dm$DMDTC <- "2019-12-20"
  dm$DMDY <- NA_real_
  path <- tempfile("coreval_dm_", fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  utils::write.csv(dm, path, row.names = FALSE)

  from_csv <- check_dataset(path, domain = "DM")
  from_df <- check_dataset(dm)
  key <- function(r) sort(paste(r$findings$rule_id, r$findings$Record, r$findings$Value))
  expect_identical(key(from_csv), key(from_df))
})

test_that("a CSV in the Windows encoding is repaired like any other input", {
  path <- tempfile("coreval_cp1252_", fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw("STUDYID,DOMAIN,USUBJID,ARM\nS1,DM,S1-1,Caf\xe9\n"), path)
  expect_no_warning(result <- check_dataset(path))
  expect_s3_class(result, "coreval_result")
})

test_that("two columns with one name are refused", {
  dm <- small_dm()
  names(dm)[names(dm) == "AGE"] <- "RFSTDTC"
  expect_error(check_dataset(dm), "more than one column is named 'RFSTDTC'")
})

test_that("arguments that would quietly change which rules run are refused", {
  dm <- small_dm()
  expect_error(check_dataset(dm, use_case = "IND"), "not a use case")
  expect_error(check_dataset(dm, include_deprecated = "yes"), "TRUE or FALSE")
  expect_error(check_study(42), "must be a folder path")

  lower <- check_dataset(dm, use_case = "indh")
  upper <- check_dataset(dm, use_case = "INDH")
  expect_identical(attr(lower, "checks_run"), attr(upper, "checks_run"))

  every <- list_rules()
  indh <- list_rules(use_case = "INDH")
  expect_lt(nrow(indh), nrow(every))
})

test_that("write_findings() explains a missing folder or a folder path", {
  result <- check_dataset(small_dm())
  dir <- temp_folder("coreval_write_")
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(write_findings(result, dir), "is a folder")
  expect_error(write_findings(result, file.path(dir, "no", "out.csv")), "does not exist")
})

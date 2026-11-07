# Each of these ran green through evaluate_rule() and went wrong only in a
# whole-study check, or only on real files, so each is checked that way.

study_dir <- function(datasets) {
  dir <- tempfile("coreval_study_")
  dir.create(dir)
  for (name in names(datasets)) {
    haven::write_xpt(as.data.frame(datasets[[name]]), file.path(dir, paste0(tolower(name), ".xpt")),
                     name = name)
  }
  dir
}

found <- function(result, id) result$findings[result$findings$rule_id == id, ]

dm_rows <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = "S1-1", SUBJID = "1",
                      stringsAsFactors = FALSE)
ae_rows <- data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = "S1-1", AESEQ = 1, AETERM = "X",
                      stringsAsFactors = FALSE)

test_that("a presence rule is asked of every dataset, not the first alone (CORE-000297)", {
  # MIDS is in SM and there is no TM. AE sorts first and has no MIDS.
  sm <- data.frame(STUDYID = "S1", DOMAIN = "SM", USUBJID = "S1-1", SMSEQ = 1, MIDS = "A1",
                   MIDSTYPE = "T", stringsAsFactors = FALSE)
  dir <- study_dir(list(AE = ae_rows, DM = dm_rows, SM = sm))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  expect_gt(nrow(found(result, "CORE-000297")), 0)
})

test_that("a QNAM that is a variable of its parent is reported in a study check (CORE-000783)", {
  supp <- data.frame(STUDYID = "S1", RDOMAIN = "AE", USUBJID = "S1-1", IDVAR = "AESEQ", IDVARVAL = "1",
                     QNAM = "AESEV", QLABEL = "Severity", QVAL = "MILD", QORIG = "CRF",
                     stringsAsFactors = FALSE)
  dir <- study_dir(list(AE = ae_rows, DM = dm_rows, SUPPAE = supp))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  expect_true("SUPPAE" %in% found(result, "CORE-000783")$Dataset)
})

test_that("a SUPP dataset is not judged by DM's columns (CORE-000354, CORE-000529, CORE-000853)", {
  # The SUPP merge brings DM's columns in; "--DY" read from DOMAIN = DM became
  # DMDY. CORE 1.0 expands "--" from the file name, so SUPPAE has no such column.
  dm <- dm_rows
  dm$DMDTC <- "2014-02"
  dm$DMDY <- 999
  supp <- data.frame(STUDYID = "S1", RDOMAIN = "AE", USUBJID = "S1-1", IDVAR = "AESEQ", IDVARVAL = "1",
                     QNAM = "AEXX", QLABEL = "x", QVAL = "1", QORIG = "CRF", stringsAsFactors = FALSE)
  dir <- study_dir(list(AE = ae_rows, DM = dm, SUPPAE = supp))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  hits <- result$findings[result$findings$rule_id %in% c("CORE-000354", "CORE-000529", "CORE-000853"), ]
  expect_false(any(startsWith(hits$Dataset, "SUPP")))
})

test_that("a variable no SUPP dataset may hold is reported there (CORE-000550)", {
  supp <- data.frame(STUDYID = "S1", RDOMAIN = "AE", USUBJID = "S1-1", IDVAR = "AESEQ", IDVARVAL = "1",
                     QNAM = "AEXX", QLABEL = "x", QVAL = "1", QORIG = "CRF", XBOGUS = "z",
                     stringsAsFactors = FALSE)
  dir <- study_dir(list(AE = ae_rows, DM = dm_rows, SUPPAE = supp))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  hits <- found(result, "CORE-000550")
  expect_true(any(hits$Dataset == "SUPPAE" & hits$Value == "XBOGUS"))
})

test_that("a custom domain in the right order is not reported as out of order (CORE-000852)", {
  xz <- data.frame(STUDYID = "S1", DOMAIN = "XZ", USUBJID = "S1-1", XZSEQ = 1, XZTERM = "X",
                   stringsAsFactors = FALSE)
  dir <- study_dir(list(DM = dm_rows, XZ = xz))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  expect_false("XZ" %in% found(result, "CORE-000852")$Dataset)
})

test_that("a subject is reported whatever the other subjects hold (CORE-000370)", {
  dm <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = c("S1-1", "S1-2"), SUBJID = c("1", "2"),
                   RFICDTC = "2020-01-01", stringsAsFactors = FALSE)
  ds <- data.frame(STUDYID = "S1", DOMAIN = "DS", USUBJID = c("S1-1", "S1-2"), DSSEQ = 1,
                   DSTERM = "INFORMED CONSENT OBTAINED", DSDECOD = "OTHER", DSCAT = "X", DSSTDTC = "",
                   stringsAsFactors = FALSE)
  subjects <- function(ds) {
    dir <- study_dir(list(DM = dm, DS = ds))
    on.exit(unlink(dir, recursive = TRUE))
    result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.2"))
    unique(found(result, "CORE-000370")$USUBJID)
  }
  alone <- subjects(ds)
  ds$DSDECOD[2] <- "INFORMED CONSENT OBTAINED"
  ds$DSSTDTC[2] <- "2020-01-01"
  expect_true("S1-1" %in% alone)
  expect_identical(subjects(ds), "S1-1")
})

test_that("terminology of another family is refused, not left unchecked", {
  expect_error(check_dataset(dm_rows, domain = "DM", standard = "SDTMIG", version = "3.4",
                             ct_package = "sendct-2026-03-27"), "is sendct terminology")
  expect_error(check_dataset(dm_rows, domain = "DM", standard = "SDTMIG", version = "3.4",
                             ct_package = "adamct-2014-09-26"), "sdtmct")
  expect_identical(list_ct_packages("sdtmct"), list_ct_packages("sdtm"))
  expect_error(list_ct_packages("nope"), "no terminology family")
})

test_that("a define.xml that cannot be read is not reported as missing", {
  skip_if_not_installed("xml2")
  dir <- study_dir(list(AE = ae_rows, DM = dm_rows))
  on.exit(unlink(dir, recursive = TRUE))
  writeLines("<ODM><broken", file.path(dir, "define.xml"))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  expect_false("CORE-002084" %in% result$findings$rule_id)
  reasons <- result$skipped$reason[grepl("define", result$skipped$reason)]
  expect_true(length(reasons) > 0)
  expect_true(all(grepl("could not be read", reasons)))
})

test_that("only a result can be written up as one", {
  path <- tempfile(fileext = ".csv")
  expect_error(write_findings(list(findings = 1), path), "not a coreval result")
  expect_error(write_findings(list(findings = data.frame(a = 1), skipped = data.frame()), path),
               "not a coreval result")
})

test_that("an empty or broken dataset file stops the read, a non-dataset JSON does not", {
  skip_if_not_installed("jsonlite")
  dir <- study_dir(list(DM = dm_rows))
  on.exit(unlink(dir, recursive = TRUE))
  file.create(file.path(dir, "ae.json"))
  expect_error(read_study(dir))
  writeLines("<html>502 Bad Gateway</html>", file.path(dir, "ae.json"))
  expect_error(read_study(dir))
  unlink(file.path(dir, "ae.json"))
  writeLines('{"package":"submission"}', file.path(dir, "manifest.json"))
  expect_warning(read_study(dir), "not a dataset, so left out: manifest.json")
})

test_that("forbidden and required presence findings are labelled for what they are", {
  sub <- data.frame(Variable = "dataset_name", Value = "TT", issue = "TT dataset must not be present",
                    stringsAsFactors = FALSE)
  expect_equal(finding_triage(sub, list(rule_type = "Domain Presence Check", outcome = list(
    Message = "TT dataset must not be present."))), "wrong value")
  expect_equal(finding_triage(sub, list(rule_type = "Domain Presence Check", outcome = list(
    Message = "PP dataset is present in study, but PC dataset is not present in study."))), "missing required")
  timing <- data.frame(Variable = "$timing", Value = "", issue = "", stringsAsFactors = FALSE)
  expect_equal(finding_triage(timing, list(rule_type = "Variable Metadata Check", outcome = list(
    Message = "At least one timing variable must be present in the dataset."))), "missing required")
})

test_that("an all-missing column of a data frame is no text column (CORE-000362)", {
  ae <- data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = c("S1-1", "S1-2"), AESEQ = 1:2,
                   AETERM = "X", AESOCCD = c(100, 200), AEBDSYCD = NA)
  result <- check_dataset(ae, domain = "AE", standard = "SDTMIG", version = "3.4")
  expect_false("CORE-000362" %in% result$skipped$rule_id)
})

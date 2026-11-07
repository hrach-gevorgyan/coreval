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

with_core1 <- function(code) {
  old <- .coreval_env$engine
  on.exit(.coreval_env$engine <- old)
  .coreval_env$engine <- "core1"
  force(code)
}

test_that("trailing tabs and line breaks are dropped from transport text", {
  path <- tempfile(fileext = ".xpt")
  on.exit(unlink(path))
  haven::write_xpt(data.frame(LBDTC = c("2018-02-20T06:00:00\t", "x\r\n", "ok ")), path,
                   version = 5, name = "LB")
  expect_equal(read_sas_file(path)$LBDTC, c("2018-02-20T06:00:00", "x", "ok"))
})

test_that("1.0's latest and earliest dates compare as ISO text (CORE-000238, CORE-000239)", {
  with_core1({
    expect_equal(pick_date(c("2014-02", "2014-02-01"), TRUE), "2014-02-01")
    expect_equal(pick_date(c("2014-02", "2014-02-01"), FALSE), "2014-02")
    expect_equal(pick_date(c("2011-01-14 00:00:00", "2010-01-01"), TRUE), "2011-01-14T00:00:00")
    expect_equal(pick_date(c("2012-12-32", "garbage", "2014---15"), TRUE), "2014")
  })
})

test_that("1.0's study day stops where its SQL does (CORE-000529)", {
  with_core1({
    dt <- data.table::data.table(RFSTDTC = c("2014-01-01", "2014-01-02"))
    expect_equal(core1_dy_reference(dt, c("2014-01-05", NA)), c("2014-01-01", "2014-01-02"))
    expect_error(core1_dy_reference(dt, c("2014-02-30", NA)), "not a real date")
    expect_error(core1_dy_reference(dt, c("2014-13-01", NA)), "not a real date")
    expect_error(core1_dy_reference(data.table::data.table(A = 1), "2014-01-01"), "RFSTDTC")
  })
})

test_that("a 1.0 SUPP merge keeps every qualifier of a record and no identifier", {
  with_core1({
    ae <- list(data = data.table::data.table(STUDYID = "S", DOMAIN = "AE", USUBJID = "1", AESEQ = 1),
               meta = NULL)
    supp <- list(data = data.table::data.table(
      STUDYID = "S", RDOMAIN = "AE", USUBJID = "1", IDVAR = "aeseq", IDVARVAL = "1",
      QNAM = c("X", "Y"), QVAL = c("x", "y"), SPDEVID = c("D1", "D2"), POOLID = "P"), meta = NULL)
    merged <- apply_supp_match(ae, supp)$data
    expect_equal(c(merged$X, merged$Y), c("x", "y"))
    expect_false(any(c("SPDEVID", "POOLID") %in% names(merged)))
    supp$data$RDOMAIN <- NULL
    expect_error(apply_supp_match(ae, supp), "RDOMAIN")
  })
})

test_that("a 1.0 rule takes the domain from the file name, not DOMAIN", {
  with_core1({
    ae <- list(data = data.table::data.table(DOMAIN = "XX", AESEQ = 1), meta = NULL)
    expect_equal(dataset_unsplit_name(ae, "AE"), "AE")
    expect_equal(dataset_unsplit_name(ae, "LB1"), "LB")
  })
})

test_that("a transport file with every label blank is checked for labels (CORE-000398)", {
  dm <- dm_rows
  dir <- study_dir(list(DM = dm))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  expect_false(any(grepl("has none at all", result$skipped$reason)))
  frame <- check_dataset(dm, domain = "DM", standard = "SDTMIG", version = "3.4")
  expect_true(any(grepl("has none at all", frame$skipped$reason)))
})

test_that("Findings About may hold the Findings class variables (CORE-000550)", {
  fa <- data.table::data.table(STUDYID = "S", DOMAIN = "FA", USUBJID = "1", FASEQ = 1, FATESTCD = "A",
                               FATEST = "A", FAOBJ = "X", FAORRES = "1")
  study <- list(datasets = list(FA = list(data = fa, meta = NULL)))
  op <- list(domain = "FA", id = "$allowed", operator = "get_model_column_order")
  allowed <- compute_operation(op, study, "FA", study$datasets$FA)$value
  expect_true(all(c("FATESTCD", "FAORRES", "FAOBJ") %in% allowed))
})

test_that("a hand-built study list is refused with a message", {
  expect_error(check_study(list(datasets = list(DM = dm_rows)), standard = "SDTMIG"),
               "named list of datasets")
  expect_error(write_findings(structure(list(findings = data.frame(rule_id = character()),
                                             skipped = data.frame()), class = "coreval_result"),
                              tempfile(fileext = ".csv"), tracking = NA), "TRUE or FALSE")
})

test_that("a 1.0 split is read from the file name, not DOMAIN", {
  ae <- list(data = data.table::data.table(DOMAIN = "CE"), meta = NULL)
  expect_false(dataset_is_split(ae, "AE", core1 = TRUE))
  expect_true(dataset_is_split(ae, "LB1", core1 = TRUE))
  expect_false(dataset_is_split(ae, "POOLDEF", core1 = TRUE))
  expect_false(dataset_is_split(ae, "SUPPAE", core1 = TRUE))
})

test_that("a 1.0 Exclude matches the file's own domain, not its DOMAIN column (CORE-000701)", {
  apmh <- list(data = data.table::data.table(DOMAIN = "MH"), meta = NULL)
  expect_true(domains_match(list(Exclude = list("MH")), "APMH", apmh, core1 = TRUE))
  expect_false(domains_match(list(Exclude = list("MH")), "APMH", apmh, core1 = FALSE))
})

test_that("a 1.0 SUPP qualifier name has no case", {
  with_core1({
    ae <- list(data = data.table::data.table(STUDYID = "S", DOMAIN = "AE", USUBJID = "1", AESEQ = 1),
               meta = NULL)
    supp <- list(data = data.table::data.table(STUDYID = "S", RDOMAIN = "AE", USUBJID = "1", IDVAR = "AESEQ",
                                               IDVARVAL = "1", QNAM = "aetrtem", QVAL = "Y"), meta = NULL)
    expect_equal(apply_supp_match(ae, supp)$data$AETRTEM, "Y")
  })
})

test_that("a TS row with no terminology version is read with the study's own (CORE-001080)", {
  ts <- data.frame(STUDYID = "S1", DOMAIN = "TS", TSSEQ = 1:2, TSPARMCD = c("SEXPOP", "SEXPOP"),
                   TSPARM = "Sex of Participants", TSVAL = c("BOTH", "BOTH"),
                   TSVALCD = c("C49636", "C00001"), TSVCDREF = "CDISC", TSVCDVER = "",
                   stringsAsFactors = FALSE)
  dir <- study_dir(list(DM = dm_rows, TS = ts))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4",
                                         ct_package = "sdtmct-2024-03-29"))
  hits <- found(result, "CORE-001080")
  expect_true(2L %in% hits$Record)
  expect_false(1L %in% hits$Record)
})

test_that("a 1.0 custom domain with a class is judged against the Model (CORE-001082)", {
  xz <- data.frame(STUDYID = "S1", DOMAIN = "XZ", USUBJID = "S1-1", XZSEQ = "one", XZTERM = "X",
                   stringsAsFactors = FALSE)
  dir <- study_dir(list(DM = dm_rows, XZ = xz))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4"))
  hits <- found(result, "CORE-001082")
  expect_true(any(hits$Dataset == "XZ"))
})

test_that("a 1.0 rule reads the SDTM Model its guide links to (CORE-000550)", {
  with_core1({
    events <- function() {
      mv <- .coreval_env$model_variables
      mv$variable[mv$class == "Events"]
    }
    default <- events()
    restore <- use_sdtm_model(list(standard = list(product = "SDTMIG", version = "3.2")))
    expect_false("--RLPRC" %in% events())
    expect_false("SPTOBID" %in% events())
    restore()
    expect_identical(events(), default)
    restore <- use_sdtm_model(list(standard = list(product = "SDTMIG", version = "3-4")))
    expect_true("--RLPRC" %in% events())
    restore()
  })
  # CDISC's rules keep the bundled default.
  restore <- use_sdtm_model(list(standard = list(product = "SDTMIG", version = "3.2")))
  expect_true("SPTOBID" %in% .coreval_env$model_variables$variable)
  restore()
})

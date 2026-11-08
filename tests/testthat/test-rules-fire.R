# Rules whose CDISC test cases all expect no findings, shown here to fire.
# Each study was also run through CDISC's engine, which reported the same
# records. Records count from 1, as the engine's do.

study_dir <- function(datasets) {
  dir <- tempfile("coreval_study_")
  dir.create(dir)
  for (name in names(datasets)) {
    haven::write_xpt(as.data.frame(datasets[[name]]), file.path(dir, paste0(tolower(name), ".xpt")),
                     name = name, version = 5)
  }
  dir
}

found <- function(result, id) result$findings[result$findings$rule_id == id, ]
send <- function(dir, ...) suppressWarnings(check_study(dir, standard = "SENDIG", version = "3.1", ...))

dm_send <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = c("S1-1", "S1-2", "S1-3"),
                      SUBJID = c("1", "2", "3"), RFSTDTC = c("2020-01-01", "2020-01-05", "2020-01-02"),
                      ARMCD = c("1", "1", "2"), ARM = c("Low", "Low", "Ctrl"),
                      ACTARMCD = c("1", "1", "2"), ACTARM = c("Low", "Low", "Ctrl"), SPECIES = "RAT",
                      stringsAsFactors = FALSE)
ex_send <- data.frame(STUDYID = "S1", DOMAIN = "EX", USUBJID = c("S1-1", "S1-2", "S1-2"),
                      EXSEQ = c(1, 1, 2), EXTRT = "Drug", EXDOSE = 1,
                      EXSTDTC = c("2020-01-01", "2020-01-03", "2020-01-04"),
                      EXENDTC = c("2020-01-02", "2020-01-03", "2020-01-06"), stringsAsFactors = FALSE)

test_that("a QNAM with two QLABELs is reported on both records (CORE-000302, SEND)", {
  supp <- data.frame(STUDYID = "S1", RDOMAIN = "DM", USUBJID = c("S1-1", "S1-2", "S1-3"), IDVAR = "",
                     IDVARVAL = "", QNAM = c("AA", "AA", "BB"), QLABEL = c("Label A", "Label X", "Label B"),
                     QVAL = "v", QORIG = "CRF", stringsAsFactors = FALSE)
  dir <- study_dir(list(DM = dm_send, SUPPDM = supp))
  on.exit(unlink(dir, recursive = TRUE))
  hits <- found(send(dir), "CORE-000302")
  expect_setequal(unique(paste(hits$Dataset, hits$Record)), c("SUPPDM 1", "SUPPDM 2"))
})

test_that("NOT DONE without a reason is reported, column empty or absent (CORE-000774, SEND)", {
  lb <- data.frame(STUDYID = "S1", DOMAIN = "LB", USUBJID = "S1-1", LBSEQ = 1:3,
                   LBTESTCD = c("ALT", "AST", "GLUC"), LBTEST = c("ALT", "AST", "Glucose"),
                   LBORRES = c("", "", "5"), LBSTAT = c("NOT DONE", "NOT DONE", ""),
                   LBREASND = c("", "Sample lost", ""), stringsAsFactors = FALSE)
  bw <- data.frame(STUDYID = "S1", DOMAIN = "BW", USUBJID = "S1-1", BWSEQ = 1:2, BWTESTCD = "BW",
                   BWTEST = "Body Weight", BWORRES = c("", "200"), BWSTAT = c("NOT DONE", ""),
                   stringsAsFactors = FALSE)
  dir <- study_dir(list(DM = dm_send, LB = lb, BW = bw))
  on.exit(unlink(dir, recursive = TRUE))
  hits <- found(send(dir), "CORE-000774")
  expect_setequal(unique(paste(hits$Dataset, hits$Record)), c("LB 1", "BW 1"))
})

test_that("--ENDTC without --ENDY is reported once for the dataset (CORE-000776, SEND)", {
  dir <- study_dir(list(DM = dm_send, EX = ex_send))
  on.exit(unlink(dir, recursive = TRUE))
  hits <- found(send(dir), "CORE-000776")
  expect_equal(unique(hits$Dataset), "EX")
  expect_true(all(is.na(hits$Record)))
  expect_true("EXENDY" %in% hits$Variable)
})

test_that("an ACTARMCD with two ACTARMs is reported on both records (CORE-000791, SEND)", {
  dm <- dm_send
  dm$ACTARM <- c("Low", "High", "Ctrl")
  dir <- study_dir(list(DM = dm))
  on.exit(unlink(dir, recursive = TRUE))
  hits <- found(send(dir), "CORE-000791")
  expect_setequal(unique(paste(hits$Dataset, hits$Record)), c("DM 1", "DM 2"))
})

test_that("RFSTDTC after the first EXSTDTC, or with no EX, is reported (CORE-001044, SEND)", {
  # S1-1 matches its first dose; S1-2 starts later than it; S1-3 has no EX.
  dir <- study_dir(list(DM = dm_send, EX = ex_send))
  on.exit(unlink(dir, recursive = TRUE))
  hits <- found(send(dir), "CORE-001044")
  expect_setequal(unique(paste(hits$Dataset, hits$Record)), c("DM 2", "DM 3"))
})

test_that("a healthy-subject TS without INDIC = NA is reported on every TS record (CORE-000742)", {
  # Deprecated, SDTMIG only. TSVCDREF keeps the record over 80 bytes: at 80
  # or under, the engine's reader (pandas read_sas) drops the last row, so a
  # narrower file cannot be compared with it.
  ts <- data.frame(STUDYID = "S1", DOMAIN = "TS", TSSEQ = 1, TSPARMCD = c("HLTSUBJI", "INDIC", "ADDON"),
                   TSPARM = c("Healthy Subject Indicator", "Trial Disease/Condition Indication",
                              "Added on to Existing Treatments"),
                   TSVAL = c("Y", "Hypertension", "N"), TSVALNF = "",
                   TSVCDREF = "CDISC CT reference text padding", stringsAsFactors = FALSE)
  dir <- study_dir(list(TS = ts))
  on.exit(unlink(dir, recursive = TRUE))
  result <- suppressWarnings(check_study(dir, standard = "SDTMIG", version = "3.4",
                                         include_deprecated = TRUE))
  hits <- found(result, "CORE-000742")
  expect_setequal(unique(paste(hits$Dataset, hits$Record)), c("TS 1", "TS 2", "TS 3"))
})

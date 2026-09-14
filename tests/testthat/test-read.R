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
  # Note the case difference, which is deliberate and load-bearing: the
  # declared dataset is `TS` while the file is `ts.csv`. See the dedicated
  # test below for why that combination is the interesting one.
  writeLines("dataset,variable,label,type,length\nTS,STUDYID,Study Identifier,Char,10", file.path(dir, "_variables.csv"))
  writeLines("STUDYID\nABC", file.path(dir, "ts.csv"))
  study <- read_study(dir)
  expect_equal(names(study$datasets), "TS")
  expect_equal(study$datasets$TS$data$STUDYID, "ABC")
  expect_true(is.na(study$datasets$TS$label))
})

test_that("a dataset CSV is found when the declared name's case differs from the file", {
  # A study declares a dataset's name in `_datasets.csv`/`_variables.csv` in
  # whatever case upstream used; the file beside it carries its own. Declaring
  # `TS` and shipping `ts.csv` is legal and happens.
  #
  # This was a real bug that CI caught and no local run could: building the
  # path as paste0(fname, ".csv") assumes the cases match. Windows and macOS
  # are case-insensitive by default, so opening "TS.csv" just returns ts.csv
  # and the assumption is invisible. Linux is case-sensitive, so fread()
  # hard-errors and takes the entire study read down with it - which is also
  # what CRAN's own build machines would have hit.
  #
  # Asserting via file.exists() would prove nothing here, since that call is
  # itself case-insensitive on this machine. Compare the BASENAME instead:
  # that is an ordinary string comparison, so this test fails on every
  # platform if the resolution regresses.
  dir <- tempfile("coreval_case_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("STUDYID\nABC", file.path(dir, "ts.csv"))

  expect_equal(basename(dataset_csv_path(dir, "TS")), "ts.csv")
  expect_equal(basename(dataset_csv_path(dir, "Ts")), "ts.csv")
  expect_equal(basename(dataset_csv_path(dir, "ts")), "ts.csv")

  # A genuinely absent dataset must still yield the plain expected path, so
  # fread() reports "does not exist" for the name actually asked for rather
  # than something surprising.
  expect_equal(basename(dataset_csv_path(dir, "DM")), "DM.csv")
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

test_that("a column declared Num holding SAS's '.' missing token becomes numeric NA, not character", {
  # fread reads a lone "." as text, so the column's inherent type is string
  # and colClasses cannot down-cast it - it warned and left the column
  # CHARACTER despite _variables.csv declaring it Num. Quiet type drift like
  # that is exactly what a conformance check must not inherit. Confirmed
  # against CORE-000183's fixture, where pc.PCSTRESN is declared Num and
  # every value is ".".
  dir <- tempfile("coreval_num_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  writeLines(c(
    "dataset,variable,label,type,length",
    "lb,USUBJID,Unique Subject Identifier,Char,8",
    "lb,LBSTRESN,Numeric Result,Num,8",
    "lb,LBSTRESC,Character Result,Char,20"
  ), file.path(dir, "_variables.csv"))
  writeLines(c("Filename,Label", "lb,Lab"), file.path(dir, "_datasets.csv"))
  writeLines(c(
    "USUBJID,LBSTRESN,LBSTRESC",
    "01,.,BELOW LIMIT",
    "02,4.5,4.5",
    "03,,MISSING"
  ), file.path(dir, "lb.csv"))

  # No warning: the down-cast complaint is handled, not merely tolerated.
  expect_no_warning(study <- read_study(dir))
  lb <- study$datasets$LB$data

  expect_type(lb$LBSTRESN, "double")
  expect_equal(lb$LBSTRESN, c(NA, 4.5, NA))
  # A Char column declared as such is untouched, blanks included.
  expect_type(lb$LBSTRESC, "character")
  expect_equal(lb$LBSTRESC, c("BELOW LIMIT", "4.5", "MISSING"))
})

test_that("a declared-Num column carrying real text is left alone rather than nulled", {
  # Coercing it would silently destroy the evidence: a Num variable holding
  # words is itself a finding, and turning it into NA hides it.
  dir <- tempfile("coreval_numtext_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines(c(
    "dataset,variable,label,type,length",
    "ds,DSNOMDY,Nominal Day,Num,8"
  ), file.path(dir, "_variables.csv"))
  writeLines(c("Filename,Label", "ds,Disposition"), file.path(dir, "_datasets.csv"))
  writeLines(c("DSNOMDY", "yesterday", "3"), file.path(dir, "ds.csv"))

  study <- read_study(dir)
  expect_type(study$datasets$DS$data$DSNOMDY, "character")
  expect_equal(study$datasets$DS$data$DSNOMDY, c("yesterday", "3"))
})

test_that("a ragged CSV keeps every record, its real column names, and its comma separator", {
  dir <- tempfile("coreval_ragged_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  writeLines(c(
    "Filename,Label",
    "pr,Procedures",
    "ce,Clinical Events",
    "sj,Subject Stages"
  ), file.path(dir, "_datasets.csv"))
  vars <- function(ds, v) paste0(ds, ",", v, ",", v, ",Char,50")
  writeLines(c(
    "dataset,variable,label,type,length",
    vars("pr", "STUDYID"), vars("pr", "DOMAIN"), vars("pr", "USUBJID"), vars("pr", "PRSCAT"),
    vars("ce", "STUDYID"), vars("ce", "DOMAIN"), vars("ce", "USUBJID"), vars("ce", "CESCAT"),
    vars("sj", "STUDYID"), vars("sj", "DOMAIN"), vars("sj", "USUBJID"), vars("sj", "RSTGCD")
  ), file.path(dir, "_variables.csv"))

  # Last row is SHORT. fread's default reads it as a footer and DISCARDS it,
  # so a violation on that record could never be reported.
  writeLines(c(
    "STUDYID,DOMAIN,USUBJID,PRSCAT",
    "S1,PR,S1-001,PRIOR",
    "S1,PR,S1-002"
  ), file.path(dir, "pr.csv"))

  # A row with MORE fields than the header makes fread abandon the header and
  # name the columns after the first row's VALUES.
  writeLines(c(
    "STUDYID,DOMAIN,USUBJID,CESCAT",
    "S1,CE,S1-001",
    "S1,CE,S1-002,COMPLICATIONS"
  ), file.path(dir, "ce.csv"))

  # Well-formed, but every field carries a trailing space. fread re-runs
  # separator detection under fill and picked WHITESPACE on a file like this,
  # returning V1..Vn and losing every declared column.
  writeLines(c(
    "STUDYID ,DOMAIN ,USUBJID,RSTGCD",
    "S1 ,SJ ,S1-001 ,GEST ",
    "S1 ,SJ ,S1-002 ,UNPLAN"
  ), file.path(dir, "sj.csv"))

  # Warnings here are fread reporting that _variables.csv declares a column
  # name the file does not carry, because sj.csv's header has trailing spaces
  # inside the NAMES. That is about type declarations, never about rows, and
  # it is not what this test is pinning down.
  study <- suppressWarnings(read_study(dir))

  expect_equal(nrow(study$datasets$PR$data), 2)
  expect_equal(study$datasets$PR$data$USUBJID, c("S1-001", "S1-002"))

  expect_true(all(c("STUDYID", "DOMAIN", "USUBJID", "CESCAT") %in%
                    names(study$datasets$CE$data)))
  expect_equal(nrow(study$datasets$CE$data), 2)

  expect_true("RSTGCD" %in% names(study$datasets$SJ$data))
  expect_equal(ncol(study$datasets$SJ$data), 4)
  # Trailing whitespace is data, not noise: CORE-000867 exists to catch it.
  expect_equal(study$datasets$SJ$data$RSTGCD[1], "GEST ")
})

test_that("an escaped quote inside a quoted CSV field is read as one quote", {
  dir <- tempfile("coreval_quotes_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  writeLines(c("Filename,Label", "pm,Parameter Maps"), file.path(dir, "_datasets.csv"))
  writeLines(c(
    "dataset,variable,label,type,length",
    "pm,ID,Id,Char,20",
    "pm,REFERENCE,Reference,Char,200",
    "pm,PLAIN,Plain,Char,20"
  ), file.path(dir, "_variables.csv"))
  # RFC 4180: a quote inside a quoted field is escaped by doubling it. fread
  # does not collapse the pair when the field holds no separator, so the value
  # arrived with its quotes still doubled and every pattern match against it
  # was computed from text the file does not contain.
  writeLines(c(
    "ID,REFERENCE,PLAIN",
    'P1,"<ref klass=""Range"" id=""R_3""/>",ok',
    'P2,"<ref klass=""Code"", with a comma""/>",ok',
    "P3,no quotes here,ok"
  ), file.path(dir, "pm.csv"))

  pm <- suppressWarnings(read_study(dir))$datasets$PM$data
  expect_identical(pm$REFERENCE[1], '<ref klass="Range" id="R_3"/>')
  # The field holding a separator is the case fread already got right, so the
  # repair must not double-collapse it.
  expect_identical(pm$REFERENCE[2], '<ref klass="Code", with a comma"/>')
  expect_identical(pm$REFERENCE[3], "no quotes here")
  expect_identical(pm$PLAIN, c("ok", "ok", "ok"))
  expect_equal(nrow(pm), 3)
})

test_that("a dataset is named after the manifest's Dataset Name, not its file", {
  # USDM test cases truncate the file stem to 27 characters and carry the real
  # entity name in a separate column, so StudyProtocolDocumentVersio.csv
  # declares StudyProtocolDocumentVersion. Naming the dataset after the file
  # left five USDM rules skipped as "no dataset matches the rule's scope" with
  # the scoped dataset sitting right there, and two more filing findings under
  # an entity USDM does not have. The reference reads the declared column
  # (csv_metadata_reader.py:85-89), with the filename only as a fallback.
  dir <- tempfile("coreval_declared_name_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  writeLines(c(
    "Filename,Dataset Name,Label",
    "StudyProtocolDocumentVersio,StudyProtocolDocumentVersion,Study Protocol Version",
    "timing,,Timing"
  ), file.path(dir, "_datasets.csv"))
  writeLines(c(
    "dataset,variable,label,type,length",
    "StudyProtocolDocumentVersio,id,id,Char,50",
    "timing,id,id,Char,50"
  ), file.path(dir, "_variables.csv"))
  writeLines(c("id", "SPDV_1"), file.path(dir, "StudyProtocolDocumentVersio.csv"))
  writeLines(c("id", "Timing_1"), file.path(dir, "timing.csv"))

  study <- read_study(dir)
  # The declared name where there is one, the filename where the cell is blank.
  expect_equal(sort(names(study$datasets)),
               c("STUDYPROTOCOLDOCUMENTVERSION", "TIMING"))
  # Still opened by filename: the CSV on disk and _variables.csv's `dataset`
  # column both use the truncated form.
  expect_equal(study$datasets$STUDYPROTOCOLDOCUMENTVERSION$data$id, "SPDV_1")
})

test_that("two files declaring one dataset name raise rather than resolving to the first", {
  # No fixture upstream does this; a split-domain case declaring AE twice
  # would, and every study$datasets[[dom]] lookup would silently return the
  # first of the two.
  dir <- tempfile("coreval_dup_name_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  writeLines(c(
    "Filename,Dataset Name,Label",
    "ae1,AE,Adverse Events",
    "ae2,AE,Adverse Events"
  ), file.path(dir, "_datasets.csv"))
  writeLines(c(
    "dataset,variable,label,type,length",
    "ae1,USUBJID,USUBJID,Char,50",
    "ae2,USUBJID,USUBJID,Char,50"
  ), file.path(dir, "_variables.csv"))
  writeLines(c("USUBJID", "S1-001"), file.path(dir, "ae1.csv"))
  writeLines(c("USUBJID", "S1-002"), file.path(dir, "ae2.csv"))

  expect_error(read_study(dir), "declares one dataset name for several files")
})

test_that("text in the Windows encoding SAS writes is read as text", {
  # A transport file states no encoding, and SAS on Windows writes wlatin1: a
  # curly apostrophe is the single byte 0x92, handed back marked as UTF-8 where
  # it is not a character at all. CDISC's own pilot submission has three such
  # values in TS, and every pattern rule that met one warned and left that row
  # unchecked.
  broken <- rawToChar(as.raw(c(0x41, 0x6c, 0x7a, 0x92, 0x73)))
  Encoding(broken) <- "UTF-8"
  expect_false(validUTF8(broken))

  fixed <- coreval:::fix_invalid_utf8(c(broken, "plain", NA))
  expect_true(all(validUTF8(fixed[!is.na(fixed)])))
  expect_identical(fixed[[1]], "Alz\u2019s")
  expect_identical(fixed[2:3], c("plain", NA))

  ts <- data.frame(STUDYID = "S1", DOMAIN = "TS", TSVAL = broken)
  ds <- coreval:::build_dataset_from_data_frame(ts)
  expect_identical(ds$data$TSVAL, "Alz\u2019s")
})

test_that("numbers carry no conversion noise from a transport file", {
  # IBM floating point converted to a double lands a hair off what was
  # written, so one visit number can be 9.2999999999999989 in LB and
  # 9.3000000000000007 in SV. CDISC's pilot submission does this, and 250 lab
  # records were reported as having a visit that is not among the subject's
  # visits.
  dt <- data.table::data.table(
    LBVIS = c(9.2999999999999989, 1.2000000000000002, 3, NA),
    SVVIS = c(9.3000000000000007, 1.2, 3, NA),
    WHEN = as.Date("2024-01-01") + 0:3
  )
  coreval:::settle_float_noise(dt)
  expect_identical(dt$LBVIS, dt$SVVIS)
  expect_identical(dt$WHEN, as.Date("2024-01-01") + 0:3)

  dir <- tempfile("coreval_noise_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  haven::write_xpt(data.frame(STUDYID = "S1", DOMAIN = "SV", USUBJID = "S1-1",
                              VISITNUM = 9.3000000000000007), file.path(dir, "sv.xpt"))
  haven::write_xpt(data.frame(STUDYID = "S1", DOMAIN = "LB", USUBJID = "S1-1",
                              VISITNUM = 9.2999999999999989), file.path(dir, "lb.xpt"))
  study <- read_study(dir)
  expect_identical(study$datasets$LB$data$VISITNUM, study$datasets$SV$data$VISITNUM)
})

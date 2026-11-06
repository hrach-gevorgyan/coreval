# Expected violation vector from a reference results.csv: one row per
# (Record, Variable) pair, filtered to one Dataset - distinct Record values
# are the violating rows.
test_that("is_not_unique_set matches CDISC's reference results.csv (CORE-000186)", {
  # SUBJID is_not_unique_set [STUDYID]: flags duplicate (SUBJID, STUDYID)
  # combinations anywhere in the dataset.
  rule <- fixture_rule("CORE-000186")
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000186", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$DM, domain = "DM")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DM", nrow(study$datasets$DM$data))
    )
  }
})

test_that("is_not_unique_relationship matches CDISC's reference results.csv (CORE-000132)", {
  # ETCD <-> ELEMENT must be a one-to-one mapping within the TE dataset.
  rule <- fixture_rule("CORE-000132")
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000132", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study$datasets$TE, domain = "TE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "TE", nrow(study$datasets$TE$data))
    )
  }
})

test_that("is_inconsistent_across_dataset's positive (compliant) CDISC fixture still matches (CORE-000612)", {
  # PCSTRESU is_inconsistent_across_dataset [PCTESTCD]. CORE-000612's own
  # NEGATIVE fixture is stale relative to the pinned upstream engine: it
  # expects EVERY row in an inconsistent PCTESTCD group to be flagged (e.g.
  # a 5-ug/mL-vs-1-bottles split flags all 6 rows), but the engine's own
  # bundled unit tests (test_check_operators/test_value_set_checks.py::
  # test_is_inconsistent_across_dataset, parametrized case
  # ("STRESU", "TESTCD", ..., [False, False, True, False])) prove the real
  # algorithm (`_check_inconsistency()` in check_operators/
  # dataframe_operators.py) flags only the MINORITY value's rows, unless
  # there's a tie for the majority (then it flags everyone) - see
  # flag_inconsistent_minority() in op_grouping.R. Only the POSITIVE
  # (all-consistent, zero expected violations) fixture is asserted here;
  # the negative one is intentionally not, since coreval matches the
  # engine's own source and unit tests over a stale results.csv.
  rule <- fixture_rule("CORE-000612")
  dir <- test_path("fixtures", "core_rules", "CORE-000612", "positive", "01")
  study <- read_study(file.path(dir, "data"))
  actual <- evaluate_rule(rule, study$datasets$PC, domain = "PC")
  expect_equal(
    actual,
    expected_violations_for(file.path(dir, "results", "results.csv"), "PC", nrow(study$datasets$PC$data))
  )
})

test_that("is_inconsistent_across_dataset matches CDISC's reference results.csv (CORE-000142)", {
  # A group with two values is marked whole, and Sensitivity: Group reports its
  # first row. where_populated_columns keeps out a row with no --TPT.
  rule <- fixture_rule("CORE-000142")
  for (case in c("negative/01", "positive/01", "positive/03")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000142", case)
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "FT")
    reported <- group_first_violations(study$datasets$FT, actual, rule$grouping_variables, "FT")
    expected <- which(expected_violations_for(file.path(dir, "results", "results.csv"), "FT",
                                              nrow(study$datasets$FT$data)))
    expect_equal(reported, expected, info = case)
  }
})

test_that("is_inconsistent_across_dataset flags every row of a group with two values", {
  # CDISC's engine flagged the minority until its 1.0.0.
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1, 2),
    ELTM = c("PT1H", "PT2H", "PT1H", "PT1H")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(TRUE, TRUE, TRUE, FALSE))
})

test_that("is_inconsistent_across_dataset treats a blank target as its own value, not an exclusion", {
  data <- data.table::data.table(
    VISITNUM = c(1, 1, 1),
    ELTM = c("PT1H", "PT1H", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM")
  expect_equal(evaluate_check(check, dataset, "FT"), c(TRUE, TRUE, TRUE))
})

test_that("has_same_values matches CDISC's reference results.csv (CORE-000365)", {
  # "MHCAT non_empty AND MHCAT has_same_values" - flags every record when
  # the whole dataset's non-blank MHCAT values are all identical.
  rule <- fixture_rule("CORE-000365")
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000365", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "MH")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "MH", nrow(study$datasets$MH$data))
    )
  }
})

test_that("has_same_values is dataset-level: FALSE for every row once >1 distinct non-blank value exists", {
  data <- data.table::data.table(CAT = c("A", "A", "B"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "CAT", operator = "has_same_values")
  expect_equal(evaluate_check(check, dataset, "MH"), c(FALSE, FALSE, FALSE))

  data2 <- data.table::data.table(CAT = c("A", "A", "A"))
  dataset2 <- list(data = data2, meta = NULL)
  expect_equal(evaluate_check(check, dataset2, "MH"), c(TRUE, TRUE, TRUE))

  # A blank is a second value, as in the reference.
  data3 <- data.table::data.table(CAT = c("A", "A", ""))
  dataset3 <- list(data = data3, meta = NULL)
  expect_equal(evaluate_check(check, dataset3, "MH"), c(FALSE, FALSE, FALSE))
})

test_that("is_not_unique_relationship finds nothing against a column the dataset lacks", {
  # EGTPTNUM is absent. It was compared as the text "EGTPTNUM", and whether a
  # row was reported depended on the order of the rows. Both engines answer
  # FALSE; CDISC's used to fail here, until its 1.0.0.
  data <- data.table::data.table(EGTPT = c("PRE-DOSE", "PRE-DOSE", "1H POST"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "EGTPT", operator = "is_not_unique_relationship", value = "EGTPTNUM")
  expect_equal(evaluate_check(check, dataset, "EG"), c(FALSE, FALSE, FALSE))
})

test_that("present_on_multiple_rows_within matches CDISC's reference results.csv (CORE-000363)", {
  # "DSDECOD present_on_multiple_rows_within: USUBJID" - flags every row
  # whose DSDECOD value appears on more than one row for the same subject.
  rule <- fixture_rule("CORE-000363")
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000363", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "DS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DS", nrow(study$datasets$DS$data))
    )
  }
})

test_that("present_on_multiple_rows_within/not_present_on_multiple_rows_within flag the right rows", {
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S1", "S2"),
    DSDECOD = c("A", "A", "B", "A")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "DSDECOD", operator = "present_on_multiple_rows_within", within = "USUBJID")
  expect_equal(evaluate_check(check, dataset, "DS"), c(TRUE, TRUE, FALSE, FALSE))

  check2 <- list(name = "DSDECOD", operator = "not_present_on_multiple_rows_within", within = "USUBJID")
  expect_equal(evaluate_check(check2, dataset, "DS"), c(FALSE, FALSE, TRUE, TRUE))
})

test_that("is_not_unique_set treats blanks as a real, matching value when grouping", {
  data <- data.table::data.table(A = c("", "", "X"), B = c("Y", "Y", "Y"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("is_not_unique_set supports a multi-column comparator", {
  data <- data.table::data.table(
    A = c("X", "X", "X"),
    B = c("Y", "Y", "Z"),
    C = c("1", "1", "1")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = c("B", "C"))
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("is_not_unique_relationship flags both sides of an inconsistent mapping", {
  # ETCD "LOW" maps to two different ELEMENTs -> both LOW rows flagged.
  # ETCD "HIGH" and "SCREEN" are consistent -> not flagged.
  data <- data.table::data.table(
    ETCD = c("SCREEN", "LOW", "HIGH", "LOW"),
    ELEMENT = c("Screening", "Elem A", "High Dose", "Elem B")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, TRUE, FALSE, TRUE))
})

test_that("is_not_unique_relationship flags a value paired with both a real value and a blank", {
  data <- data.table::data.table(
    ETCD = c("A", "A", "B"),
    ELEMENT = c("X", "", "Y")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  # ETCD "A" maps to "X" in one row and blank in another - inconsistent.
  expect_equal(evaluate_check(check, dataset, "TS"), c(TRUE, TRUE, FALSE))
})

test_that("is_not_unique_set does not collide the blank sentinel with a real value of the text \"NA\"", {
  # Bug: an earlier version used the literal string "NA" as its blank
  # sentinel, which collided with a genuine data value of "NA" - a row
  # with a real "NA" value and a row with an actual blank would be treated
  # as duplicates of each other even though they aren't.
  data <- data.table::data.table(A = c("NA", "", "X"), B = c("Y", "Y", "Y"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE, FALSE))
})

test_that("is_not_unique_set does not collide keys across a multi-column boundary", {
  # Bug: pasting columns together with no separator lets ("1", "23") and
  # ("12", "3") both collapse to the same key "123".
  data <- data.table::data.table(A = c("1", "12"), B = c("23", "3"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "A", operator = "is_not_unique_set", value = "B")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE))
})

test_that("is_not_unique_relationship never flags a fully blank pair", {
  data <- data.table::data.table(ETCD = c("", "A"), ELEMENT = c("", "X"))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "ETCD", operator = "is_not_unique_relationship", value = "ELEMENT")
  expect_equal(evaluate_check(check, dataset, "TS"), c(FALSE, FALSE))
})

test_that("is_not_unique_set resolves \"--\" prefixes in its grouping columns (CORE-000914)", {
  # The reference engine's _resolve_prefixes() applies replace_all_prefixes()
  # to any LIST-valued operator argument, so a comparator like
  # ["--TESTCD", "USUBJID"] arrives fully resolved. Left raw, the "--"
  # entries match no real column, are silently dropped, and the uniqueness
  # key collapses to whatever happened to be literal - a far looser key
  # that reports masses of spurious duplicates.
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2", "S2"),
    LBTESTCD = c("NA", "K", "NA", "NA"),
    LBBLFL = c("Y", "Y", "Y", "Y")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(
    name = "LBBLFL", operator = "is_not_unique_set",
    value = c("--TESTCD", "USUBJID")
  )
  # Resolved key is (LBBLFL, LBTESTCD, USUBJID): only S2's two NA rows
  # duplicate. Unresolved, the key degrades to (LBBLFL, USUBJID) and would
  # wrongly flag all four rows.
  expect_equal(evaluate_check(check, dataset, "LB"), c(FALSE, FALSE, TRUE, TRUE))
})

test_that("is_not_unique_set spans every file a split domain is spread across (CORE-000750)", {
  # A domain split across files is still one domain: --SEQ must be unique
  # per subject across lbae.csv AND lbds.csv together. A value appearing
  # once in EACH file is a genuine duplicate that is invisible to either
  # file on its own. Findings are still reported per physical file with
  # that file's own record numbers, which is what the reference does.
  lbae <- list(
    data = data.table::data.table(
      DOMAIN = "LB", USUBJID = c("S1", "S1"), LBSEQ = c(4, 5)
    ),
    meta = NULL
  )
  lbds <- list(
    data = data.table::data.table(
      DOMAIN = "LB", USUBJID = c("S1", "S1"), LBSEQ = c(4, 9)
    ),
    meta = NULL
  )
  study <- list(datasets = list(LBAE = lbae, LBDS = lbds))
  check <- list(name = "LBSEQ", operator = "is_not_unique_set", value = c("DOMAIN", "USUBJID"))

  # LBSEQ 4 appears in both files -> duplicate; 5 and 9 are unique.
  expect_equal(evaluate_check(check, lbae, "LBAE", study = study), c(TRUE, FALSE))
  expect_equal(evaluate_check(check, lbds, "LBDS", study = study), c(TRUE, FALSE))

  # Without the sibling, neither row is a duplicate - which is exactly the
  # answer that made this bug invisible.
  solo <- list(datasets = list(LBAE = lbae))
  expect_equal(evaluate_check(check, lbae, "LBAE", study = solo), c(FALSE, FALSE))
})

test_that("split_domain_siblings only groups files sharing a DOMAIN, current file first", {
  lbae <- list(data = data.table::data.table(DOMAIN = "LB", X = 1), meta = NULL)
  lbds <- list(data = data.table::data.table(DOMAIN = "LB", X = 2), meta = NULL)
  ae <- list(data = data.table::data.table(DOMAIN = "AE", X = 3), meta = NULL)
  study <- list(datasets = list(LBAE = lbae, LBDS = lbds, AE = ae))

  sibs <- split_domain_siblings(list(study = study, dataset = lbae, domain = "LBAE"))
  expect_length(sibs, 2)
  expect_equal(sibs[[1]]$X, 1) # current file first, so results slice back correctly
  expect_equal(sibs[[2]]$X, 2) # AE is a different domain and excluded

  # An unsplit domain returns nothing, so callers keep their simple path.
  expect_length(split_domain_siblings(list(study = study, dataset = ae, domain = "AE")), 0)
})

test_that("uniqueness is not asserted about a column that is absent", {
  # 1.0 asserts nothing about a missing column. CDISC's engine negates, and says TRUE.
  old <- .coreval_env$engine
  on.exit(.coreval_env$engine <- old)
  ctx <- list(exists = FALSE, n = 3L, target = rep(NA_character_, 3))
  .coreval_env$engine <- "core1"
  expect_equal(get_operator("is_unique_relationship")(ctx), rep(FALSE, 3))
  .coreval_env$engine <- "cdisc"
  expect_equal(get_operator("is_unique_relationship")(ctx), rep(TRUE, 3))
  # is_unique_set follows CDISC's engine, which keeps whichever of its columns
  # exist and fails when none does; CORE 1.0 answers FALSE.
  study <- one_dataset(list(A = c("x", "y", "x")), "XX")
  rule <- list(check = list(name = "B", operator = "is_unique_set", value = "C"))
  expect_error(evaluate_rule(rule, study, "XX"), "none of which this dataset has")
  expect_equal(evaluate_rule(core1_rule(rule$check), study, "XX"), rep(FALSE, 3))
})

test_that("a date-time column can be tested for blanks", {
  # Comparing a date-time with "" makes R parse "" as a date-time, which
  # fails. Every rule reaching is_blank() on such a column stopped with
  # "character string is not in a standard unambiguous format" and was
  # reported as skipped: on CDISC's ADaM examples, whose ADT reads as a
  # date-time, a dozen rules per dataset, CORE-000690 among them.
  when <- as.POSIXct(c("2007-01-10", NA), tz = "UTC")
  expect_equal(is_blank(when), c(FALSE, TRUE))
  expect_equal(is_blank(as.Date(c("2007-01-10", NA))), c(FALSE, TRUE))
  expect_equal(is_blank(c("", NA, "x")), c(TRUE, TRUE, FALSE))
  expect_equal(is_blank(c(1, NA)), c(FALSE, TRUE))

  # And the rule it stopped finds what it should: two variables sharing a label.
  data <- data.table::data.table(ADT = when, ANL01FL = c("Y", ""), ANL01FN = c(1, NA))
  meta <- data.frame(
    variable = c("ADT", "ANL01FL", "ANL01FN"),
    label = c("Analysis Date", "Analysis Flag 01", "Analysis Flag 01"),
    type = c("Num", "Char", "Num"), length = c(8, 1, 8)
  )
  study <- list(datasets = list(ADVS = list(data = data, meta = meta)))
  hit <- evaluate_rule(fixture_rule("CORE-000690"), study, "ADVS")
  expect_equal(which(hit), 2:3)
})

test_that("is_not_unique_set with a regex puts values it does not match with the blanks, as CDISC's engine does", {
  # apply_regex() gives None for a value the pattern does not match, and
  # fillna() groups those with the blanks, so two partial dates on one
  # subject and test are duplicates of each other (CORE-001034).
  study <- one_dataset(list(
    USUBJID = c("1", "1", "1"), LBTESTCD = "ALB",
    LBDTC = c("2022-01-14T07:00", "2022-01", "2022-02")
  ), "LB")
  rule <- list(check = list(name = "LBDTC", operator = "is_not_unique_set",
                            value = c("USUBJID", "LBTESTCD"), regex = "^\\d{4}-\\d{2}-\\d{2}"))
  expect_equal(evaluate_rule(rule, study, "LB"), c(FALSE, TRUE, TRUE))
  # The column is sampled at its first non-blank value, not at a blank.
  study$datasets$LB$data$LBDTC <- c("", "2022-01-14T07:00", "2022-01-14T09:00")
  expect_equal(evaluate_rule(rule, study, "LB"), c(FALSE, TRUE, TRUE))
})

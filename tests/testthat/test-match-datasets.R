expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("a simple Match Datasets join (DS matched with DM) matches CDISC's reference results.csv", {
  # CORE-000034: DSSTDTC not_equal_to DM.DTHDTC, joined on USUBJID. DTHDTC
  # doesn't collide with any DS column, so it's referenced by its bare name
  # after the join.
  rule <- .coreval_env$data$rules[["CORE-000034"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000034", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "DS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DS", nrow(study$datasets$DS$data))
    )
  }
})

test_that("a one-to-many Match Datasets join matches CDISC's reference results.csv", {
  # CORE-000097: SV matched with SE on USUBJID alone. SE has multiple
  # time-windowed records per subject, so the join legitimately explodes
  # one SV row into several - the rule's OWN Check conditions
  # (SESTDTC <= SVSTDTC <= SEENDTC) filter down to the one SE record whose
  # window actually contains the visit date. This only comes out right if
  # the join keeps every exploded row (no "first match" dedup) and results
  # collapse back to one finding per original SV record - confirmed against
  # the real cdisc-rules-engine source (a plain, undeduplicated merge) and
  # against this exact reference data (an earlier "keep first match"
  # implementation reproduced a different, wrong record).
  #
  # The schema's own Check condition also confirms the {MatchedDomain}.
  # {Column} collision-naming convention directly: both SV and SE have
  # EPOCH, and the condition literally references "SE.EPOCH".
  rule <- .coreval_env$data$rules[["CORE-000097"]]
  cond <- rule$check$all[[4]]
  expect_equal(cond$value, "SE.EPOCH")

  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000097", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SV")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SV", nrow(study$datasets$SV$data))
    )
  }
})

test_that("apply_match_dataset renames only colliding columns, joins the rest bare", {
  left <- list(data = data.table::data.table(USUBJID = c("S1", "S2"), EPOCH = c("A", "B")), meta = NULL)
  right_data <- data.table::data.table(USUBJID = c("S1", "S2"), EPOCH = c("X", "Y"), DTHFL = c("Y", ""))
  study <- list(datasets = list(DM = list(data = right_data, meta = NULL)))

  spec <- list(Keys = "USUBJID", Name = "DM")
  joined <- apply_match_dataset(left, spec, study, "SV")

  expect_equal(joined$data$EPOCH, c("A", "B")) # left's own EPOCH untouched
  expect_equal(joined$data$DM.EPOCH, c("X", "Y")) # right's collides -> prefixed
  expect_equal(joined$data$DTHFL, c("Y", "")) # no collision -> bare name
})

test_that("apply_match_dataset keeps every left row (left join), even without a match", {
  left <- list(data = data.table::data.table(USUBJID = c("S1", "S2", "S3")), meta = NULL)
  right_data <- data.table::data.table(USUBJID = c("S1", "S2"), DTHFL = c("Y", "N"))
  study <- list(datasets = list(DM = list(data = right_data, meta = NULL)))

  joined <- apply_match_dataset(left, list(Keys = "USUBJID", Name = "DM"), study, "SV")
  expect_equal(nrow(joined$data), 3)
  expect_true(is.na(joined$data$DTHFL[3]))
})

test_that("a one-to-many match keeps every exploded row, tagged with .coreval_row_id", {
  left <- list(data = data.table::data.table(USUBJID = c("S1", "S2")), meta = NULL)
  right_data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    ELEMENT = c("A", "B", "C")
  )
  study <- list(datasets = list(SE = list(data = right_data, meta = NULL)))

  joined <- apply_match_dataset(left, list(Keys = "USUBJID", Name = "SE"), study, "SV")
  expect_equal(nrow(joined$data), 3) # S1 explodes into 2 rows, not deduplicated
  expect_equal(joined$data$.coreval_row_id, c(1, 1, 2))
})

test_that("evaluate_rule collapses an exploded join back to one result per original row", {
  sv_data <- data.table::data.table(USUBJID = c("S1", "S2"), EPOCH = c("SCREENING", "TREATMENT"))
  se_data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    EPOCH = c("SCREENING", "TREATMENT", "OTHER")
  )
  study <- list(datasets = list(
    SV = list(data = sv_data, meta = NULL),
    SE = list(data = se_data, meta = NULL)
  ))
  rule <- list(
    match_datasets = list(list(Keys = "USUBJID", Name = "SE")),
    check = list(name = "EPOCH", operator = "not_equal_to", value = "SE.EPOCH")
  )
  # S1: exploded into (EPOCH=SCREENING vs SE.EPOCH=SCREENING -> match, not a
  # violation) and (EPOCH=SCREENING vs SE.EPOCH=TREATMENT -> violation).
  # "any exploded copy violates" -> S1 is a violation overall.
  # S2: only match is EPOCH=TREATMENT vs SE.EPOCH=OTHER -> violation.
  expect_equal(evaluate_rule(rule, study, "SV"), c(TRUE, TRUE))
})

test_that("Match Datasets with a partial key matches CDISC's reference results.csv across every applicable domain (CORE-000270)", {
  rule <- .coreval_env$data$rules[["CORE-000270"]]
  for (case in c("negative", "positive")) {
    cases <- Sys.glob(test_path("fixtures", "core_rules", "CORE-000270", case, "*"))
    for (dir in cases) {
      study <- read_study(file.path(dir, "data"))
      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      for (domain in names(study$datasets)) {
        if (!rule_applies_to_domain(rule, domain)) next
        actual <- which(evaluate_rule(rule, study, domain))
        expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
        expect_equal(sort(unname(actual)), expected, info = paste(dir, domain))
      }
    }
  }
})

test_that("a Match Datasets self-join with an all-scalar Check matches CDISC's reference results.csv (CORE-000291)", {
  # EX matched with itself on USUBJID explodes the dataset (multiple EX
  # records per subject), but BOTH of this rule's Check conditions are
  # dataset-level scalars ($EXVAMT_EXISTS equal_to true; EC exists) - no
  # per-row sibling condition for R's ordinary `&` recycling to broadcast
  # against. Confirmed this needs evaluate_condition() itself to recycle
  # every leaf to one value per row - without it, indexing the length-1
  # result by exploded row id produced NA past the first row.
  rule <- .coreval_env$data$rules[["CORE-000291"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000291", case, "01")
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual_any <- any(evaluate_rule(rule, study, domain))
      expected_any <- nrow(results[results$Dataset == domain, ]) > 0 ||
        nrow(results[results$Dataset == "STUDY", ]) > 0
      expect_equal(actual_any, expected_any, info = paste(case, domain))
    }
  }
})

test_that("apply_match_dataset never matches a blank/NA key against another blank/NA key", {
  # Bug: base merge() treats NA (and "" as an ordinary string) as a
  # matchable value by default - a blank USUBJID on both sides would
  # fabricate a match instead of correctly getting NA for every joined-in
  # column, the same as any other genuinely unmatched key.
  left <- list(data = data.table::data.table(USUBJID = c("S1", "", NA_character_)), meta = NULL)
  right_data <- data.table::data.table(USUBJID = c("S1", "", NA_character_), DTHFL = c("Y", "N", "N"))
  study <- list(datasets = list(DM = list(data = right_data, meta = NULL)))

  joined <- apply_match_dataset(left, list(Keys = "USUBJID", Name = "DM"), study, "SV")
  joined$data <- joined$data[order(joined$data$.coreval_row_id)]
  expect_equal(nrow(joined$data), 3)
  expect_equal(joined$data$DTHFL[1], "Y") # a genuine key still matches
  expect_true(is.na(joined$data$DTHFL[2])) # blank key: no fabricated match
  expect_true(is.na(joined$data$DTHFL[3])) # NA key: no fabricated match
})

test_that("apply_match_dataset skips the join entirely when a key is missing from either side, rather than joining on the rest", {
  # Bug: dropping just the missing key and joining on whatever's left turns
  # a composite key (USUBJID+VISITNUM) into a much looser one (USUBJID
  # alone) when the CURRENT domain has no VISITNUM at all - e.g. AE, which
  # explodes into every one of that subject's SV visits instead of staying
  # unmatched. Confirmed against CORE-000270's real fixture.
  left <- list(data = data.table::data.table(USUBJID = c("S1", "S1")), meta = NULL)
  right_data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S1"), VISITNUM = c(1, 2, 3), SVPRESP = c("Y", "Y", "Y")
  )
  study <- list(datasets = list(SV = list(data = right_data, meta = NULL)))
  joined <- apply_match_dataset(left, list(Keys = c("USUBJID", "VISITNUM"), Name = "SV"), study, "AE")
  expect_equal(nrow(joined$data), 2) # unchanged - no cartesian explosion
  expect_false("SVPRESP" %in% names(joined$data))
})

test_that("apply_match_dataset handles an all-valid-key dataset without erroring on the empty blank branch", {
  # Regression for a fix-of-a-fix: when there are zero blank-key rows,
  # assigning a length-1 NA into a zero-row data.table used to error
  # ("replacement has 1 row, data has 0").
  left <- list(data = data.table::data.table(USUBJID = c("S1", "S2")), meta = NULL)
  right_data <- data.table::data.table(USUBJID = c("S1", "S2"), DTHFL = c("Y", "N"))
  study <- list(datasets = list(DM = list(data = right_data, meta = NULL)))
  joined <- apply_match_dataset(left, list(Keys = "USUBJID", Name = "DM"), study, "SV")
  expect_equal(joined$data$DTHFL, c("Y", "N"))
})

test_that("apply_match_dataset refuses SUPP/Child joins rather than guess", {
  left <- list(data = data.table::data.table(USUBJID = "S1"), meta = NULL)
  study <- list(datasets = list())
  expect_error(apply_match_dataset(left, list(Name = "SUPPAE", Keys = "USUBJID"), study, "AE"))
  expect_error(apply_match_dataset(left, list(Name = "CO", Keys = "USUBJID", Child = TRUE), study, "AE"))
})

test_that("a RELREC relationship join matches CDISC's reference results.csv (CORE-000757)", {
  # CM matched to FA via RELREC: a group-level pairing (CM.CMGRPID ==
  # FA.FAGRPID, both RELREC IDVARVAL blank) joins FA's columns in under a
  # literal "RELREC." prefix - confirmed directly against the real
  # relrec.csv/results.csv (see apply_relrec_match()'s docstring).
  rule <- .coreval_env$data$rules[["CORE-000757"]]
  for (case in c("negative/01", "negative/02", "positive/01", "positive/02", "positive/03")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000757", case)
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "CM")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "CM", nrow(study$datasets$CM$data))
    )
  }
})

test_that("apply_relrec_match joins the record-level pattern (both sides pinned by IDVARVAL)", {
  left <- list(data = data.table::data.table(USUBJID = "S1", CMSEQ = c(1, 2)), meta = NULL)
  fa_data <- data.table::data.table(USUBJID = "S1", FASEQ = c(3, 4), FAOBJ = c("ASPIRIN", "OTHER"))
  relrec_data <- data.table::data.table(
    STUDYID = "STUDY1", RDOMAIN = c("FA", "CM"), USUBJID = "",
    IDVAR = c("FASEQ", "CMSEQ"), IDVARVAL = c("3", "1"), RELTYPE = "ONE", RELID = "CMFA-1"
  )
  study <- list(datasets = list(
    FA = list(data = fa_data, meta = NULL),
    RELREC = list(data = relrec_data, meta = NULL)
  ))
  joined <- apply_relrec_match(left, study, "CM")
  expect_equal(joined$data$`RELREC.FAOBJ`, c("ASPIRIN", NA))
})

test_that("apply_relrec_match joins the group-level pattern (both IDVARVAL blank, matched by value)", {
  left <- list(data = data.table::data.table(USUBJID = "S1", CMGRPID = c("1", "2")), meta = NULL)
  fa_data <- data.table::data.table(USUBJID = "S1", FAGRPID = c("2", "9"), FAOBJ = c("ERYTHEMA", "OTHER"))
  relrec_data <- data.table::data.table(
    STUDYID = "STUDY1", RDOMAIN = c("FA", "CM"), USUBJID = "",
    IDVAR = c("FAGRPID", "CMGRPID"), IDVARVAL = "", RELTYPE = c("MANY", "ONE"), RELID = "CMFA-1"
  )
  study <- list(datasets = list(
    FA = list(data = fa_data, meta = NULL),
    RELREC = list(data = relrec_data, meta = NULL)
  ))
  joined <- apply_relrec_match(left, study, "CM")
  expect_equal(joined$data$`RELREC.FAOBJ`, c(NA, "ERYTHEMA"))
})

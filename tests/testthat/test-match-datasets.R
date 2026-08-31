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

test_that("a Child join attaches each child record to the parent it names in RDOMAIN", {
  # The dataset being checked is the CHILD (a CO/SUPP/RELREC record) and the
  # parent isn't named by the rule - each row names it itself, so different
  # rows can join to different domains. The parent row is chosen by matching
  # the standard keys and then the column IDVAR names against IDVARVAL.
  child <- list(
    data = data.table::data.table(
      RDOMAIN = c("LB", "LB"), USUBJID = c("S1", "S1"),
      IDVAR = c("LBSEQ", "LBSEQ"), IDVARVAL = c("321", "999")
    ),
    meta = NULL
  )
  lb <- list(
    data = data.table::data.table(USUBJID = "S1", LBSEQ = 321, LBTESTCD = "ALB"),
    meta = NULL
  )
  study <- list(datasets = list(LB = lb))
  joined <- apply_child_match(child, study, c("USUBJID", "IDVAR", "IDVARVAL"))

  # Row 1's IDVARVAL matches a real LB record, so its columns come across.
  expect_equal(joined$data$LBTESTCD[1], "ALB")
  # Row 2 points at LBSEQ 999, which doesn't exist. The parent's columns are
  # still PRESENT but empty - a rule asking "is IDVARVAL really the value of
  # the variable IDVAR names" needs that column to exist in order to report
  # the mismatch; omitting it makes the violation silently disappear.
  expect_true("LBSEQ" %in% names(joined$data))
  expect_true(is.na(joined$data$LBTESTCD[2]))
})

test_that("apply_match_dataset still refuses a plain RELREC spec it doesn't implement", {
  left <- list(data = data.table::data.table(USUBJID = "S1"), meta = NULL)
  study <- list(datasets = list())
  expect_error(apply_match_dataset(left, list(Name = "RELREC", Keys = "USUBJID", Child = FALSE), study, "AE"))
  # A SUPP name whose dataset simply isn't in the study is a no-op, not an
  # error - the rule just has nothing to join.
  expect_equal(apply_match_dataset(left, list(Name = "SUPPAE", Keys = "USUBJID"), study, "AE"), left)
})

test_that("a SUPP dataset is pivoted from QNAM/QVAL into one column per QNAM and joined to its parent", {
  # The reference's process_supp() + merge_pivot_supp_dataset(): the long
  # QNAM/QVAL shape becomes one column per QNAM, joined on the static
  # identifier columns present in both, plus the record-level key the
  # SUPP's own IDVAR names (with IDVARVAL renamed to that key). IDVARVAL is
  # character even when the parent key is numeric, so both sides compare as
  # text - AESEQ 1 must match IDVARVAL "1".
  parent <- list(
    data = data.table::data.table(
      STUDYID = "S", USUBJID = c("P1", "P1", "P2"), AESEQ = c(1, 2, 1)
    ),
    meta = NULL
  )
  supp <- list(
    data = data.table::data.table(
      STUDYID = "S", RDOMAIN = "AE", USUBJID = c("P1", "P1", "P2"),
      IDVAR = "AESEQ", IDVARVAL = c("1", "1", "1"),
      QNAM = c("AESOSP", "AESMIE", "AESOSP"),
      QVAL = c("Other", "Y", "Another")
    ),
    meta = NULL
  )
  joined <- apply_supp_match(parent, supp)

  # One column per QNAM, values attached to the right parent record only.
  expect_true(all(c("AESOSP", "AESMIE") %in% names(joined$data)))
  expect_equal(joined$data$AESOSP, c("Other", NA, "Another"))
  expect_equal(joined$data$AESMIE, c("Y", NA, NA))
  # Parent rows are all kept, in their original order.
  expect_equal(nrow(joined$data), 3)
  expect_equal(joined$data$USUBJID, c("P1", "P1", "P2"))
})

test_that("a SUPP join matches CDISC's reference results.csv (CORE-000597)", {
  rule <- .coreval_env$data$rules[["CORE-000597"]]
  for (case in c("negative/01", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000597", case)
    study <- read_study(file.path(dir, "data"))
    actual <- which(evaluate_rule(rule, study, domain = "AE"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    expected <- sort(unique(as.integer(results$Record[results$Dataset == "AE"])))
    expect_equal(sort(unname(actual)), expected, info = case)
  }
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

test_that("a RELREC group-level match with wildcard comparisons matches CDISC's reference results.csv (CORE-000744)", {
  # FAOBJ compared against RELREC.**TERM/**TRT/**DECOD - the reference
  # engine's own "**" domain wildcard, resolved per-row to whichever
  # partner domain RELREC actually joined (here always AE). Exercises two
  # bugs fixed together: (1) a FA row with NO RELREC partner at all must
  # not be flagged just because the wildcard's fallback value is blank
  # (needs an inner join, not a left join, for RELREC matches); (2) a
  # group-level RELREC pairing (IDVARVAL blank on both sides) must still
  # only link records of the SAME USUBJID - without that, negative/01's
  # FALNKGRP-based grouping cross-matched unrelated subjects' AE records.
  rule <- .coreval_env$data$rules[["CORE-000744"]]
  for (case in c(
    "negative/01", "negative/02", "negative/03", "negative/04",
    "positive/01", "positive/02", "positive/03", "positive/04"
  )) {
    dir <- test_path("fixtures", "core_rules", "CORE-000744", case)
    study <- read_study(file.path(dir, "data"))
    actual <- which(evaluate_rule(rule, study, domain = "FA"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    expected <- sort(unique(as.integer(results$Record[results$Dataset == "FA"])))
    expect_equal(sort(unname(actual)), expected, info = case)
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
  # A row with no RELREC partner at all (CMSEQ=2 here) is dropped entirely -
  # an inner join, not a left join - since a comparison against a genuinely
  # blank joined value would otherwise be a REAL violation per the
  # reference engine's own not_equal_to truth table (populated vs blank ->
  # True), wrongly flagging records that simply have no related record at
  # all (confirmed against CORE-000744's real fixtures). `.coreval_row_id`
  # still maps the surviving row back to its original position (1).
  joined <- apply_relrec_match(left, study, "CM")
  expect_equal(joined$data$`RELREC.FAOBJ`, "ASPIRIN")
  expect_equal(joined$data$.coreval_row_id, 1L)
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
  expect_equal(joined$data$`RELREC.FAOBJ`, "ERYTHEMA")
  expect_equal(joined$data$.coreval_row_id, 2L)
})

test_that("a matched column the rule references as \"<Name>.<col>\" is prefixed even without a collision", {
  # The reference engine prefixes the columns a rule NAMES, collision or
  # not (dataset_preprocessor.py builds referenced_targets from the rule's
  # own targets and renames exactly those), and only then lets pandas'
  # suffixes=("", f".{domain}") handle remaining true collisions. Renaming
  # solely on collision leaves a referenced-but-non-colliding column under
  # its bare name, so the rule's "DM.RFPENDTC" finds nothing and
  # resolve_condition_value() degrades it to a literal string - silently
  # always-false (CORE-000952 found no violations) or always-true
  # (CORE-000249 flagged every row).
  left <- list(data = data.table::data.table(USUBJID = c("S1", "S2"), AESEQ = c(1, 2)), meta = NULL)
  dm <- data.table::data.table(USUBJID = c("S1", "S2"), RFPENDTC = c("2020-01-01", ""), AGE = c(30, 40))
  study <- list(datasets = list(DM = list(data = dm, meta = NULL)))
  rule <- list(check = list(all = list(list(name = "DM.RFPENDTC", operator = "non_empty"))))

  joined <- apply_match_dataset(left, list(Keys = "USUBJID", Name = "DM"), study, "AE", rule)
  expect_true("DM.RFPENDTC" %in% names(joined$data))
  expect_equal(joined$data$`DM.RFPENDTC`, c("2020-01-01", ""))
  # a column the rule never references keeps its bare name (no collision)
  expect_true("AGE" %in% names(joined$data))

  # with no rule supplied, only the collision rule applies (back-compat)
  plain <- apply_match_dataset(left, list(Keys = "USUBJID", Name = "DM"), study, "AE")
  expect_true("RFPENDTC" %in% names(plain$data))
})

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
    cases <- fixture_cases("CORE-000270", case)
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
  # Pattern-matched deliberately: a bare expect_error() passes on ANY error,
  # including one from a typo in the call itself, so it can assert that
  # something broke without asserting that the right thing broke.
  expect_error(
    apply_match_dataset(left, list(Name = "RELREC", Keys = "USUBJID", Child = FALSE), study, "AE"),
    "unsupported join type"
  )
  # A SUPP name whose dataset isn't in the study cannot be joined, and
  # evaluated unjoined the rule would compare against columns that do not
  # exist, so it is refused and the rule is skipped with that reason.
  expect_error(
    apply_match_dataset(left, list(Name = "SUPPAE", Keys = "USUBJID"), study, "AE"),
    "needs SUPPAE, which is not in this study"
  )
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

test_that("the child match joins to each row's own RDOMAIN parent", {
  # apply_child_match() used to loop over every child row and rescan the whole
  # parent per row. It was 90% of check_study()'s runtime and superlinear: one
  # SUPPAE/AE merge took 3.1s at 1,616 rows and 60.4s at 16,160. It is now a
  # grouped join. These assertions pin the semantics that rewrite had to keep.
  ae <- data.table::data.table(
    STUDYID = "S", DOMAIN = "AE", USUBJID = c("01", "01", "02"),
    AESEQ = c(1L, 2L, 1L), AETERM = c("HEADACHE", "NAUSEA", "RASH")
  )
  dm <- data.table::data.table(
    STUDYID = "S", DOMAIN = "DM", USUBJID = c("01", "02"), AGE = c(40L, 50L)
  )
  study <- list(datasets = list(
    AE = list(data = ae, meta = NULL),
    DM = list(data = dm, meta = NULL)
  ))
  supp <- list(
    data = data.table::data.table(
      STUDYID = "S", RDOMAIN = c("AE", "AE", "DM", "ZZ"),
      USUBJID = c("01", "01", "02", "01"),
      IDVAR = c("AESEQ", "AESEQ", "", ""),
      IDVARVAL = c("2", "99", "", ""),
      QNAM = c("A", "B", "C", "D"), QVAL = c("w", "x", "y", "z")
    ),
    meta = NULL
  )
  out <- apply_child_match(supp, study, c("STUDYID", "USUBJID", "IDVAR", "IDVARVAL"))
  d <- as.data.frame(out$data)

  expect_equal(nrow(d), 4L)
  # Row order is the child's own, not group order.
  expect_equal(d$QNAM, c("A", "B", "C", "D"))
  # IDVAR/IDVARVAL pick the named parent record, not merely the first.
  expect_equal(d$AETERM[1], "NAUSEA")
  # No parent record matches IDVARVAL 99: the parent's columns must still be
  # PRESENT and empty. A rule asking whether IDVARVAL really is the value of
  # the parent variable IDVAR needs that column to exist to report the
  # mismatch - drop it and the violation disappears silently.
  expect_true("AETERM" %in% names(d))
  expect_true(is.na(d$AETERM[2]))
  # A blank IDVARVAL takes the first row matching the standard keys alone.
  expect_equal(d$AGE[3], 50L)
  # RDOMAIN naming a dataset the study does not have leaves the row alone.
  expect_true(is.na(d$AETERM[4]))
})

test_that("the child match leaves the caller's dataset untouched", {
  # apply_child_match() no longer copies the child dataset up front, because
  # copying an 18 MB SUPPAE for every rule that needed the join was pure
  # waste. data.table assigns BY REFERENCE, so the guarantee that replaced the
  # copy - that nothing here modifies the input - has to be asserted, not
  # assumed. If it ever does, the caller's dataset silently grows a stray
  # column and every later rule sees it.
  ae <- data.table::data.table(
    STUDYID = "S", DOMAIN = "AE", USUBJID = c("01", "02"),
    AESEQ = c(1L, 1L), AETERM = c("HEADACHE", "RASH")
  )
  supp <- data.table::data.table(
    STUDYID = "S", RDOMAIN = "AE", USUBJID = c("01", "02"),
    IDVAR = "AESEQ", IDVARVAL = c("1", "1"),
    QNAM = c("A", "B"), QVAL = c("x", "y")
  )
  study <- list(datasets = list(AE = list(data = ae, meta = NULL)))
  before_cols <- names(supp)
  before_rows <- nrow(supp)
  before <- data.table::copy(supp)

  out <- apply_child_match(list(data = supp, meta = NULL), study,
                           c("STUDYID", "USUBJID", "IDVAR", "IDVARVAL"))

  expect_equal(names(supp), before_cols)
  expect_equal(nrow(supp), before_rows)
  expect_false(".coreval_child_row" %in% names(supp))
  expect_true(isTRUE(all.equal(as.data.frame(supp), as.data.frame(before))))
  # And the join still did its job.
  expect_equal(as.data.frame(out$data)$AETERM, c("HEADACHE", "RASH"))
  expect_false(".coreval_child_row" %in% names(out$data))
})

test_that("a Match Datasets key can name a different column on each side", {
  # Both forms in one Keys list, which is how USDM writes them: a bare string
  # for a column both sides share, and Left/Right where the child's foreign
  # key is spelled differently from the parent's id.
  keys <- list(
    list(Left = "id", Right = "parent_id"),
    "rel_type"
  )
  resolved <- match_key_columns(keys, "ENCOUNTER")
  expect_identical(resolved$left, c("id", "rel_type"))
  expect_identical(resolved$right, c("parent_id", "rel_type"))

  # A mapping giving only one side means the same name on both.
  one_sided <- match_key_columns(list(list(Left = "id")), "ENCOUNTER")
  expect_identical(one_sided$left, "id")
  expect_identical(one_sided$right, "id")

  # A plain character vector, which is what every bundled rule uses, is
  # unchanged and still resolves a "--" prefix against the domain.
  plain <- match_key_columns(c("USUBJID", "--SEQ"), "AE")
  expect_identical(plain$left, c("USUBJID", "AESEQ"))
  expect_identical(plain$right, c("USUBJID", "AESEQ"))
})

test_that("a join on differently named keys attaches the right rows", {
  parent <- data.table::data.table(
    id = c("E1", "E2", "E3"),
    rel_type = rep("definition", 3),
    instanceType = rep("Encounter", 3)
  )
  child <- data.table::data.table(
    parent_id = c("E1", "E3"),
    rel_type = rep("definition", 2),
    code = c("C1", "C3")
  )
  study <- list(
    datasets = list(
      ENCOUNTER = list(data = parent, meta = NULL),
      CODE = list(data = child, meta = NULL)
    ),
    standard = list(product = "USDM", version = NA_character_)
  )
  rule <- list(
    id = "TEST-1",
    match_datasets = list(list(
      Name = "Code",
      Keys = list(list(Left = "id", Right = "parent_id"), "rel_type")
    )),
    check = list(all = list(list(name = "code", operator = "exists")))
  )

  joined <- apply_match_datasets(study$datasets$ENCOUNTER, rule, study, "ENCOUNTER")
  expect_equal(nrow(joined$data), 3)
  # E2 has no child row, so its joined value is missing rather than another
  # encounter's.
  expect_identical(joined$data$code[joined$data$id == "E1"], "C1")
  expect_identical(joined$data$code[joined$data$id == "E3"], "C3")
  expect_true(is.na(joined$data$code[joined$data$id == "E2"]) ||
                !nzchar(joined$data$code[joined$data$id == "E2"]))
})

test_that("a declared left join blanks an unmatched row's joined-in columns", {
  # `Join Type: left` is the reference's signal to keep the rows that matched
  # nothing and blank their right-hand columns, so `empty` answers TRUE on
  # them: merge_sdtm_datasets() writes None across a left_only row
  # (data_processor.py:470-480). Those rows are what the rule is asking about.
  # CORE-000816 wants the epochs no activity instance points at, CORE-000830
  # the timings nothing schedules; both reported nothing, because the join
  # leaves a character NA there and `empty` deliberately answers NA on one.
  parent <- data.table::data.table(
    id = c("E1", "E2"),
    rel_type = rep("definition", 2)
  )
  child <- data.table::data.table(
    parent_id = "E1",
    rel_type = "definition",
    code = "C1"
  )
  study <- list(
    datasets = list(
      ENCOUNTER = list(data = parent, meta = NULL),
      CODE = list(data = child, meta = NULL)
    ),
    standard = list(product = "USDM", version = NA_character_)
  )
  spec <- list(
    Name = "Code",
    Keys = list(list(Left = "id", Right = "parent_id"), "rel_type")
  )
  rule <- function(join_type) {
    if (!is.null(join_type)) spec[["Join Type"]] <- join_type
    list(id = "TEST-1", match_datasets = list(spec),
         check = list(all = list(list(name = "code", operator = "exists"))))
  }

  declared <- apply_match_datasets(study$datasets$ENCOUNTER, rule("left"), study, "ENCOUNTER")
  expect_identical(declared$data$code[declared$data$id == "E2"], "")
  expect_identical(declared$data$code[declared$data$id == "E1"], "C1")

  # With no declared type the reference joins INNER and drops the unmatched
  # row entirely; coreval keeps it with NA, and six FDA.SENDIG rules depend on
  # that NA reading as populated rather than blank. So the fill must not reach
  # a spec that declares nothing.
  undeclared <- apply_match_datasets(study$datasets$ENCOUNTER, rule(NULL), study, "ENCOUNTER")
  expect_true(is.na(undeclared$data$code[undeclared$data$id == "E2"]))
})

test_that("a parent key written with padding still finds its record", {
  # SAS commonly writes a number into a character field right-aligned, and
  # CDISC's own pilot submission stores IDVARVAL 1 as "       1". Compared
  # as-is, no SUPPLB or RELREC row found its parent record, and CORE-000206
  # reported all 64,637 of them as pointing at records that do not exist.
  study <- list(
    datasets = list(
      LB = list(data = data.table::data.table(
        STUDYID = "S1", DOMAIN = "LB", USUBJID = "S1-1", LBSEQ = c(1, 2),
        LBTESTCD = c("ALB", "GLUC")
      ), meta = NULL),
      SUPPLB = list(data = data.table::data.table(
        STUDYID = "S1", RDOMAIN = "LB", USUBJID = "S1-1", IDVAR = "LBSEQ",
        IDVARVAL = c("       1", " 2 "), QNAM = "LBTMSHI", QVAL = "Y"
      ), meta = NULL)
    ),
    standard = list(product = "SDTMIG", version = NA_character_)
  )
  joined <- coreval:::apply_child_match(study$datasets$SUPPLB, study,
                                        c("STUDYID", "USUBJID", "IDVAR", "IDVARVAL"))
  expect_equal(joined$data$LBTESTCD, c("ALB", "GLUC"))

  rule <- coreval:::.coreval_env$data$rules[["CORE-000206"]]
  out <- coreval:::run_rule_on_domain(rule, study, "SUPPLB")
  expect_false(any(out$violations))
})

# A small study written as transport files, checked the way a user checks one.
study_on_disk <- function(...) {
  dir <- tempfile("coreval_join_")
  dir.create(dir)
  datasets <- list(...)
  for (nm in names(datasets)) {
    haven::write_xpt(datasets[[nm]], file.path(dir, paste0(tolower(nm), ".xpt")), name = nm)
  }
  dir
}
rule_records <- function(result, rule_id) {
  f <- result$findings
  sort(unique(f$Record[f$rule_id == rule_id]))
}

test_that("a RELREC link relates records of one subject only", {
  # Each subject's FA record is related to that subject's AE record, and the
  # terms agree. Paired on RELID alone, each FA was also related to the other
  # subject's AE and both were reported.
  dir <- study_on_disk(
    DM = data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = c("S1-001", "S1-002")),
    AE = data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = c("S1-001", "S1-002"),
                    AESEQ = c(1, 1), AETERM = c("HEADACHE", "NAUSEA"), AEDECOD = ""),
    FA = data.frame(STUDYID = "S1", DOMAIN = "FA", USUBJID = c("S1-001", "S1-002"),
                    FASEQ = c(1, 1), FATESTCD = "SEV", FATEST = "Severity",
                    FAOBJ = c("HEADACHE", "NAUSEA"), FAORRES = "MILD"),
    RELREC = data.frame(STUDYID = "S1", RDOMAIN = c("AE", "FA", "AE", "FA"),
                        USUBJID = c("S1-001", "S1-001", "S1-002", "S1-002"),
                        IDVAR = c("AESEQ", "FASEQ", "AESEQ", "FASEQ"), IDVARVAL = "1",
                        RELTYPE = "", RELID = c("1", "1", "1", "1"))
  )
  on.exit(unlink(dir, recursive = TRUE))
  expect_length(rule_records(check_study(dir), "CORE-000744"), 0)
})

test_that("records of a domain RELREC does not mention are not compared with anything", {
  dir <- study_on_disk(
    DM = data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = "S1-001"),
    FA = data.frame(STUDYID = "S1", DOMAIN = "FA", USUBJID = "S1-001", FASEQ = c(1, 2),
                    FATESTCD = "SEV", FATEST = "Severity", FAOBJ = "HEADACHE", FAORRES = "MILD"),
    CM = data.frame(STUDYID = "S1", DOMAIN = "CM", USUBJID = "S1-001", CMSEQ = 1, CMTRT = "X"),
    AE = data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = "S1-001", AESEQ = 1, AETERM = "Y"),
    RELREC = data.frame(STUDYID = "S1", RDOMAIN = c("CM", "AE"), USUBJID = "S1-001",
                        IDVAR = c("CMSEQ", "AESEQ"), IDVARVAL = "1", RELTYPE = "", RELID = "1")
  )
  on.exit(unlink(dir, recursive = TRUE))
  expect_length(rule_records(check_study(dir), "CORE-000744"), 0)
})

test_that("a rule joining a dataset the study lacks is skipped with the reason, not evaluated", {
  # CORE-000034 compares DS with DM.DTHDTC. Without DM it compared with the
  # word "DTHDTC" and reported both death records.
  dir <- study_on_disk(
    DS = data.frame(STUDYID = "S1", DOMAIN = "DS", USUBJID = c("S1-001", "S1-002"),
                    DSSEQ = 1, DSTERM = "DEATH", DSDECOD = "DEATH", DSCAT = "DISPOSITION EVENT",
                    DSSTDTC = c("2024-01-01", "2024-02-01")),
    AE = data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = "S1-001", AESEQ = 1, AETERM = "Y")
  )
  on.exit(unlink(dir, recursive = TRUE))
  result <- check_study(dir)
  expect_length(rule_records(result, "CORE-000034"), 0)
  why <- result$skipped$reason[result$skipped$rule_id == "CORE-000034"]
  expect_match(why, "needs DM, which is not in this study")
})

test_that("SUPP qualifiers join whatever way the record key is written", {
  # SAS writes IDVARVAL right-aligned; "1.0" and 100000 are the same keys.
  # Compared as plain text, none matched and CORE-000597 found nothing.
  for (case in list(list(idvarval = "       1", seq = 1),
                    list(idvarval = "1.0", seq = 1),
                    list(idvarval = "100000", seq = 100000))) {
    dir <- study_on_disk(
      DM = data.frame(STUDYID = "S", DOMAIN = "DM", USUBJID = c("S-1", "S-2")),
      AE = data.frame(STUDYID = "S", DOMAIN = "AE", USUBJID = c("S-1", "S-2"),
                      AESEQ = case$seq, AETERM = "X", AEDECOD = "X", AESER = "Y",
                      AESMIE = "N", AESDTH = "N", AESHOSP = "N", AESLIFE = "N",
                      AESCONG = "N", AESDISAB = "N"),
      SUPPAE = data.frame(STUDYID = "S", RDOMAIN = "AE", USUBJID = c("S-1", "S-2"),
                          IDVAR = "AESEQ", IDVARVAL = case$idvarval, QNAM = "AESOSP",
                          QLABEL = "Other", QVAL = "Something", QORIG = "CRF", QEVAL = "")
    )
    result <- check_study(dir)
    expect_equal(rule_records(result, "CORE-000597"), c(1L, 2L), info = case$idvarval)
    # ...and no SUPP row is reported as pointing at a record that does not exist.
    expect_length(rule_records(result, "CORE-000206"), 0)
    unlink(dir, recursive = TRUE)
  }
})

test_that("a SUPP row with no parent record keeps its own subject in the finding", {
  dir <- study_on_disk(
    DM = data.frame(STUDYID = "S", DOMAIN = "DM", USUBJID = c("S-1", "S-2")),
    AE = data.frame(STUDYID = "S", DOMAIN = "AE", USUBJID = c("S-1", "S-2"), AESEQ = 1,
                    AETERM = "X"),
    SUPPAE = data.frame(STUDYID = "S", RDOMAIN = "AE", USUBJID = c("S-1", "S-2"),
                        IDVAR = "AESEQ", IDVARVAL = c("1", "99"), QNAM = "AETRTEM",
                        QLABEL = "Treatment emergent", QVAL = "Y", QORIG = "DERIVED", QEVAL = "")
  )
  on.exit(unlink(dir, recursive = TRUE))
  f <- check_study(dir)$findings
  orphan <- f[f$rule_id == "CORE-000206", ]
  expect_equal(unique(orphan$Record), 2L)
  # The row's own values, not the parent's. CDISC's October 2026 release
  # dropped USUBJID from this rule's reported columns, so the same guard runs
  # through IDVARVAL: the orphan cites 99, and a finding built from the joined
  # parent row instead would show the parent's 1.
  expect_equal(unique(orphan$Value[orphan$Variable == "IDVARVAL"]), "99")
})

test_that("SUPP rows find their parent in a domain split across files", {
  dir <- study_on_disk(
    DM = data.frame(STUDYID = "S", DOMAIN = "DM", USUBJID = "S-1"),
    LBCH = data.frame(STUDYID = "S", DOMAIN = "LB", USUBJID = "S-1", LBSEQ = c(1, 2),
                      LBTESTCD = "GLUC"),
    LBHE = data.frame(STUDYID = "S", DOMAIN = "LB", USUBJID = "S-1", LBSEQ = c(3, 4),
                      LBTESTCD = "HGB"),
    SUPPLB = data.frame(STUDYID = "S", RDOMAIN = "LB", USUBJID = "S-1", IDVAR = "LBSEQ",
                        IDVARVAL = c("1", "3", "99"), QNAM = "LBX", QLABEL = "X",
                        QVAL = "Y", QORIG = "CRF", QEVAL = "")
  )
  on.exit(unlink(dir, recursive = TRUE))
  expect_equal(rule_records(check_study(dir), "CORE-000206"), 3L)
})

test_that("a SUPP whose IDVAR the parent lacks is refused, not joined on the subject alone", {
  parent <- list(data = data.table::data.table(STUDYID = "S", USUBJID = "P1", AESEQ = c(1, 2)),
                 meta = NULL)
  supp <- list(data = data.table::data.table(STUDYID = "S", RDOMAIN = "AE", USUBJID = "P1",
                                             IDVAR = "AESPID", IDVARVAL = "1",
                                             QNAM = "AESOSP", QVAL = "x"),
               meta = NULL)
  expect_error(apply_supp_match(parent, supp), "IDVAR names AESPID")
})

test_that("a SUPP mixing record-level and subject-level rows joins both", {
  parent <- list(data = data.table::data.table(STUDYID = "S", USUBJID = c("P1", "P1"),
                                               AESEQ = c(1, 2)),
                 meta = NULL)
  supp <- list(data = data.table::data.table(STUDYID = "S", RDOMAIN = "AE", USUBJID = "P1",
                                             IDVAR = c("AESEQ", ""), IDVARVAL = c("2", ""),
                                             QNAM = c("AESOSP", "AEXSUBJ"),
                                             QVAL = c("rec2", "subj")),
               meta = NULL)
  joined <- apply_supp_match(parent, supp)$data
  expect_equal(joined$AESOSP, c(NA, "rec2"))
  expect_equal(joined$AEXSUBJ, c("subj", "subj"))
  expect_equal(joined$AESEQ, c(1, 2))
})

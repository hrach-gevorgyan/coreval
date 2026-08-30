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

test_that("apply_match_dataset refuses Child/RELREC/SUPP joins rather than guess", {
  left <- list(data = data.table::data.table(USUBJID = "S1"), meta = NULL)
  study <- list(datasets = list())
  expect_error(apply_match_dataset(left, list(Name = "RELREC"), study, "AE"))
  expect_error(apply_match_dataset(left, list(Name = "SUPPAE", Keys = "USUBJID"), study, "AE"))
  expect_error(apply_match_dataset(left, list(Name = "CO", Keys = "USUBJID", Child = TRUE), study, "AE"))
})

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

test_that("a colliding column name after Match Datasets is what the schema expects", {
  # CORE-000097: SV matched with SE on USUBJID, both have EPOCH. The
  # schema's own Check condition references "SE.EPOCH" directly, confirming
  # the {MatchedDomain}.{Column} naming convention (see apply_match_dataset
  # unit tests below for the actual join behavior).
  #
  # NOTE: this specific rule is a known limitation, not verified end-to-end
  # here - SE (Subject Elements) legitimately has multiple time-windowed
  # records per USUBJID, and this package's "keep first match per row" join
  # isn't precise enough to reproduce CDISC's reference output for it (the
  # real engine likely needs a date-range-aware match, picking the SE
  # record whose window contains the SV visit date). Left as a documented
  # follow-up rather than guessed at.
  rule <- .coreval_env$data$rules[["CORE-000097"]]
  cond <- rule$check$all[[4]]
  expect_equal(cond$value, "SE.EPOCH")
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

test_that("apply_match_dataset refuses Child/RELREC/SUPP joins rather than guess", {
  left <- list(data = data.table::data.table(USUBJID = "S1"), meta = NULL)
  study <- list(datasets = list())
  expect_error(apply_match_dataset(left, list(Name = "RELREC"), study, "AE"))
  expect_error(apply_match_dataset(left, list(Name = "SUPPAE", Keys = "USUBJID"), study, "AE"))
  expect_error(apply_match_dataset(left, list(Name = "CO", Keys = "USUBJID", Child = TRUE), study, "AE"))
})

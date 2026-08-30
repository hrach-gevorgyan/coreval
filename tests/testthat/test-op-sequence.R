expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

test_that("does_not_have_next_corresponding_record matches CDISC's reference results.csv (CORE-000352)", {
  # "SEENDTC does_not_have_next_corresponding_record ordering: SESEQ,
  # value: SESTDTC, within: USUBJID" - flags a subject's row whenever its
  # SEENDTC doesn't equal the following record's SESTDTC.
  rule <- .coreval_env$data$rules[["CORE-000352"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000352", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SE", nrow(study$datasets$SE$data))
    )
  }
})

test_that("does_not_have_next_corresponding_record never flags a group's last row", {
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    SESEQ = c(1, 2, 1),
    SESTDTC = c("2020-01-01", "2020-01-05", "2020-02-01"),
    SEENDTC = c("2020-01-05", "2020-01-10", "2020-02-01")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "SEENDTC", operator = "does_not_have_next_corresponding_record", ordering = "SESEQ", value = "SESTDTC", within = "USUBJID")
  # row1: SEENDTC == row2's SESTDTC -> not flagged. row2: last for S1 -> not flagged.
  # row3: last for S2 -> not flagged.
  expect_equal(evaluate_check(check, dataset, "SE"), c(FALSE, FALSE, FALSE))
})

test_that("empty_within_except_last_row matches CDISC's reference results.csv (CORE-000527)", {
  rule <- .coreval_env$data$rules[["CORE-000527"]]
  for (case in c("negative/01", "positive/01", "positive/02")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000527", case)
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SE")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SE", nrow(study$datasets$SE$data))
    )
  }
})

test_that("target_is_not_sorted_by matches CDISC's reference results.csv (CORE-000386, CORE-000535)", {
  # "SJSEQ target_is_not_sorted_by value: [{name: SJSTDTC, sort_order: asc,
  # null_position: last}], within: USUBJID" - flags both members of an
  # inverted pair when the target's own order doesn't sort SJSTDTC
  # ascending.
  for (id_case in list(
    list(id = "CORE-000386", domain = "SJ", cases = c("negative/01", "positive/01")),
    list(id = "CORE-000535", domain = "SM", cases = c("negative/01"))
  )) {
    rule <- .coreval_env$data$rules[[id_case$id]]
    for (case in id_case$cases) {
      dir <- test_path("fixtures", "core_rules", id_case$id, case)
      study <- read_study(file.path(dir, "data"))
      actual <- evaluate_rule(rule, study, domain = id_case$domain)
      expect_equal(
        actual,
        expected_violations_for(file.path(dir, "results", "results.csv"), id_case$domain, nrow(study$datasets[[id_case$domain]]$data)),
        info = paste(id_case$id, case)
      )
    }
  }
})

test_that("target_is_not_sorted_by truncates a pair to common date precision, but a same-precision tie is not a violation", {
  # Different precision AND truncated-equal -> violation (can't prove
  # non-decreasing). Same precision AND equal -> NOT a violation (a real
  # tie is fine, only a real decrease is flagged).
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S1", "S2", "S2"),
    SEQ = c(1, 2, 3, 1, 2),
    STDTC = c("2020-01", "2020-01-15", "2020-02-01", "2020-03-01", "2020-03-01")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(
    name = "SEQ", operator = "target_is_not_sorted_by", within = "USUBJID",
    value = list(list(name = "STDTC", sort_order = "asc", null_position = "last"))
  )
  # S1: month "2020-01" truncated-equal to day "2020-01-15" -> (1,2) flagged;
  # (2,3) day->day, 01-15 < 02-01, genuinely increasing -> not flagged.
  # S2: same precision (day), same value -> a tie, NOT flagged.
  expect_equal(evaluate_check(check, dataset, "SM"), c(TRUE, TRUE, FALSE, FALSE, FALSE))
})

test_that("empty_within_except_last_row allows a blank target only on the group's last row", {
  data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    SESTDTC = c("2020-01-01", "2020-01-05", "2020-02-01"),
    SEENDTC = c("", "", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "SEENDTC", operator = "empty_within_except_last_row", ordering = "SESTDTC", value = "USUBJID")
  expect_equal(evaluate_check(check, dataset, "SE"), c(TRUE, FALSE, FALSE))
})

test_that("empty/non_empty are unresolvable (NA), not TRUE, when the column doesn't exist at all (CORE-000018)", {
  # "--STAT empty" - a domain that structurally has no --STAT variable
  # (e.g. EC has no ECSTAT) must NOT be treated as satisfying "empty",
  # unlike a domain that has the variable, populated blank (e.g. AG has a
  # real, blank AGSTAT and IS expected to violate in the SAME test case).
  # An earlier version of empty() defaulted a missing column to TRUE,
  # wrongly flagging every EC row here.
  rule <- .coreval_env$data$rules[["CORE-000018"]]
  dir <- test_path("fixtures", "core_rules", "CORE-000018", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
  for (domain in names(study$datasets)) {
    if (!rule_applies_to_domain(rule, domain)) next
    actual <- which(evaluate_rule(rule, study, domain))
    expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
    expect_equal(sort(unname(actual)), expected, info = domain)
  }
})

test_that("empty returns NA for a missing column, non_empty propagates it (stays NA, not TRUE/FALSE)", {
  data <- data.table::data.table(X = c("a", ""))
  dataset <- list(data = data, meta = NULL)
  expect_equal(evaluate_check(list(name = "Y", operator = "empty"), dataset, "TS"), c(NA, NA))
  expect_equal(evaluate_check(list(name = "Y", operator = "non_empty"), dataset, "TS"), c(NA, NA))
})

test_that("inconsistent_enumerated_columns matches CDISC's reference results.csv (CORE-000780)", {
  # "--VAL inconsistent_enumerated_columns" - flags a gap in the
  # COVAL/COVAL1/COVAL2 family: once one is blank, every later one in the
  # sequence must be blank too.
  rule <- .coreval_env$data$rules[["CORE-000780"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000780", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "CO")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "CO", nrow(study$datasets$CO$data))
    )
  }
})

test_that("inconsistent_enumerated_columns flags a gap in either direction", {
  data <- data.table::data.table(
    COVAL = c("x", "", "y", "x"),
    COVAL1 = c("", "a", "", "y"),
    COVAL2 = c("", "b", "z", "")
  )
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "COVAL", operator = "inconsistent_enumerated_columns")
  # row1: x,"","" - populated then nothing but blanks - fine.
  # row2: "","a","b" - COVAL skipped but COVAL1/COVAL2 populated - gap.
  # row3: y,"","z" - COVAL1 skipped but COVAL2 populated - gap.
  # row4: x,y,"" - no gap (blank only at the end).
  expect_equal(evaluate_check(check, dataset, "CO"), c(FALSE, TRUE, TRUE, FALSE))
})

test_that("inconsistent_enumerated_columns is FALSE when there's no numbered sibling column", {
  data <- data.table::data.table(COVAL = c("x", ""))
  dataset <- list(data = data, meta = NULL)
  check <- list(name = "COVAL", operator = "inconsistent_enumerated_columns")
  expect_equal(evaluate_check(check, dataset, "CO"), c(FALSE, FALSE))
})

test_that("an Operations binding that resolved to nothing is empty, a column's NA is not", {
  # The reference's `empty` is `isin(NULL_FLAVORS) | pd.isna(...)`, so a
  # merged-in aggregate with no match reads as empty, and 63 USDM rules are
  # built on that: they ask `empty` of a codelist lookup, where "this code is
  # not in the codelist" is the finding. Answering NA did not report the row,
  # it made the enclosing condition NA, and NA is not a violation - so rows
  # vanished from CORE-000859 while their neighbours were reported.
  #
  # A column's NA stays non-blank. Six FDA.SENDIG rules use `empty` on an
  # unmatched left join to tell "no partner" from "partner with a blank
  # value", and reading that as blank turns all six into failures.
  data <- data.table::data.table(JOINED = c("x", NA_character_, ""))
  dataset <- list(data = data, meta = NULL)

  from_column <- list(
    name = "JOINED", exists = TRUE, target = data$JOINED, n = 3L,
    target_is_binding = FALSE, dataset = dataset,
    condition = list(operator = "empty")
  )
  expect_equal(get_operator("empty")(from_column), c(FALSE, NA, TRUE))

  from_binding <- utils::modifyList(from_column, list(target_is_binding = TRUE))
  expect_equal(get_operator("empty")(from_binding), c(FALSE, TRUE, TRUE))
  expect_equal(get_operator("non_empty")(from_binding), c(TRUE, FALSE, FALSE))
})

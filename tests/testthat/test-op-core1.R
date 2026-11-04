# The operators only CORE 1.0's rules use (R/op_core1.R), each against the
# behaviour of the verisianHQ/cdisc-rules-engine file it ports.

leaf <- function(data, check) {
  evaluate_check(check, list(data = data.table::as.data.table(data), meta = NULL), "XX")
}

test_that("the case-insensitive pattern checks ignore case on the value only", {
  d <- list(X = c("faAE", "FAAE", "XXAE", ""))
  expect_equal(leaf(d, list(name = "X", operator = "matches_regex_case_insensitive", value = "^FA")),
               c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(leaf(d, list(name = "X", operator = "not_prefix_matches_regex_case_insensitive",
                            prefix = 2, value = "(AP|FA)")),
               c(FALSE, FALSE, TRUE, FALSE))
  expect_equal(leaf(d, list(name = "X", operator = "suffix_is_not_contained_by_case_insensitive",
                            suffix = 2, value = c("AE", "DM"))),
               c(FALSE, FALSE, FALSE, TRUE))
})

test_that("shorter_than_or_equal_to compares lengths and never reports a blank", {
  d <- list(X = c("ABCD", "ABCDE", ""))
  expect_equal(leaf(d, list(name = "X", operator = "shorter_than_or_equal_to", value = 4)),
               c(TRUE, FALSE, FALSE))
})

test_that("suffix_equal_to compares without case, against any of a list", {
  d <- list(X = c("AEDUR", "AEdur", "AESTDTC", ""))
  expect_equal(leaf(d, list(name = "X", operator = "suffix_equal_to", suffix = 3, value = "DUR",
                            value_is_literal = TRUE)),
               c(TRUE, TRUE, FALSE, FALSE))
})

test_that("is_not_substring_of looks inside every member of a set", {
  ds <- list(data = data.table::data.table(X = c("SEV", "ZZZ", "")), meta = NULL)
  check <- list(name = "X", operator = "is_not_substring_of", value = "$names")
  b <- list(`$names` = scalar_binding(c("Severity/Intensity", "SEVERE")))
  expect_equal(evaluate_check(check, ds, "XX", b), c(FALSE, TRUE, TRUE))
})

test_that("not_in_enumerated_columns looks at RACE, RACE1, RACE2 and so on", {
  d <- list(RACE = c("MULTIPLE", "MULTIPLE", "ASIAN"), RACE1 = c("ASIAN", "WHITE", ""),
            RACE2 = c("BLACK OR AFRICAN AMERICAN", "", ""), RACEX = c("BLACK OR AFRICAN AMERICAN", "", ""))
  expect_equal(leaf(d, list(name = "RACE", operator = "not_in_enumerated_columns",
                            value = "BLACK OR AFRICAN AMERICAN", value_is_literal = TRUE)),
               c(FALSE, TRUE, TRUE))
})

test_that("is_not_ordered_set reports a whole group that steps down, numbers as numbers", {
  d <- list(USUBJID = c("1", "1", "1", "2", "2"), TAETORD = c("1", "10", "2", "1", "2"))
  expect_equal(leaf(d, list(name = "TAETORD", operator = "is_not_ordered_set", value = list("USUBJID"))),
               c(TRUE, TRUE, TRUE, FALSE, FALSE))
})

test_that("CORE 1.0's date test is stricter than CDISC's", {
  x <- c("2012-11-23", "2012-11-23T00", "2012-11-23T10:05", "2013-08-", "2013-02-29", "2013",
         "2013-13", "2013-01--", "2012-11/2012-12", "")
  expect_equal(core1_invalid_date(x), c(FALSE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, TRUE))
})

test_that("invalid_date_interval accepts date/date, date/duration and duration/date only", {
  d <- list(X = c("2023-01-01/2023-01-02", "2023-01-01T08:00/P1DT2H", "P1D/2023-01-02",
                  "P1D/P2D", "2023-01-01", "2023-01-01/-P1D", ""))
  expect_equal(leaf(d, list(name = "X", operator = "invalid_date_interval", value = TRUE)),
               c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE))
})

test_that("a dictionary check is refused with the dictionary it needs", {
  d <- list(AEDECOD = "HEADACHE")
  expect_error(leaf(d, list(name = "AEDECOD", operator = "is_not_valid_meddra_term_reference")),
               "needs the MedDRA dictionary, which is not supplied")
  expect_error(leaf(d, list(name = "AEDECOD", operator = "is_not_valid_whodrug_level_reference")),
               "WHODrug")
})

test_that("an operation over one of 1.0's own reference tables is refused, not answered empty", {
  study <- list(datasets = list(TS = list(data = data.table::data.table(TSVAL = "x"), meta = NULL)))
  rule <- list(source = "core_contributor",
               check = list(name = "TSVAL", operator = "is_not_contained_by", value = "$fda"),
               operations = list(list(id = "$fda", operator = "distinct", domain = "cg_taugs",
                                      name = "fda_guides")))
  expect_error(evaluate_rule(rule, study, "TS"), "FDA Therapeutic Area User Guides")
})

test_that("Term Signification is the submission value of the codelist's terms", {
  skip_if(is.null(ct_codelists()), "bundled controlled terminology not installed")
  pkg <- utils::tail(sort(unique(ct_codelists()$package[startsWith(ct_codelists()$package, "sdtmct")])), 1)
  sig <- ct_package_attribute(pkg, "Term Signification", list(list(`Codelist Code` = "C66731")))
  sub <- ct_package_attribute(pkg, "Term Submission Value", list(list(`Codelist Code` = "C66731")))
  expect_setequal(sig, sub)
  expect_true("M" %in% sig)
})

test_that("a Value Check sees an empty number as a blank value (CORE-000356)", {
  built <- build_variable_value_check_dataset(list(
    data = data.table::data.table(LBSEQ = c(1, NA)), meta = NULL
  ))
  expect_equal(built$data$variable_value, c("1", ""))
})

in_core1 <- function(code) {
  old <- .coreval_env$engine
  on.exit(.coreval_env$engine <- old)
  .coreval_env$engine <- "core1"
  force(code)
}

test_that("1.0's one-to-one check counts a blank as a value (CORE-000141)", {
  d <- list(VSTPT = c("PRE", "", "POST"), VSTPTNUM = c(1, 1, 2))
  check <- list(name = "VSTPT", operator = "is_not_unique_relationship", value = "VSTPTNUM")
  expect_equal(in_core1(leaf(d, check)), c(TRUE, TRUE, FALSE))
})

test_that("1.0's inconsistency check marks the whole group and honours where_populated_columns", {
  d <- list(VISITNUM = c(1, 1, 1, 2, 2), ELTM = c("PT1H", "PT1H", "PT2H", "PT1H", "PT2H"),
            TPT = c("A", "A", "A", "A", ""))
  check <- list(name = "ELTM", operator = "is_inconsistent_across_dataset", value = "VISITNUM",
                where_populated_columns = "TPT")
  expect_equal(in_core1(leaf(d, check)), c(TRUE, TRUE, TRUE, FALSE, FALSE))
  # CDISC's engine marks only the minority, and has no where_populated_columns.
  expect_equal(leaf(d, check), c(FALSE, FALSE, TRUE, TRUE, TRUE))
})

test_that("1.0 compares dates cut to the shorter length, and never against a blank", {
  t <- c("2014-01-20T10:00", "2014-01-20", "2014-01-21", "", "20140120")
  c <- c("2014-01-20", "2014-01-20T10:00", "2014-01-20", "2014-01-20", "2014-01-20")
  expect_equal(core1_compare_dates(t, c, "eq"), c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_equal(core1_compare_dates(t, c, "ne"), c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_equal(core1_compare_dates("2014-03-05", "2015-03-07", "eq", "month"), TRUE)
})

test_that("a 1.0 grouped record count is 0 for a subject the other dataset lacks (CORE-000679)", {
  study <- list(datasets = list(
    DM = list(data = data.table::data.table(USUBJID = c("1", "2")), meta = NULL),
    DS = list(data = data.table::data.table(USUBJID = "1", DSDECOD = "DEATH"), meta = NULL)
  ))
  rule <- list(source = "core_contributor",
               check = list(name = "$deaths", operator = "equal_to", value = 0),
               operations = list(list(domain = "DS", filter = list(DSDECOD = "DEATH"), group = "USUBJID",
                                      id = "$deaths", name = "DSDECOD", operator = "record_count")))
  expect_equal(evaluate_rule(rule, study, "DM"), c(FALSE, TRUE))
  rule$source <- "published"
  expect_equal(evaluate_rule(rule, study, "DM"), c(FALSE, FALSE))
})

test_that("max can take an earlier operation's values (CORE-002112)", {
  study <- one_dataset(list(IETESTCD = c("A", "B", "A")))
  rule <- list(check = list(name = "$most", operator = "greater_than", value = 1),
               operations = list(list(id = "$n", operator = "record_count", group = "IETESTCD"),
                                 list(id = "$most", operator = "max", name = "$n")))
  expect_equal(evaluate_rule(rule, study, "XX"), c(TRUE, TRUE, TRUE))
})

test_that("a 1.0 rule checks the parent alone when its SUPP dataset is absent (CORE-002034)", {
  study <- list(datasets = list(AE = list(data = data.table::data.table(
    STUDYID = "S", DOMAIN = "AE", USUBJID = c("1", "2"), AESEQ = 1:2, AETERM = "X"), meta = NULL)))
  rule <- list(source = "core_contributor",
               check = list(name = "AETRTEM", operator = "not_exists"),
               match_datasets = list(list(Keys = list("USUBJID"), Name = "SUPPAE")))
  expect_equal(evaluate_rule(rule, study, "AE"), c(TRUE, TRUE))
  rule$source <- "published"
  expect_error(evaluate_rule(rule, study, "AE"), "SUPPAE")
})

test_that("a 1.0 rule's empty counts a missing value as blank", {
  d <- list(X = c("a", NA, ""))
  expect_equal(in_core1(leaf(d, list(name = "X", operator = "empty"))), c(FALSE, TRUE, TRUE))
  # CDISC's engine leaves a missing text value undecided: a join's unmatched
  # row is not the same as a blank one there.
  expect_equal(leaf(d, list(name = "X", operator = "empty")), c(FALSE, NA, TRUE))
})

test_that("define.xml exists asks whether the study has a define (CORE-002084)", {
  rule <- list(check = list(name = "define.xml", operator = "not_exists"))
  study <- one_dataset(list(X = 1))
  expect_equal(evaluate_rule(rule, study, "XX"), TRUE)
  study$define <- list(datasets = data.frame())
  expect_equal(evaluate_rule(rule, study, "XX"), FALSE)
})

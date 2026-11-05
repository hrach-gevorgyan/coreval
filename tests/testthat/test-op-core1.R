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

test_that("an operation over a 1.0 reference table coreval lacks is refused, not answered empty", {
  study <- list(datasets = list(TS = list(data = data.table::data.table(TSVAL = "x"), meta = NULL)))
  rule <- list(source = "core_contributor",
               check = list(name = "TSVAL", operator = "is_not_contained_by", value = "$med"),
               operations = list(list(id = "$med", operator = "distinct", domain = "ex_meddra",
                                      name = "code")))
  expect_error(evaluate_rule(rule, study, "TS"), "MedDRA dictionary")
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

test_that("a 1.0 rule takes a domain's class from the declared SDTMIG version (CORE-000864)", {
  rule <- core1_rule(list(name = "X", operator = "exists"),
                     scope = list(Classes = list(Include = "SPECIAL PURPOSE"), Domains = list(Include = "ALL")))
  sm <- list(data = data.table::data.table(DOMAIN = "SM", SMSEQ = 1), meta = NULL)
  # SM arrived in SDTMIG 3.3, so under 3.2 it has no class and is passed by.
  expect_false(rule_applies_to_domain(rule, "SM", dataset = sm, ig = list(standard = "SDTMIG", version = "3.2")))
  expect_true(rule_applies_to_domain(rule, "SM", dataset = sm, ig = list(standard = "SDTMIG", version = "3.4")))
  rule$source <- "published"
  expect_true(rule_applies_to_domain(rule, "SM", dataset = sm, ig = list(standard = "SDTMIG", version = "3.2")))
})

test_that("1.0's variable table lists define variables the dataset lacks (CORE-002107)", {
  skip_if_not_installed("xml2")
  real <- list(data = data.table::data.table(STUDYID = "S", DOMAIN = "SV", SVSEQ = 1),
               meta = data.frame(variable = c("STUDYID", "DOMAIN", "SVSEQ"), label = "", type = "Char"))
  define <- list(variables = data.frame(
    define_dataset_name = "SV", define_variable_name = c("STUDYID", "SVUPDES", "DOMAIN", "SVSEQ"),
    define_variable_has_no_data = FALSE, stringsAsFactors = FALSE
  ))
  built <- core1_define_and_library_variables(real, define, "SV", NULL)$data
  expect_equal(built$variable_name, c("STUDYID", "", "DOMAIN", "SVSEQ"))
  expect_equal(built$define_variable_name, c("STUDYID", "SVUPDES", "DOMAIN", "SVSEQ"))
  expect_true(built$variable_is_empty[2])
  expect_true(all(is.na(built$define_variable_has_no_data)))
})

test_that("dataset_size is the file's size, and refused for a dataset with no file (CORE-000765)", {
  rule <- list(check = list(name = "$size", operator = "greater_than", value = 5368709120),
               operations = list(list(id = "$size", operator = "extract_metadata", name = "dataset_size")))
  study <- one_dataset(list(X = 1), domain = "DM")
  expect_error(evaluate_rule(rule, study, "DM"), "size of the dataset's file")
  study$datasets$DM$file_size <- 5368709121
  expect_true(evaluate_rule(rule, study, "DM"))
  study$datasets$DM$file_size <- 10
  expect_false(evaluate_rule(rule, study, "DM"))
})

test_that("1.0's sort check compares positions and refuses overlapping partial dates (CORE-000535)", {
  ds <- list(data = data.table::data.table(
    USUBJID = "1", SMSEQ = 1:4, SMSTDTC = c("2020", "2020-01", "2021-01", "2021-03")
  ), meta = NULL)
  check <- list(name = "SMSEQ", operator = "target_is_not_sorted_by", within = "USUBJID",
                value = list(list(name = "SMSTDTC", null_position = "last", sort_order = "asc")))
  expect_equal(in_core1(evaluate_check(check, ds, "SM")), c(TRUE, FALSE, FALSE, FALSE))
  ds$data$SMSTDTC <- c("2020-01", "2020-03", "2020-02", "2020-04")
  expect_equal(in_core1(evaluate_check(check, ds, "SM")), c(FALSE, TRUE, TRUE, FALSE))
})

test_that("standard_domains lists the IG's domains of a class, not a dataset called the class (CORE-002056)", {
  study <- one_dataset(list(TSPARMCD = "X"), domain = "TS")
  study$standard <- list(product = "SDTMIG", version = "3-4")
  ops <- list(list(operator = "standard_domains", id = "$td", domain_class = "TRIAL DESIGN"))
  b <- operation_bindings_for_rule(list(operations = ops), study, "TS", study$datasets$TS)
  expect_true(all(c("TA", "TE", "TS", "TV") %in% b$`$td`$value))
  expect_false("DM" %in% b$`$td`$value)
})

test_that("define_variable_metadata reads one attribute, booleans written as Python does (CORE-002001)", {
  study <- one_dataset(list(AEDUR = "P1D"), domain = "AE")
  study$define <- list(variables = data.frame(
    define_dataset_name = "AE", define_variable_name = "AEDUR",
    define_variable_is_collected = FALSE, define_variable_ccode = "C1", stringsAsFactors = FALSE
  ))
  op <- function(attr) list(list(id = "$x", name = "--DUR", operator = "define_variable_metadata",
                                 attribute_name = attr))
  ds <- study$datasets$AE
  ds$data$DOMAIN <- "AE"
  expect_equal(operation_bindings_for_rule(list(operations = op("define_variable_is_collected")),
                                           study, "AE", ds)$`$x`$value, "False")
  expect_equal(operation_bindings_for_rule(list(operations = op("define_variable_ccode")),
                                           study, "AE", ds)$`$x`$value, "C1")
  expect_error(operation_bindings_for_rule(list(operations = list(list(
    id = "$x", name = "AENOPE", operator = "define_variable_metadata", attribute_name = "define_variable_ccode"))),
    study, "AE", ds), "has no define_variable_ccode for AENOPE")
})

test_that("the per-value table carries each value's length, and the declared length when known (CORE-002062)", {
  built <- build_variable_value_check_dataset(list(
    data = data.table::data.table(C = c("abc", ""), N = c(10.5, NA)),
    meta = data.table::data.table(variable = c("C", "N"), label = "", type = c("Char", "Num"), length = c(20, 8))
  ))
  expect_equal(built$data$variable_value_length, c(3L, 0L, 3L, NA))
  expect_equal(built$data$variable_length, c(20, 20, 8, 8))
  no_len <- build_variable_value_check_dataset(list(
    data = data.table::data.table(C = "a"), meta = data.table::data.table(variable = "C", label = "", type = "Char")
  ))
  expect_false("variable_length" %in% names(no_len$data))
})


test_that("the bundled FDA guides list is read as the table a 1.0 rule names (CORE-002050)", {
  study <- one_dataset(list(TSVAL = c("QT Studies Therapeutic Area User Guide v1", "Not a guide")), domain = "TS")
  rule <- core1_rule(list(name = "TSVAL", operator = "is_not_contained_by", value = "$fda"),
                     operations = list(list(id = "$fda", operator = "distinct", domain = "cg_taugs",
                                            name = "fda_guides")))
  expect_equal(evaluate_rule(rule, study, "TS"), c(FALSE, TRUE))
})

test_that("get_countries draws on ISO 3166 and GENC as 1.0 does (CORE-002106)", {
  study <- one_dataset(list(COUNTRY = c("USA", "XQZ", "ZZZ")), domain = "DM")
  check <- function(list_name) {
    rule <- core1_rule(list(name = "$codes", operator = "does_not_contain", value = "COUNTRY"),
                       operations = list(list(id = "$codes", operator = "get_countries",
                                              attribute_name = "alpha_3", codelist = list_name)))
    evaluate_rule(rule, study, "DM")
  }
  # XQZ (Akrotiri) is GENC only; "ISO 3166-1" is not a list name there, so
  # it gets ISO plus GENC's extra entries.
  expect_equal(check("GENC"), c(FALSE, FALSE, TRUE))
  expect_equal(check("ISO 3166"), c(FALSE, TRUE, TRUE))
  expect_equal(check("ISO 3166-1"), c(FALSE, FALSE, TRUE))
})

test_that("a 1.0 rule's codelist conditions are all required, Yes/No reading as True/False (CORE-002123)", {
  skip_if(is.null(ct_codelists()), "bundled controlled terminology not installed")
  pkg <- utils::tail(sort(unique(ct_codelists()$package[startsWith(ct_codelists()$package, "sdtmct")])), 1)
  conds <- list(list(Extensible = "No"), list(`Standard Type` = "sdtm"))
  in_core1({
    codes <- ct_package_attribute(pkg, "Codelist Code", conds)
  })
  rows <- ct_codelists()[ct_codelists()$package == pkg, ]
  expect_setequal(codes, rows$codelist_code[rows$extensible == "False"])
})

test_that("MedDRA's latest release at study start is compared with the define's (CORE-002041)", {
  ds <- list(data = data.table::data.table(TSVAL = c("2024-05-01", "2024-10-01", "2019-01-01")), meta = NULL)
  check <- list(name = "TSVAL", operator = "is_not_latest_available_external_dictionary_version",
                external_dictionary_type = "meddra", version = "27.0", value_is_literal = FALSE)
  expect_equal(evaluate_check(check, ds, "TS"), c(FALSE, TRUE, TRUE))
  check$external_dictionary_type <- "whodrug"
  expect_error(evaluate_check(check, ds, "TS"), "no release dates")
})

test_that("a dataset with a define's key variables is checked for unique records, SUPP included (CORE-002007)", {
  ae <- list(data = data.table::data.table(STUDYID = "S", DOMAIN = "AE", USUBJID = "1", AESEQ = 1:3,
                                           AEDECOD = "HEADACHE"), meta = NULL, label = "Adverse Events")
  suppae <- list(data = data.table::data.table(STUDYID = "S", RDOMAIN = "AE", USUBJID = "1", IDVAR = "AESEQ",
                                               IDVARVAL = "2", QNAM = "AETRTEM", QVAL = "Y"), meta = NULL)
  study <- list(datasets = list(AE = ae, SUPPAE = suppae), define = list(
    datasets = data.frame(define_dataset_name = "AE", define_dataset_class = "EVENTS",
                          define_dataset_is_non_standard = FALSE, stringsAsFactors = FALSE),
    variables = data.frame(define_dataset_name = "AE", define_variable_name = c("STUDYID", "USUBJID", "AEDECOD"),
                           define_variable_key_sequence = 1:3, stringsAsFactors = FALSE)
  ))
  built <- build_dataset_contents_against_define(ae, study, "AE")$data
  # Records 1 and 3 match on the keys and both lack a qualifier; record 2 has one.
  expect_equal(built$define_key_sequence_is_unique, c(FALSE, TRUE, FALSE))
  expect_equal(built$define_dataset_class, rep("EVENTS", 3))
})

test_that("a value-level where clause selects records as 1.0 does", {
  data <- data.table::data.table(TSPARMCD = c("ADAPT", "TITLE", "", NA), N = c(1, 2, NA, 3))
  expect_equal(vlm_where_matches(list(list(variable = "TSPARMCD", comparator = "IN",
                                           values = c("ADAPT", "RANDOM"))), data), c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(vlm_where_matches(list(list(variable = "TSPARMCD", comparator = "NE", values = "ADAPT")), data),
               c(FALSE, TRUE, TRUE, TRUE))
  expect_equal(vlm_where_matches(list(list(variable = "N", comparator = "GE", values = "2")), data),
               c(FALSE, TRUE, FALSE, TRUE))
  expect_null(vlm_where_matches(list(list(variable = "NOPE", comparator = "EQ", values = "x")), data))
})

test_that("an STF is read one row per file tag, and is never taken for the define", {
  skip_if_not_installed("xml2")
  dir <- tempfile("stf_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  writeLines(c(
    '<?xml version="1.0"?>',
    '<ectd:study xmlns:ectd="http://www.ich.org/ectd" xmlns:xlink="http://www.w3.org/1999/xlink">',
    '<study-identifier><title>T</title><study-id>S1</study-id></study-identifier>',
    '<study-document>',
    '<doc-content xlink:href="a.xml"><title>A</title><file-tag name="data-tabulation-dataset-sdtm" info-type="ich"/></doc-content>',
    '<doc-content xlink:href="b.xml"><title>B</title></doc-content>',
    '</study-document></ectd:study>'), file.path(dir, "stf.xml"))
  expect_null(find_define_xml(dir))
  stf <- read_stf_xml(find_stf_xml(dir))
  expect_equal(stf$file_tag_name, c("data-tabulation-dataset-sdtm", NA))
  expect_equal(stf$study_id, c("S1", "S1"))
})

test_that("a 1.0 rule takes a dataset's domain from its name when classing it (CORE-000786)", {
  ti <- list(data = data.table::data.table(DOMAIN = "PR", IESCAT = "X"), meta = NULL)
  rule <- core1_rule(list(name = "IESCAT", operator = "exists"),
                     scope = list(Classes = list(Include = "TRIAL DESIGN"), Domains = list(Include = "TI")))
  expect_true(rule_applies_to_domain(rule, "TI", dataset = ti))
  rule$source <- "published"
  expect_false(rule_applies_to_domain(rule, "TI", dataset = ti))
})

test_that("a transport file's declared lengths are read from its header", {
  f <- tempfile(fileext = ".xpt")
  x <- data.frame(A = c("ab", "abcd"), N = 1:2, B = "x")
  attr(x$A, "width") <- 10
  haven::write_xpt(x, f)
  expect_equal(xpt_declared_lengths(f), c(10L, 8L, 1L))
  haven::write_xpt(x, f, version = 8)
  expect_equal(xpt_declared_lengths(f), c(10L, 8L, 1L))
  dir <- tempfile("xptlen_")
  dir.create(dir)
  haven::write_xpt(x, file.path(dir, "dm.xpt"))
  expect_equal(read_study(dir)$datasets$DM$meta$length, c(10, 8, 1))
  unlink(dir, recursive = TRUE)
})

test_that("a declared version is matched however it is written", {
  expect_equal(pick_library_version("3.2", c("3-2", "3-3", "3-4")), "3-2")
  expect_equal(pick_library_version("3-2", c("3-2", "3-4")), "3-2")
  expect_equal(pick_library_version("3.2.0", c("3-2", "3-4")), "3-2")
  expect_equal(pick_library_version(NA_character_, c("3-2", "3-4")), "3-4")
})

test_that("a 1.0 condition naming a missing column is FALSE, never the name as text (CORE-000264)", {
  d <- list(MHBODSYS = c("A", "B"))
  check <- list(name = "MHBODSYS", operator = "not_equal_to", value = "--SOC")
  ds <- list(data = data.table::as.data.table(c(d, DOMAIN = "MH")), meta = NULL)
  expect_equal(in_core1(evaluate_check(check, ds, "MH")), c(FALSE, FALSE))
  # A literal stays a literal, and a pattern is never a column.
  check$value <- "A"
  check$value_is_literal <- TRUE
  expect_equal(in_core1(evaluate_check(check, ds, "MH")), c(FALSE, TRUE))
  pattern <- list(name = "MHBODSYS", operator = "matches_regex", value = "^A")
  expect_equal(in_core1(evaluate_check(pattern, ds, "MH")), c(TRUE, FALSE))
})

test_that("check_study's dataset pre-check agrees with evaluation (CORE-000712, 002050, 002056)", {
  supp <- list(data = data.table::data.table(RDOMAIN = "AE"), meta = NULL)
  r712 <- core1_rule(NULL, operations = list(list(domain = "SUPP--", id = "$v", name = "RDOMAIN",
                                                  operator = "referenced_domain_variable_names")))
  expect_length(rule_external_domains(r712, "SUPPAE", supp), 0)
  r50 <- core1_rule(NULL, operations = list(list(domain = "cg_taugs", id = "$f", name = "fda_guides",
                                                 operator = "distinct")))
  expect_length(rule_external_domains(r50, "TS", NULL), 0)
  r56 <- core1_rule(NULL, operations = list(list(operator = "standard_domains", id = "$td",
                                                 domain_class = "TRIAL DESIGN")))
  expect_length(rule_external_domains(r56, "TS", NULL), 0)
})

test_that("a Study rule is reported once, under STUDY (CORE-002084)", {
  dir <- tempfile("study_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))
  haven::write_xpt(data.frame(STUDYID = "S", DOMAIN = "DM", USUBJID = c("1", "2")), file.path(dir, "dm.xpt"))
  haven::write_xpt(data.frame(STUDYID = "S", DOMAIN = "AE", USUBJID = "1", AESEQ = 1, AETERM = "X"),
                   file.path(dir, "ae.xpt"))
  found <- check_study(dir)$findings
  f <- found[found$rule_id == "CORE-002084", ]
  expect_equal(unique(f$Dataset), "STUDY")
  expect_true(all(is.na(f$Record)))
  expect_equal(nrow(unique(f[, c("Dataset", "Record")])), 1L)
})

test_that("an operation naming a column its dataset lacks is refused, not answered", {
  # Each used to drop the column or give no binding, which the Check read as
  # no violation. CORE 1.0 skips the rule (ColumnNotFoundError).
  ts <- data.table::data.table(STUDYID = "S", TSPARMCD = c("STYPE", "TRT"), TSVAL = c("INTERVENTIONAL", ""))
  study <- list(datasets = list(TS = list(data = ts, meta = NULL)))
  check <- list(all = list(
    list(name = "TSPARMCD", operator = "equal_to", value = "TRT", value_is_literal = TRUE),
    list(name = "$n", operator = "greater_than_or_equal_to", value = 1)
  ))
  grouped <- core1_rule(check, operations = list(list(
    id = "$n", operator = "record_count", group = list("TSGRPID")
  )))
  expect_error(evaluate_rule(grouped, study, "TS"), "groups by TSGRPID")
  filtered <- core1_rule(check, operations = list(list(
    id = "$n", operator = "record_count", filter = list(TSPARMCD = "STYPE", TSCAT = "X")
  )))
  expect_error(evaluate_rule(filtered, study, "TS"), "filters on TSCAT")
  collected <- core1_rule(list(name = "TSVAL", operator = "is_not_contained_by", value = "$v"),
                          operations = list(list(id = "$v", operator = "distinct", name = "TSVALNF")))
  expect_error(evaluate_rule(collected, study, "TS"), "collects the values of TSVALNF")
})

test_that("a grouping column written as a template is the dataset's own, and a set member it lacks is skipped", {
  eg <- data.table::data.table(USUBJID = "1", EGTESTCD = c("HR", "QT"), EGREPNUM = 1)
  study <- list(datasets = list(EG = list(data = eg, meta = NULL)))
  rule <- core1_rule(
    list(name = "$n", operator = "greater_than", value = 1),
    operations = list(
      list(id = "$cols", operator = "map", value = c("VISITDY", "EPOCH")),
      list(id = "$n", operator = "record_count", group = list("USUBJID", "--TESTCD", "$cols"))
    )
  )
  binding <- compute_operation(rule$operations[[2]], study, "EG", study$datasets$EG,
                               list(`$cols` = scalar_binding(c("VISITDY", "EPOCH"))))
  expect_equal(binding$group_cols, c("USUBJID", "EGTESTCD"))
})

test_that("type_insensitive: true compares as text for a CORE 1.0 rule (CORE-000206)", {
  supp <- data.table::data.table(IDVAR = "XXSEQ", XXSEQ = 1, IDVARVAL = c("1", "01", "1.0", " 1"))
  study <- one_dataset(supp)
  check <- list(name = "IDVARVAL", operator = "not_equal_to", value = "IDVAR",
                value_is_reference = TRUE, type_insensitive = TRUE)
  expect_equal(evaluate_rule(core1_rule(check), study, "XX"), c(FALSE, TRUE, TRUE, TRUE))
  # CDISC's engine compares the numbers.
  expect_equal(evaluate_rule(list(check = check), study, "XX"), c(FALSE, FALSE, FALSE, FALSE))
})

test_that("a CORE 1.0 comparison against the column each row names follows 1.0's table", {
  xx <- data.table::data.table(
    IDVAR = c("XXSEQ", "NOPE", "xxseq", "XXSEQ"), XXSEQ = c("1", "1", "1", "1"),
    IDVARVAL = c("1", "2", "2", "")
  )
  check <- list(name = "IDVARVAL", operator = "not_equal_to", value = "IDVAR", value_is_reference = TRUE)
  # Named column found whatever its case; a row naming no column is FALSE;
  # a blank target counts as different only from a blank column.
  expect_equal(evaluate_rule(core1_rule(check), one_dataset(xx), "XX"), c(FALSE, FALSE, TRUE, FALSE))
})

test_that("CORE 1.0's complete date is a shape, and its duration rule allows one decimal", {
  x <- c("2012-11-23", "2012-11-23T10", "2013-02-30", "2012-11-23T10:30", "")
  rule <- core1_rule(list(name = "XXDTC", operator = "is_complete_date"))
  expect_equal(evaluate_rule(rule, one_dataset(list(XXDTC = x)), "XX"), c(TRUE, FALSE, TRUE, TRUE, FALSE))
  # A missing number is not an invalid duration there; blank text is.
  expect_equal(core1_invalid_duration(c("P1.5Y2M", "P1.5Y2.5M", "PT", "P1DT", "-P1D", "", NA)),
               c(FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_false(core1_invalid_duration("-P1D", negative = TRUE))
})

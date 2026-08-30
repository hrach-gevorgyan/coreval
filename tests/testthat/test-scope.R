test_that("pattern_matches_domain handles sentinels, wildcards, and exact codes", {
  expect_true(pattern_matches_domain("ALL", "AE"))
  expect_false(pattern_matches_domain("NONE", "AE"))
  expect_true(pattern_matches_domain("SUPP--", "SUPPAE"))
  expect_true(pattern_matches_domain("SUPP--", "SUPPDM"))
  expect_false(pattern_matches_domain("SUPP--", "AE"))
  expect_true(pattern_matches_domain("AE", "ae"))
  expect_false(pattern_matches_domain("AE", "AG"))
})

test_that("domain_class resolves the static table and the SUPPxx convention", {
  expect_equal(domain_class("AE"), "EVENTS")
  expect_equal(domain_class("LB"), "FINDINGS")
  expect_equal(domain_class("DM"), "SPECIAL PURPOSE")
  expect_equal(domain_class("SUPPAE"), "RELATIONSHIP")
  expect_equal(domain_class("SUPPQUAL"), "RELATIONSHIP")
  expect_true(is.na(domain_class("ZZ")))
})

test_that("class_matches respects Include/Exclude and the ALL sentinel", {
  expect_true(class_matches(list(Include = "ALL"), "AE"))
  expect_true(class_matches(list(Include = "EVENTS"), "AE"))
  expect_false(class_matches(list(Include = "FINDINGS"), "AE"))
  expect_false(class_matches(list(Exclude = "EVENTS"), "AE"))
  expect_true(class_matches(list(Exclude = "FINDINGS"), "AE"))
  expect_true(class_matches(NULL, "AE"))
})

test_that("domains_match respects Include/Exclude, ALL, and prefix wildcards", {
  expect_true(domains_match(list(Include = "ALL"), "AE"))
  expect_true(domains_match(list(Exclude = c("AE", "DS")), "LB"))
  expect_false(domains_match(list(Exclude = c("AE", "DS")), "AE"))
  expect_true(domains_match(list(Include = "SUPP--"), "SUPPAE"))
  expect_false(domains_match(list(Include = "SUPP--"), "AE"))
})

test_that("rule_applies_to_domain combines Classes and Domains as AND, not OR", {
  rule <- list(scope = list(
    Classes = list(Include = "FINDINGS"),
    Domains = list(Include = "ALL")
  ))
  expect_true(rule_applies_to_domain(rule, "LB"))   # FINDINGS domain
  expect_false(rule_applies_to_domain(rule, "AE"))  # EVENTS domain, excluded by Classes

  rule2 <- list(scope = list(
    Classes = list(Include = "ALL"),
    Domains = list(Include = "DM")
  ))
  expect_true(rule_applies_to_domain(rule2, "DM"))
  expect_false(rule_applies_to_domain(rule2, "AE"))
})

test_that("rule_applies_to_domain filters on Use Case only when both sides specify it", {
  rule <- list(scope = list(
    Classes = list(Include = "ALL"),
    Domains = list(Include = "ALL"),
    `Use Case` = "INDH, PROD"
  ))
  expect_true(rule_applies_to_domain(rule, "AE", use_case = "INDH"))
  expect_false(rule_applies_to_domain(rule, "AE", use_case = "NONCLIN"))
  expect_true(rule_applies_to_domain(rule, "AE"))  # no use_case supplied -> not filtered

  rule_no_uc <- list(scope = list(Classes = list(Include = "ALL"), Domains = list(Include = "ALL")))
  expect_true(rule_applies_to_domain(rule_no_uc, "AE", use_case = "INDH"))
})

test_that("rules_for_domain('AE') returns a plausible, real result", {
  r <- rules_for_domain("AE")
  expect_s3_class(r, "data.table")
  expect_true(nrow(r) > 100 && nrow(r) < 250)
  expect_true(all(c("id", "source", "standard") %in% names(r)))
  expect_true(all(r$id %in% list_rules()$id))
})

test_that("rules_for_domain matches SUPPxx domains via the RELATIONSHIP class", {
  r <- rules_for_domain("SUPPAE")
  expect_true(nrow(r) > 0)
})

test_that("sdtm_domain_classes exposes the bundled reference table", {
  tbl <- sdtm_domain_classes()
  expect_s3_class(tbl, "data.table")
  expect_true(nrow(tbl) == 82) # 63 SDTMIG 3.4 + 10 base-SEND + 9 SEND extension-standard additions
  expect_true(all(c("domain", "class") %in% names(tbl)))
})

test_that("dataset_is_split distinguishes a split file from an ordinary or AP dataset", {
  # Split-ness is a property of the DATA (its DOMAIN column), not the name:
  # lbae.csv carrying DOMAIN=LB unsplits to LB, so it IS split.
  split <- list(data = data.table::data.table(DOMAIN = "LB", LBSEQ = 1), meta = NULL)
  expect_true(dataset_is_split(split, "LBAE"))
  expect_equal(dataset_unsplit_name(split, "LBAE"), "LB")

  plain <- list(data = data.table::data.table(DOMAIN = "AE", AESEQ = 1), meta = NULL)
  expect_false(dataset_is_split(plain, "AE"))

  # A SUPP dataset has no DOMAIN of its own; it names its parent in
  # RDOMAIN, so SUPPLB is unsplit but a split SUPPLBAE is not.
  supp <- list(data = data.table::data.table(RDOMAIN = "LB", QNAM = "X"), meta = NULL)
  expect_false(dataset_is_split(supp, "SUPPLB"))
  expect_true(dataset_is_split(supp, "SUPPLBAE"))
})

test_that("include_split_datasets narrows or widens a rule's domain scope", {
  # Per the reference's _is_domain_name_included/_handle_split_domains:
  # TRUE with no Include list means "only split datasets"; FALSE excludes
  # split datasets outright; absent does nothing.
  split <- list(data = data.table::data.table(DOMAIN = "QS", QSSEQ = 1), meta = NULL)
  plain <- list(data = data.table::data.table(DOMAIN = "QS", QSSEQ = 1), meta = NULL)

  only_split <- list(scope = list(Domains = list(include_split_datasets = TRUE)))
  expect_true(rule_applies_to_domain(only_split, "QSCGI", dataset = split))
  expect_false(rule_applies_to_domain(only_split, "QS", dataset = plain))

  no_split <- list(scope = list(Domains = list(
    Include = "ALL", include_split_datasets = FALSE
  )))
  expect_false(rule_applies_to_domain(no_split, "QSCGI", dataset = split))
  expect_true(rule_applies_to_domain(no_split, "QS", dataset = plain))

  # Absent flag: unchanged behaviour for both.
  silent <- list(scope = list(Domains = list(Include = "ALL")))
  expect_true(rule_applies_to_domain(silent, "QSCGI", dataset = split))
  expect_true(rule_applies_to_domain(silent, "QS", dataset = plain))

  # Without a dataset the flag can't be resolved, so it neither narrows
  # nor widens rather than guessing.
  expect_true(rule_applies_to_domain(only_split, "QSCGI"))
})

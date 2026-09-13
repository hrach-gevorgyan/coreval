skip_if_no_jsonata <- function() {
  testthat::skip_if_not(coreval:::jsonata_available(),
                        "QuickJSR and jsonlite are needed to evaluate JSONata")
}

test_that("a JSONata expression is evaluated against a study document", {
  skip_if_no_jsonata()
  rule <- list(rule_type = "JSONata", check = '$.a.b')
  results <- coreval:::evaluate_jsonata_rule(rule, '{"a": {"b": [{"x": 1}, {"x": 2}]}}')
  expect_length(results, 2)
  expect_equal(results[[1]]$x, 1)
})

test_that("every object gets the JSON Pointer the rules report as _path", {
  # The expressions name the record they flag with `_path`, which is not in the
  # source document: the reference stamps it onto every object before
  # evaluating (add_json_pointer_paths). Without it a rule parses, evaluates
  # and returns nothing at all, which reads as a clean study.
  skip_if_no_jsonata()
  rule <- list(rule_type = "JSONata", check = '$.study.versions.{"path": _path}')
  results <- coreval:::evaluate_jsonata_rule(
    rule, '{"study": {"versions": [{"id": "v1"}, {"id": "v2"}]}}')
  expect_equal(vapply(results, function(r) r$path, character(1)),
               c("/study/versions/0", "/study/versions/1"))
})

test_that("CDISC's utility functions are in scope for an expression", {
  # $utils is not part of JSONata. CDISC ships the functions as .jsonata files
  # and glues them onto the front of every expression; a rule calling one
  # against an expression assembled without the prelude fails to parse.
  skip_if_no_jsonata()
  expect_match(coreval:::jsonata_prelude(), "^[$]utils:=[{]")
  expect_match(coreval:::jsonata_prelude(), "sift_tree", fixed = TRUE)
  expect_match(coreval:::jsonata_prelude(), "parse_refs", fixed = TRUE)

  rule <- list(rule_type = "JSONata",
               check = '$utils.sift_tree($.a, "keep", ["keep"], false)')
  expect_no_error(coreval:::evaluate_jsonata_rule(rule, '{"a": {"keep": 1}}'))
})

test_that("an expression that cannot be parsed or evaluated raises", {
  # Returning no findings for a broken expression would be indistinguishable
  # from a study with nothing wrong with it. check_study() turns the error into
  # a SKIPPED row carrying the message.
  skip_if_no_jsonata()
  expect_error(
    coreval:::evaluate_jsonata_rule(list(check = "$.a["), '{"a": 1}'),
    "could not be parsed"
  )
  expect_error(
    coreval:::evaluate_jsonata_rule(list(check = "$.a"), "{not json"),
    "could not be given its study document"
  )
})

test_that("findings carry the path and the attributes the rule chose to report", {
  skip_if_no_jsonata()
  rule <- list(
    rule_type = "JSONata",
    check = '$.study.versions.{"path": _path, "instanceType": "StudyVersion", "name": id}'
  )
  study <- list(document = '{"study": {"versions": [{"id": "v1"}, {"id": "v2"}]}}')
  found <- coreval:::jsonata_findings(rule, study)
  expect_equal(sort(unique(found$path)), c("/study/versions/0", "/study/versions/1"))
  # `instanceType` names the entity and is not itself a reported attribute
  # column; `name` is what the rule chose to report.
  expect_true("name" %in% found$attribute)
  expect_equal(found$value[found$attribute == "name"], c("v1", "v2"))
})

test_that("a JSONata rule refuses a study that is not a USDM document", {
  skip_if_no_jsonata()
  tabular <- list(datasets = list(DM = list(data = data.table::data.table(USUBJID = "1"))))
  expect_error(
    coreval:::jsonata_findings(list(rule_type = "JSONata", check = "$"), tabular),
    "not one"
  )
})

test_that("a folder holding a USDM document is read as one, not as Dataset-JSON", {
  # Both are .json and land in the same folder scan. Read as a Dataset-JSON, a
  # USDM document is refused for declaring no columns, which says nothing about
  # what it actually is.
  dir <- tempfile("coreval_usdm_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines(
    '{"study": {"id": "S1", "versions": []}, "usdmVersion": "4.0"}',
    file.path(dir, "study.json")
  )

  study <- read_study(dir)
  expect_equal(study$standard$product, "USDM")
  expect_equal(study$standard$version, "4.0")
  expect_length(study$datasets, 0)
  expect_match(study$document, "usdmVersion", fixed = TRUE)
})

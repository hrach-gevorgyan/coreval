skip_if_no_json <- function() {
  testthat::skip_if_not(requireNamespace("jsonlite", quietly = TRUE),
                        "jsonlite is needed to read a USDM document")
}

# A miniature study, shaped the way a real one is: a wrapper around a study
# holding versions, each version holding entities, and one key holding another
# entity's id rather than the entity.
tiny_usdm <- function() {
  paste0(
    '{"usdmVersion": "4.0", "study": {"id": "S1", "instanceType": "Study",',
    ' "versions": [{"id": "SV1", "instanceType": "StudyVersion",',
    '   "organizations": [',
    '     {"id": "O1", "instanceType": "Organization", "name": "Alpha",',
    '      "legalAddress": {"id": "A1", "instanceType": "Address", "city": "Ely"}},',
    '     {"id": "O2", "instanceType": "Organization", "name": "Beta",',
    '      "legalAddress": null}],',
    '   "studyIdentifiers": [',
    '     {"id": "SI1", "instanceType": "StudyIdentifier", "scopeId": "O1"}]}]}}'
  )
}

read_tiny <- function() {
  dir <- tempfile("coreval_usdm_")
  dir.create(dir)
  writeLines(tiny_usdm(), file.path(dir, "study.json"))
  on.exit(unlink(dir, recursive = TRUE), add = TRUE, after = FALSE)
  read_study(dir)
}

test_that("a USDM document becomes one table per entity", {
  skip_if_no_json()
  study <- read_tiny()
  expect_true(all(c("ORGANIZATION", "ADDRESS", "STUDYVERSION", "STUDY") %in%
                    names(study$datasets)))
  organizations <- study$datasets$ORGANIZATION$data
  # Two written out in place, plus the one the studyIdentifier points at by id.
  expect_equal(nrow(organizations), 3)
  expect_equal(organizations$name, c("Alpha", "Beta", "Alpha"))
})

test_that("every record says what it hangs off and how", {
  skip_if_no_json()
  organizations <- read_tiny()$datasets$ORGANIZATION$data
  expect_equal(organizations$parent_entity,
               c("StudyVersion", "StudyVersion", "StudyIdentifier"))
  expect_equal(organizations$parent_id, c("SV1", "SV1", "SI1"))
  expect_equal(organizations$parent_rel,
               c("organizations", "organizations", "scopeId"))
  # A key ending in Id that resolves to a real object is a reference to it, not
  # a second definition of it. Rules turn on the difference constantly.
  expect_equal(organizations$rel_type, c("definition", "definition", "reference"))
  expect_equal(organizations[["_path"]],
               c("/study/versions/0/organizations/0",
                 "/study/versions/0/organizations/1",
                 "/study/versions/0/studyIdentifiers/0/scopeId"))
})

test_that("a nested object is flattened into dotted columns and a presence flag", {
  skip_if_no_json()
  organizations <- read_tiny()$datasets$ORGANIZATION$data
  # The object's own column says only whether it holds anything; its contents
  # arrive as `legalAddress.<key>`. A JSON null is carried through as missing
  # rather than as FALSE: the reference turns an object or an array into a
  # presence flag and leaves every other value alone, so "there is no address"
  # and "there is an empty address" stay different statements.
  expect_equal(organizations$legalAddress, c(TRUE, NA, TRUE))
  expect_equal(organizations$`legalAddress.city`, c("Ely", "", "Ely"))
})

test_that("an id that resolves to nothing stays a plain value", {
  # A dangling reference is data, not a crash: the record keeps the id as its
  # value and stays a definition. `exists()` on an id is also an error rather
  # than FALSE when the id is blank, which used to abort the whole flatten and
  # silently drop entities from the study.
  skip_if_no_json()
  dir <- tempfile("coreval_usdm_dangling_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines(paste0(
    '{"usdmVersion": "4.0", "study": {"id": "S1", "instanceType": "Study",',
    ' "versions": [{"id": "SV1", "instanceType": "StudyVersion",',
    '   "studyIdentifiers": [{"id": "SI1", "instanceType": "StudyIdentifier",',
    '     "scopeId": "nobody"}, {"id": "SI2", "instanceType": "StudyIdentifier",',
    '     "scopeId": ""}]}]}}'
  ), file.path(dir, "study.json"))

  study <- read_study(dir)
  expect_false("ORGANIZATION" %in% names(study$datasets))
  identifiers <- study$datasets$STUDYIDENTIFIER$data
  expect_equal(nrow(identifiers), 2)
  expect_equal(identifiers$scopeId, c("nobody", ""))
})

test_that("the entity map is read without raising on a key it does not carry", {
  # entities[[key]] raises "subscript out of bounds" on a named character
  # vector rather than returning NULL, and most keys in a real document are not
  # in the map at all.
  entities <- c(epochId = "StudyEpoch")
  expect_equal(coreval:::entity_lookup(entities, "epochId"), "StudyEpoch")
  expect_true(is.na(coreval:::entity_lookup(entities, "somethingElse")))
  expect_true(is.na(coreval:::entity_lookup(entities, NA_character_)))
})

test_that("the traversal visits an object's own keys before descending", {
  # The reference walks with `$..*`, where `*` matches an object's keys and
  # nothing on an array. So a node contributes its own keys first and only then
  # each child's, which is neither breadth- nor depth-first. The order fixes
  # which record number a finding is reported against.
  skip_if_no_json()
  doc <- jsonlite::fromJSON(
    '{"a": {"x": 1, "y": {"z": 2}}, "b": 3}', simplifyVector = FALSE)
  paths <- vapply(coreval:::usdm_traversal(doc), function(n) n$path, character(1))
  expect_equal(paths, c("a", "b", "a.x", "a.y", "a.y.z"))
})

test_that("a document with no jsonlite still reads, without tables", {
  # jsonlite is a Suggests. Without it the document is still carried, so the
  # JSONata rules run; the tabular rules find nothing in scope and skip.
  skip_if_no_json()
  study <- read_tiny()
  expect_type(study$document, "character")
  expect_match(study$document, "usdmVersion", fixed = TRUE)
})

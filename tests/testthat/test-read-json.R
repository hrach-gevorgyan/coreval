# Dataset-JSON and Dataset-NDJSON.
#
# The central test is round-trip equivalence, not a comparison against an
# expected answer: CDISC publishes no Dataset-JSON reference data, so there is
# no answer sheet to grade against. Writing the same study as XPT and as
# Dataset-JSON and requiring check_study() to return the same findings is a
# stronger test anyway. A reader that drops a row, shifts a column or mistypes
# one makes the two disagree, and it needs nothing shipped by anyone else.

sample_dm <- function() {
  data.frame(
    STUDYID = rep("S1", 6),
    DOMAIN = rep("DM", 6),
    USUBJID = sprintf("S1-%03d", 1:6),
    AGE = c(34, 51, NA, 67, 29, NA),
    AGEU = rep("YEARS", 6),
    SEX = c("F", "M", "U", "F", "M", "F"),
    # A bad month, an empty value and a partial date: the three things the date
    # rules exist to find, so the comparison is not made on clean data only.
    RFSTDTC = c("2024-01-15", "2024-13-01", "", "2024-02", "2024-03-01", "2024-04-01"),
    stringsAsFactors = FALSE
  )
}

# Writes `df` as Dataset-JSON (whole = TRUE) or Dataset-NDJSON.
write_dataset_json <- function(df, path, name = "DM", whole = TRUE,
                               records = nrow(df)) {
  types <- vapply(df, function(col) {
    if (is.character(col)) "string" else "decimal"
  }, character(1))
  columns <- lapply(names(df), function(v) {
    list(itemOID = paste0("IT.", name, ".", v), name = v, label = v,
         dataType = types[[v]])
  })
  rows <- lapply(seq_len(nrow(df)), function(i) {
    lapply(names(df), function(v) {
      value <- df[[v]][i]
      # JSON null, which is what a missing value is in this format.
      if (is.na(value)) NULL else if (is.character(value)) value else as.numeric(value)
    })
  })
  header <- list(
    datasetJSONCreationDateTime = "2026-01-01T00:00:00",
    datasetJSONVersion = "1.1.0", itemGroupOID = paste0("IG.", name),
    name = name, label = paste(name, "dataset"), records = records,
    columns = columns
  )
  as_json <- function(x) {
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  }
  if (whole) {
    header$rows <- rows
    writeLines(as_json(header), path)
  } else {
    writeLines(c(as_json(header), vapply(rows, as_json, character(1))), path)
  }
  invisible(path)
}

test_that("a study read as Dataset-JSON gives the same findings as the same study as XPT", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("haven")

  dm <- sample_dm()
  root <- tempfile("coreval_json_")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  xpt <- file.path(root, "xpt")
  js <- file.path(root, "json")
  nd <- file.path(root, "ndjson")
  for (d in c(xpt, js, nd)) dir.create(d)

  haven::write_xpt(dm, file.path(xpt, "dm.xpt"))
  write_dataset_json(dm, file.path(js, "dm.json"), whole = TRUE)
  write_dataset_json(dm, file.path(nd, "dm.ndjson"), whole = FALSE)

  fingerprint <- function(dir) {
    result <- check_study(dir, standard = "SDTMIG", version = "3.4")
    found <- result$findings
    list(
      checks = as.integer(attr(result, "checks_run")),
      keys = sort(paste(found$Dataset, found$Record, found$Variable,
                        found$rule_id, sep = "|"))
    )
  }
  from_xpt <- fingerprint(xpt)
  from_json <- fingerprint(js)
  from_ndjson <- fingerprint(nd)

  # Not just the same count. The same findings, on the same rows, from the
  # same rules: a shifted column keeps the count and changes the rows.
  expect_identical(from_json$keys, from_xpt$keys)
  expect_identical(from_ndjson$keys, from_xpt$keys)
  expect_identical(from_json$checks, from_xpt$checks)
  expect_identical(from_ndjson$checks, from_xpt$checks)
  expect_gt(length(from_xpt$keys), 0)
})

test_that("Dataset-JSON types, labels, nulls and declared name are read", {
  skip_if_not_installed("jsonlite")
  dm <- sample_dm()
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  write_dataset_json(dm, path, name = "DM")

  ds <- read_dataset_json(path)
  expect_equal(nrow(ds$data), 6)
  expect_equal(names(ds$data), names(dm))
  expect_equal(ds$label, "DM dataset")
  expect_identical(attr(ds, "dataset_name"), "DM")

  # A declared numeric column stays numeric and its JSON nulls stay NA.
  expect_true(is.numeric(ds$data$AGE))
  expect_equal(sum(is.na(ds$data$AGE)), 2)
  # A character column's blank is "", not NA, matching every other reader here.
  expect_identical(ds$data$RFSTDTC[3], "")
  expect_equal(ds$meta$type[ds$meta$variable == "AGE"], "Num")
  expect_equal(ds$meta$type[ds$meta$variable == "RFSTDTC"], "Char")
})

test_that("a date is read as text, so partial dates survive", {
  skip_if_not_installed("jsonlite")
  df <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = "S1-001",
                   RFSTDTC = "2024-02", stringsAsFactors = FALSE)
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  # Declared as a date, which the reader must still hand over as the original
  # string: converting it would lose the partial dates the rules look for.
  types_as_date <- function(df, path) {
    columns <- lapply(names(df), function(v) {
      list(itemOID = paste0("IT.DM.", v), name = v, label = v,
           dataType = if (v == "RFSTDTC") "date" else "string")
    })
    obj <- list(datasetJSONCreationDateTime = "2026-01-01T00:00:00",
                datasetJSONVersion = "1.1.0", itemGroupOID = "IG.DM",
                name = "DM", label = "DM", records = 1L, columns = columns,
                rows = list(as.list(unname(as.character(df[1, ])))))
    writeLines(as.character(jsonlite::toJSON(obj, auto_unbox = TRUE)), path)
  }
  types_as_date(df, path)

  ds <- read_dataset_json(path)
  expect_true(is.character(ds$data$RFSTDTC))
  expect_identical(ds$data$RFSTDTC, "2024-02")
})

test_that("a malformed or incomplete Dataset-JSON is refused, not read as empty", {
  skip_if_not_installed("jsonlite")

  # Ragged rows. The reference returns an empty data frame when a file fails
  # schema validation, which reads as a dataset with no problems in it.
  ragged <- tempfile(fileext = ".json")
  writeLines(paste0(
    '{"datasetJSONCreationDateTime":"2026-01-01T00:00:00",',
    '"datasetJSONVersion":"1.1.0","itemGroupOID":"IG.DM","name":"DM",',
    '"label":"DM","records":2,"columns":[',
    '{"itemOID":"a","name":"USUBJID","label":"U","dataType":"string"},',
    '{"itemOID":"b","name":"AGE","label":"A","dataType":"integer"}],',
    '"rows":[["S1-001",34],["S1-002"]]}'), ragged)
  on.exit(unlink(ragged), add = TRUE)
  expect_error(read_dataset_json(ragged), "malformed")

  # A truncated transfer: the file says how many records it holds, and holds
  # fewer. Reading it anyway reports clean for every row that never arrived.
  short <- tempfile(fileext = ".json")
  on.exit(unlink(short), add = TRUE)
  write_dataset_json(sample_dm(), short, records = 500L)
  expect_error(read_dataset_json(short), "incomplete")

  # Not JSON at all.
  junk <- tempfile(fileext = ".json")
  on.exit(unlink(junk), add = TRUE)
  writeLines("this is not json {{{", junk)
  expect_error(read_dataset_json(junk), "not valid JSON")

  # No columns declared.
  bare <- tempfile(fileext = ".json")
  on.exit(unlink(bare), add = TRUE)
  writeLines('{"name":"DM","label":"DM","records":0,"columns":[]}', bare)
  expect_error(read_dataset_json(bare), "declares no columns")
})

test_that("an empty Dataset-JSON is a dataset with no rows, not an error", {
  skip_if_not_installed("jsonlite")
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeLines(paste0(
    '{"datasetJSONCreationDateTime":"2026-01-01T00:00:00",',
    '"datasetJSONVersion":"1.1.0","itemGroupOID":"IG.DM","name":"DM",',
    '"label":"DM","records":0,"columns":[',
    '{"itemOID":"a","name":"USUBJID","label":"U","dataType":"string"},',
    '{"itemOID":"b","name":"AGE","label":"A","dataType":"integer"}],',
    '"rows":[]}'), path)

  ds <- read_dataset_json(path)
  expect_equal(nrow(ds$data), 0)
  expect_equal(names(ds$data), c("USUBJID", "AGE"))
  expect_true(is.numeric(ds$data$AGE))
})

test_that("read_study prefers XPT when a folder holds both formats", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("haven")
  dir <- tempfile("coreval_both_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  # Deliberately different row counts, so which reader ran is unambiguous.
  haven::write_xpt(sample_dm()[1:2, ], file.path(dir, "dm.xpt"))
  write_dataset_json(sample_dm(), file.path(dir, "dm.json"))

  study <- read_study(dir)
  expect_equal(nrow(study$datasets$DM$data), 2)
})

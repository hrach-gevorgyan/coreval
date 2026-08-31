demo_ae <- function() {
  data.frame(
    STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
    AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
    AESTDTC = c("2024-01-10", "2024-02-30"), # 30 February is not a date
    stringsAsFactors = FALSE
  )
}

test_that("check_dataset finds a violation in a plain in-memory data frame", {
  result <- check_dataset(demo_ae())

  expect_true(all(c("findings", "skipped") %in% names(result)))
  # Same column contract as check_study(), so write_findings() works on either.
  expect_equal(
    names(result$findings),
    c("Dataset", "Record", "Variable", "Value", "issue", "rule_id")
  )
  expect_equal(names(result$skipped), c("rule_id", "domain", "reason"))

  bad_date <- result$findings[result$findings$Value == "2024-02-30", ]
  expect_equal(bad_date$rule_id, "CORE-000547") # the ISO 8601 rule
  # `issue` is the whole point: a row saying only "CORE-000547" cannot be
  # acted on without looking the rule up somewhere else.
  expect_match(bad_date$issue, "ISO 8601")
  expect_equal(bad_date$Dataset, "AE")
  expect_equal(bad_date$Record, 2L)
  expect_equal(bad_date$Variable, "AESTDTC")
})

test_that("a rule needing another domain is skipped with that domain named, never evaluated", {
  # This is the whole safety story of single-dataset checking. apply_match()
  # returns the dataset unchanged when a referenced domain is absent, so a
  # cross-domain rule left to run would compare against columns that do not
  # exist and could report a confident finding built out of nothing.
  result <- check_dataset(demo_ae())

  cross <- result$skipped[grepl("was not supplied", result$skipped$reason), ]
  expect_true(nrow(cross) > 0)
  expect_match(cross$reason[1], "^needs [A-Z]+")

  # CORE-000138 joins DM. It must appear as skipped, naming DM, and must NOT
  # contribute a single finding.
  expect_true("CORE-000138" %in% cross$rule_id)
  expect_match(cross$reason[cross$rule_id == "CORE-000138"], "needs DM")
  expect_false("CORE-000138" %in% result$findings$rule_id)
})

test_that("check_study is unaffected: a whole study still runs its cross-domain rules", {
  # The refusal above applies to single-dataset checks only. A study that
  # genuinely has no SUPPAE or RELREC must still evaluate rules referencing
  # them, exactly as the reference engine does, so check_study() keeps its
  # forgiving behaviour.
  dir <- test_path("fixtures", "core_rules", "CORE-000001", "negative", "01")
  study <- read_study(file.path(dir, "data"))
  result <- check_study(study)
  expect_false(any(grepl("was not supplied", result$skipped$reason)))
})

test_that("the domain comes from the DOMAIN column, not the file name", {
  # A split dataset lives in ae1.xpt but still carries DOMAIN == "AE", and the
  # rules are written against AE.
  dir <- tempfile("coreval_split_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- file.path(dir, "ae1.xpt")
  haven::write_xpt(demo_ae(), path)

  result <- check_dataset(path)
  # "STUDY" is the sentinel a Domain Presence Check reports under, so the
  # assertion is that no OTHER domain appears - not that AE is the only value.
  expect_setequal(setdiff(unique(result$findings$Dataset), "STUDY"), "AE")
})

test_that("the domain falls back to the file name when there is no DOMAIN column", {
  dir <- tempfile("coreval_nodomain_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- file.path(dir, "dm.xpt")
  haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), path)

  result <- check_dataset(path)
  expect_true(nrow(result$skipped) > 0)
  expect_equal(unique(result$skipped$domain), "DM")
})

test_that("an explicit domain= overrides both", {
  df <- data.frame(USUBJID = c("1", "2"), stringsAsFactors = FALSE)
  result <- check_dataset(df, domain = "vs")
  expect_equal(unique(result$skipped$domain), "VS") # normalised to upper case
})

test_that("check_dataset refuses input it cannot make sense of, with a usable message", {
  # More than one DOMAIN value: silently checking only the first would report
  # findings for rows the user did not think they were checking.
  mixed <- data.frame(DOMAIN = c("AE", "CM"), USUBJID = c("1", "2"), stringsAsFactors = FALSE)
  expect_error(check_dataset(mixed), "more than one value")

  # No DOMAIN column and no file name to fall back on.
  expect_error(check_dataset(data.frame(USUBJID = "1")), "pass domain=")

  expect_error(check_dataset(123), "data frame")
  expect_error(check_dataset("no-such-file.xpt"), "file not found")

  dir <- tempfile("coreval_folder_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  expect_error(check_dataset(dir), "read_study")

  bad <- file.path(dir, "data.parquet")
  writeLines("x", bad)
  expect_error(check_dataset(bad), "\\.xpt")
})

test_that("rule_external_domains expands templates, reads Child parents, and drops self", {
  # "SUPP--" carries a TRAILING --, expanded off the domain being checked.
  # resolve_var_name() handles the LEADING form used by variable names and
  # would leave this as the literal text "SUPP--", which then looks like a
  # domain of that name.
  supp_rule <- list(match_datasets = list(list(Name = "SUPP--")))
  expect_equal(rule_external_domains(supp_rule, "LB"), "SUPPLB")

  # A named join is literal, and the domain being checked is not "external"
  # to itself.
  self_rule <- list(match_datasets = list(list(Name = "SV"), list(Name = "AE")))
  expect_equal(rule_external_domains(self_rule, "AE"), "SV")

  # A Child spec names the CHILD - the dataset in hand - and joins each row
  # to the parent named in its own RDOMAIN, so the dependency lives in the
  # data.
  child_rule <- list(match_datasets = list(list(Child = TRUE, Name = "SUPP--")))
  child_data <- list(data = data.table::data.table(RDOMAIN = c("AE", "CM", "AE")))
  expect_setequal(rule_external_domains(child_rule, "SUPPAE", child_data), c("AE", "CM"))

  # With no data to read, say the parent is unknown rather than name a domain
  # that was never referenced.
  expect_match(rule_external_domains(child_rule, "SUPPAE"), "RDOMAIN")

  # An Operations block naming a domain counts too.
  expect_equal(rule_external_domains(.coreval_env$data$rules[["CORE-000036"]], "TA"), "TV")

  # A rule that references nothing external needs nothing external.
  expect_length(rule_external_domains(.coreval_env$data$rules[["CORE-000547"]], "AE"), 0)
})

test_that("check_dataset reads a csv, and a data.table, as well as a data frame", {
  dir <- tempfile("coreval_csv_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- file.path(dir, "ae.csv")
  utils::write.csv(demo_ae(), path, row.names = FALSE)

  from_csv <- check_dataset(path)
  expect_true("2024-02-30" %in% from_csv$findings$Value)

  from_dt <- check_dataset(data.table::as.data.table(demo_ae()))
  expect_true("2024-02-30" %in% from_dt$findings$Value)
})

test_that("write_findings works on a check_dataset() result unchanged", {
  result <- check_dataset(demo_ae())
  dir <- tempfile("coreval_out_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  written <- write_findings(result, file.path(dir, "issues.csv"))
  expect_length(written, 2)
  expect_true(all(file.exists(written)))
})

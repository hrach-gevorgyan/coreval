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
    c("Dataset", "Record", "Variable", "Value", "issue", "triage", "rule_id")
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
  # findings + skipped + about; nothing was capped here, so no `truncated`.
  expect_length(written, 3)
  expect_true(all(file.exists(written)))
})

test_that("factor columns are checked, not crashed on", {
  # read.csv(stringsAsFactors = TRUE) and older code hand over factors. A
  # factor is text to every rule but an integer vector underneath, so
  # nzchar()/startsWith() on one is an ERROR, not a wrong answer - the whole
  # check died with "'nzchar()' requires a character vector".
  as_factors <- data.frame(
    STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
    AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
    AESTDTC = c("2024-01-10", "2024-02-30"),
    stringsAsFactors = TRUE
  )
  result <- expect_no_error(check_dataset(as_factors))
  expect_true("2024-02-30" %in% result$findings$Value)

  # And it must agree with the same data as character.
  as_chars <- as_factors
  as_chars[] <- lapply(as_chars, function(col) {
    if (is.factor(col)) as.character(col) else col
  })
  expect_setequal(
    unique(result$findings$rule_id),
    unique(check_dataset(as_chars)$findings$rule_id)
  )
})

test_that("a trailing blank in DOMAIN does not silently change the answer", {
  # "AE " is not the domain "AE". Untrimmed it scoped to a domain of that
  # name, ran a different rule set, and reported a different number of
  # findings with no warning - and it resolved "--STDTC" to "AE STDTC", a
  # column nothing has, so every "--" rule quietly found nothing.
  padded <- data.frame(
    STUDYID = "S1", DOMAIN = "AE ", USUBJID = c("01", "01"),
    AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
    AESTDTC = c("2024-01-10", "2024-02-30"), stringsAsFactors = FALSE
  )
  clean <- padded
  clean$DOMAIN <- "AE"

  a <- check_dataset(padded)
  b <- check_dataset(clean)

  # Same domain, so the same rules are in scope.
  expect_equal(unique(a$findings$Dataset), unique(b$findings$Dataset))

  # The "--"-templated date rule must fire on the padded copy too. Untrimmed,
  # "--STDTC" resolved to "AE STDTC" and it found nothing.
  expect_true("2024-02-30" %in% a$findings$Value)

  # Nothing is LOST to the padding: every rule the clean copy finds, the
  # padded one finds too. That is the property that matters - a silently
  # smaller result was the bug.
  expect_true(all(unique(b$findings$rule_id) %in% unique(a$findings$rule_id)))

  # The padded copy legitimately finds MORE, because a trailing space in
  # DOMAIN is itself a conformance problem and several rules say so. Those are
  # true positives about the data, not an artefact of the fix.
  extra <- setdiff(unique(a$findings$rule_id), unique(b$findings$rule_id))
  expect_true(length(extra) > 0)
  expect_true(any(grepl("DOMAIN|Domain", a$findings$issue[a$findings$rule_id %in% extra])))
})

test_that("an empty or row-less dataset says which situation it is", {
  # "no single DOMAIN value" reads as "your DOMAIN column is inconsistent" to
  # someone whose column is simply empty, or who has no rows yet.
  no_rows <- data.frame(
    STUDYID = character(0), DOMAIN = character(0), USUBJID = character(0)
  )
  expect_error(check_dataset(no_rows), "no rows")

  all_blank <- data.frame(DOMAIN = c("", ""), USUBJID = c("1", "2"), stringsAsFactors = FALSE)
  expect_error(check_dataset(all_blank), "blank")

  # Both should still name the way out.
  expect_error(check_dataset(no_rows), "domain=")
  expect_error(check_dataset(all_blank), "domain=")

  # And an explicit domain makes a row-less dataset checkable.
  expect_no_error(check_dataset(no_rows, domain = "DM"))
})

test_that("declaring a standard scopes the rules to it", {
  # Before this, `standard=` was accepted and silently ignored: declaring
  # SDTMIG gave byte-identical results to declaring nothing, while 73 of DM's
  # 270 in-scope rules were SENDIG-only.
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02"),
    RFSTDTC = c("2024-01-05", "2024-13-01"), AGE = c(34, 61),
    AGEU = c("YEARS", ""), SEX = c("M", "F"), stringsAsFactors = FALSE
  )
  sdtm <- check_dataset(dm, standard = "SDTMIG")
  send <- check_dataset(dm, standard = "SENDIG")
  open <- check_dataset(dm)

  # Declaring one runs strictly fewer rules than declaring none.
  n <- function(r) attr(r, "checks_run") + nrow(r$skipped)
  expect_lt(n(sdtm), n(open))
  expect_lt(n(send), n(open))

  # The same defect is written up once per standard. Declaring the standard
  # picks the right one instead of reporting both.
  expect_true("CORE-000189" %in% sdtm$findings$rule_id)   # SDTMIG, TIG
  expect_false("CORE-000883" %in% sdtm$findings$rule_id)  # SENDIG only
  expect_true("CORE-000883" %in% send$findings$rule_id)
  expect_false("CORE-000189" %in% send$findings$rule_id)

  # Matched exactly: a SENDIG study must not pick up SENDIG-DART rules.
  dart_only <- vapply(.coreval_env$data$rules, function(r) {
    identical(sort(toupper(r$standards)), "SENDIG-DART")
  }, logical(1))
  expect_false(any(names(which(dart_only)) %in% send$findings$rule_id))
})

test_that("deprecated rules are dropped by default and can be asked for", {
  # A deprecated rule has a published replacement, so running both reports the
  # same defect twice. CORE-000452 is the deprecated twin of CORE-000189.
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02"),
    RFSTDTC = c("2024-01-05", "2024-13-01"), AGE = c(34, 61),
    AGEU = c("YEARS", ""), SEX = c("M", "F"), stringsAsFactors = FALSE
  )
  expect_false("CORE-000452" %in% check_dataset(dm)$findings$rule_id)
  expect_true("CORE-000452" %in% check_dataset(dm, include_deprecated = TRUE)$findings$rule_id)

  # rules_for_domain follows the same default.
  expect_false("CORE-000452" %in% rules_for_domain("DM")$id)
  expect_true("CORE-000452" %in% rules_for_domain("DM", include_deprecated = TRUE)$id)
})

test_that("the report says when no standard was declared", {
  # Silently measuring an SDTM study against SENDIG rules is how one defect
  # came to be reported twice; the reader has to know that happened.
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = "01",
    AGE = 34, AGEU = "", SEX = "M", stringsAsFactors = FALSE
  )
  open <- paste(capture.output(print(check_dataset(dm))), collapse = "\n")
  expect_match(open, "No standard declared")
  expect_match(open, "SDTMIG")

  named <- paste(capture.output(print(check_dataset(dm, standard = "SDTMIG"))), collapse = "\n")
  expect_false(grepl("No standard declared", named))
})

test_that("declaring an IG version narrows further than the standard alone", {
  # Rules are written per Implementation Guide version: 408 SDTMIG rules exist
  # for 3.2 against 445 for 3.4, and 86 apply to exactly one version. Without
  # this a 3.2 study is measured against rules written for a guide it does not
  # follow. `version=` was accepted and ignored, the same way `standard=` was.
  n_rules <- function(...) nrow(rules_for_domain("DM", ...))

  any_version <- n_rules(standard = "SDTMIG")
  v32 <- n_rules(standard = "SDTMIG", version = "3.2")
  v34 <- n_rules(standard = "SDTMIG", version = "3.4")

  expect_lt(v32, any_version)
  expect_lt(v34, any_version)
  # The guide grew, so a later version carries more rules.
  expect_lt(v32, v34)

  # A CORE test case writes "3-4" in its .env while the rules say "3.4"; the
  # caller should not have to know which form to use.
  expect_equal(
    n_rules(standard = "SDTMIG", version = "3-4"),
    n_rules(standard = "SDTMIG", version = "3.4")
  )

  # Version without a standard does nothing: "3.4" alone is ambiguous across
  # SDTMIG, SENDIG-DART and the rest.
  expect_equal(n_rules(version = "3.4"), n_rules())
})

test_that("check_dataset passes the declared version through to scoping", {
  dm <- data.frame(
    STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02"),
    RFSTDTC = c("2024-01-05", "2024-13-01"), AGE = c(34, 61),
    AGEU = c("YEARS", ""), SEX = c("M", "F"), stringsAsFactors = FALSE
  )
  ran <- function(r) attr(r, "checks_run") + nrow(r$skipped)

  expect_lt(
    ran(check_dataset(dm, standard = "SDTMIG", version = "3.2")),
    ran(check_dataset(dm, standard = "SDTMIG"))
  )
})

test_that("every rule records which IG versions it was written for", {
  rules <- .coreval_env$data$rules
  expect_true(all(vapply(rules, function(r) length(r$standard_versions) > 0, logical(1))))

  # The pair is "NAME VERSION", so one %in% answers both questions.
  v <- rules[["CORE-000189"]]$standard_versions
  expect_true("SDTMIG 3.4" %in% v)
  expect_true(all(grepl("^(SDTMIG|SENDIG|TIG|ADaMIG)", v)))
})

test_that("check_study takes a folder path, so read_study is optional", {
  # Requiring read_study() first made people call two functions to do one
  # thing. The object form still works, for re-checking a large study without
  # re-reading it.
  dir <- tempfile("coreval_path_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  haven::write_xpt(demo_ae(), file.path(dir, "ae.xpt"))

  from_path <- check_study(dir)
  from_object <- check_study(read_study(dir))
  expect_identical(from_path$findings, from_object$findings)
  expect_identical(from_path$skipped, from_object$skipped)

  # A file is not a folder, and the message should point at the right function.
  expect_error(check_study(file.path(dir, "ae.xpt")), "check_dataset")
  expect_error(check_study("no-such-folder"), "no such folder")
  expect_error(check_study(c("a", "b")), "one folder path")
})

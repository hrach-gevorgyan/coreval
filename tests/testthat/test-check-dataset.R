demo_ae <- function() {
  data.frame(
    STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
    AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
    AESTDTC = c("2024-01-10", "2024-02-30"), # 30 February is not a date
    stringsAsFactors = FALSE
  )
}

test_that("check_dataset finds a violation in a plain in-memory data frame", {
  result <- check_dataset(demo_ae(), standard = "SDTMIG")

  expect_true(all(c("findings", "skipped") %in% names(result)))
  # Same column contract as check_study(), so write_findings() works on either.
  expect_equal(
    names(result$findings),
    c("Dataset", "Record", "USUBJID", "SEQ", "Variable", "Value", "issue",
      "triage", "rule_id")
  )
  expect_equal(names(result$skipped), c("rule_id", "domain", "reason"))

  # CORE 1.0's CORE-002121 is SDTM's ISO 8601 rule. It checks every date
  # variable's value through a variable_name/variable_value table, and the
  # finding is reported as the variable itself.
  bad_date <- result$findings[result$findings$Value == "2024-02-30" &
                                result$findings$rule_id == "CORE-002121", ]
  expect_equal(bad_date$rule_id, "CORE-002121")
  # `issue` is the whole point: a row saying only "CORE-002121" cannot be
  # acted on without looking the rule up somewhere else.
  expect_match(bad_date$issue, "ISO 8601")
  expect_equal(bad_date$Dataset, "AE")
  expect_equal(bad_date$Record, 2L)
  # Found by subject and sequence number, as a programmer looks a record up.
  expect_equal(bad_date$USUBJID, "01")
  expect_equal(bad_date$SEQ, 2)
  expect_equal(bad_date$Variable, "AESTDTC")
  expect_false(any(result$findings$Variable %in% c("variable_name", "variable_value")))
  # So asking for the variable finds it.
  expect_true("CORE-002121" %in% filter_findings(result, variable = "AESTDTC")$findings$rule_id)
})

test_that("a per-value finding is reported as the variable it is about", {
  f <- data.table::data.table(
    Dataset = "AE", Record = c(1L, 1L, 1L, 1L, 2L, 2L),
    Variable = rep(c("variable_name", "variable_value"), 3),
    Value = c("AESTDTC", "2024-02-30", "AEENDTC", "", "AESTDTC", "x")
  )
  out <- fold_value_rows(data.table::copy(f))
  expect_equal(out$Variable, c("AESTDTC", "AEENDTC", "AESTDTC"))
  expect_equal(out$Value, c("2024-02-30", "", "x"))
  expect_equal(out$Record, c(1L, 1L, 2L))
  # Anything else on the finding stays with it.
  g <- data.table::data.table(Dataset = "DM", Record = 3L,
                              Variable = c("USUBJID", "variable_name", "variable_value"),
                              Value = c("07", "RFSTDTC", "2024-13-01"))
  expect_equal(fold_value_rows(g)$Variable, c("USUBJID", "RFSTDTC"))
  # A rule with no value column is left alone.
  h <- data.table::data.table(Dataset = "DM", Record = NA, Variable = "variable_name",
                              Value = "TOOLONGNAME")
  expect_identical(fold_value_rows(h), h)
})

test_that("USUBJID and SEQ come from the record a finding names, and stay blank otherwise", {
  ae <- list(data = data.table::as.data.table(demo_ae()), meta = NULL)
  record_rule <- list(rule_type = "Record Data")
  f <- data.table::data.table(Dataset = "AE", Record = c(2L, 1L, NA),
                              Variable = "AESTDTC", Value = "x")
  out <- add_record_keys(data.table::copy(f), ae, "AE", record_rule)
  expect_equal(names(out)[1:4], c("Dataset", "Record", "Variable", "Value"))
  expect_equal(out$USUBJID, c("01", "01", NA))
  expect_equal(out$SEQ, c(2, 1, NA))

  # A metadata rule's Record numbers a row of the metadata table, not a
  # record, so naming the subject on that row would point at the wrong thing.
  meta <- add_record_keys(data.table::copy(f), ae, "AE",
                          list(rule_type = "Variable Metadata Check"))
  expect_true(all(is.na(meta$USUBJID)) && all(is.na(meta$SEQ)))

  # A dataset with no --SEQ (DM) still gives the subject.
  dm <- list(data = data.table::data.table(DOMAIN = "DM", USUBJID = "07"), meta = NULL)
  one <- add_record_keys(f[1][, Record := 1L], dm, "DM", record_rule)
  expect_equal(one$USUBJID, "07")
  expect_true(is.na(one$SEQ))
})

test_that("a rule needing another domain is skipped with that domain named, never evaluated", {
  # This is the whole safety story of single-dataset checking. apply_match()
  # returns the dataset unchanged when a referenced domain is absent, so a
  # cross-domain rule left to run would compare against columns that do not
  # exist and could report a confident finding built out of nothing.
  result <- check_dataset(demo_ae(), standard = "SDTMIG")

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
  result <- check_study(study, standard = "SDTMIG")
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

  result <- check_dataset(path, standard = "SDTMIG")
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

  result <- check_dataset(path, standard = "SDTMIG")
  expect_true(nrow(result$skipped) > 0)
  expect_equal(unique(result$skipped$domain), "DM")
})

test_that("an explicit domain= overrides both", {
  df <- data.frame(USUBJID = c("1", "2"), stringsAsFactors = FALSE)
  result <- check_dataset(df, domain = "vs", standard = "SDTMIG")
  expect_equal(unique(result$skipped$domain), "VS") # normalised to upper case
})

test_that("check_dataset refuses input it cannot make sense of, with a usable message", {
  # More than one DOMAIN value: silently checking only the first would report
  # findings for rows the user did not think they were checking.
  mixed <- data.frame(DOMAIN = c("AE", "CM"), USUBJID = c("1", "2"), stringsAsFactors = FALSE)
  expect_error(check_dataset(mixed, standard = "SDTMIG"), "more than one value")

  # No DOMAIN column and no file name to fall back on.
  expect_error(check_dataset(data.frame(USUBJID = "1"), standard = "SDTMIG"), "pass domain=")

  expect_error(check_dataset(123, standard = "SDTMIG"), "data frame")
  expect_error(check_dataset("no-such-file.xpt", standard = "SDTMIG"), "file not found")

  dir <- tempfile("coreval_folder_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  # Points at check_study(), which takes the folder directly. It used to say
  # "read_study() then check_study()", which was advice from before that
  # simplification.
  expect_error(check_dataset(dir, standard = "SDTMIG"), "use check_study()", fixed = TRUE)

  bad <- file.path(dir, "data.parquet")
  writeLines("x", bad)
  expect_error(check_dataset(bad, standard = "SDTMIG"), "\\.xpt")
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
  expect_equal(rule_external_domains(fixture_rule("CORE-000036"), "TA"), "TV")

  # A rule that references nothing external needs nothing external.
  expect_length(rule_external_domains(fixture_rule("CORE-000547"), "AE"), 0)
})

test_that("a CORE 1.0 distinct over an unsupplied domain is needed, not empty (CORE-000172)", {
  r <- core1_rule(NULL, operations = list(list(domain = "DM", id = "$dm_studyid",
                                               name = "STUDYID", operator = "distinct")))
  # One dataset: DM was not supplied, so the rule cannot be answered.
  expect_equal(rule_external_domains(r, "AE"), "DM")
  # A whole study without DM: 1.0's engine answers with an empty set.
  expect_length(rule_external_domains(r, "AE", child = FALSE), 0)

  ae <- data.frame(STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "02"),
                   AESEQ = c(1, 1), AETERM = c("Headache", "Rash"))
  result <- check_dataset(ae, standard = "SDTMIG")
  expect_false("CORE-000172" %in% result$findings$rule_id)
  expect_match(result$skipped$reason[result$skipped$rule_id == "CORE-000172"],
               "needs DM, which was not supplied")
})

test_that("check_dataset reads a csv, and a data.table, as well as a data frame", {
  dir <- tempfile("coreval_csv_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  path <- file.path(dir, "ae.csv")
  utils::write.csv(demo_ae(), path, row.names = FALSE)

  from_csv <- check_dataset(path, standard = "SDTMIG")
  expect_true("2024-02-30" %in% from_csv$findings$Value)

  from_dt <- check_dataset(data.table::as.data.table(demo_ae()), standard = "SDTMIG")
  expect_true("2024-02-30" %in% from_dt$findings$Value)
})

test_that("write_findings works on a check_dataset() result unchanged", {
  result <- check_dataset(demo_ae(), standard = "SDTMIG")
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
  result <- expect_no_error(check_dataset(as_factors, standard = "SDTMIG"))
  expect_true("2024-02-30" %in% result$findings$Value)

  # And it must agree with the same data as character.
  as_chars <- as_factors
  as_chars[] <- lapply(as_chars, function(col) {
    if (is.factor(col)) as.character(col) else col
  })
  expect_setequal(
    unique(result$findings$rule_id),
    unique(check_dataset(as_chars, standard = "SDTMIG")$findings$rule_id)
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

  a <- check_dataset(padded, standard = "SDTMIG")
  b <- check_dataset(clean, standard = "SDTMIG")

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
  expect_error(check_dataset(no_rows, standard = "SDTMIG"), "no rows")

  all_blank <- data.frame(DOMAIN = c("", ""), USUBJID = c("1", "2"), stringsAsFactors = FALSE)
  expect_error(check_dataset(all_blank, standard = "SDTMIG"), "blank")

  # Both should still name the way out.
  expect_error(check_dataset(no_rows, standard = "SDTMIG"), "domain=")
  expect_error(check_dataset(all_blank, standard = "SDTMIG"), "domain=")

  # And an explicit domain makes a row-less dataset checkable.
  expect_no_error(check_dataset(no_rows, domain = "DM", standard = "SDTMIG"))
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

  # Each sets aside the rules written for other standards.
  expect_gt(attr(sdtm, "excluded_by_standard"), 0)
  expect_gt(attr(send, "excluded_by_standard"), 0)

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
  # A deprecated rule has a current replacement, so running both reports the
  # same defect twice. CORE-000742 is deprecated in CDISC's repository and not
  # carried by CORE 1.0. (CORE-000452, the example here before, was in CDISC's
  # Deprecated folder only while it was parked there; 1.0 publishes it.)
  ts <- data.frame(
    STUDYID = "S1", DOMAIN = "TS", TSSEQ = 1, TSPARMCD = "INDIC",
    TSPARM = "Trial Disease/Condition Indication", TSVAL = "",
    TSVALNF = "UNK", stringsAsFactors = FALSE
  )
  expect_false("CORE-000742" %in% rules_for_domain("TS")$id)
  expect_true("CORE-000742" %in% rules_for_domain("TS", include_deprecated = TRUE)$id)
  ran <- function(...) {
    r <- check_dataset(ts, ..., standard = "SDTMIG")
    unique(c(r$findings$rule_id, r$skipped$rule_id))
  }
  expect_false("CORE-000742" %in% ran())
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

  from_path <- check_study(dir, standard = "SDTMIG")
  from_object <- check_study(read_study(dir), standard = "SDTMIG")
  expect_identical(from_path$findings, from_object$findings)
  expect_identical(from_path$skipped, from_object$skipped)

  # A file is not a folder, and the message should point at the right function.
  expect_error(check_study(file.path(dir, "ae.xpt"), standard = "SDTMIG"), "check_dataset")
  expect_error(check_study("no-such-folder", standard = "SDTMIG"), "no such folder")
  expect_error(check_study(c("a", "b"), standard = "SDTMIG"), "one folder path")
})

test_that("a single CSV is read with the same protections as a folder of them", {
  dir <- tempfile("coreval_csv_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  write_lines <- function(name, lines) {
    path <- file.path(dir, name)
    writeLines(lines, path)
    path
  }
  # A short last row was dropped as a footer, without an error.
  expect_error(read_csv_dataset(write_lines("short.csv", c(
    "STUDYID,DOMAIN,USUBJID,AETERM", "S1,AE,1,Rash", "S1,AE,2,Head", "S1,AE,3"
  ))), "could not read all of")
  # Extra values on every row shifted every column one place right.
  expect_error(read_csv_dataset(write_lines("extra.csv", c(
    "STUDYID,DOMAIN,USUBJID,AETERM", "S1,AE,1,Rash,x", "S1,AE,2,Head,y"
  ))), "more values than the header")
  # A stray space in the header hid the variable.
  spaced <- read_csv_dataset(write_lines("spaced.csv", c("STUDYID ,AETERM ", "S1 ,Rash ")))
  expect_equal(names(spaced), c("STUDYID", "AETERM"))
  expect_equal(spaced$AETERM, "Rash ")
  # A doubled quote inside a quoted field is one quote.
  quoted <- read_csv_dataset(write_lines("quoted.csv", c("STUDYID,AETERM", 'S1,"Rash ""severe"""')))
  expect_equal(quoted$AETERM, 'Rash "severe"')
  # A semicolon-separated file is still read.
  semi <- read_csv_dataset(write_lines("semi.csv", c("STUDYID;AETERM", "S1;Rash, mild")))
  expect_equal(semi$AETERM, "Rash, mild")
})

test_that("a CSV header ending in a comma is not taken for a row with too many values", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  writeLines(c("STUDYID,USUBJID,AETERM,", "S,1,HEADACHE,", "S,2,NAUSEA,"), path)
  expect_equal(nrow(read_csv_dataset(path)), 2)
  tab <- tempfile(fileext = ".csv")
  on.exit(unlink(tab), add = TRUE)
  writeLines(c("STUDYID\tUSUBJID\tAETERM", "S\t1\tRash, mild"), tab)
  expect_equal(ncol(read_csv_dataset(tab)), 3)
})

test_that("a bare CSV keeps text that is not a plain number as text (CORE-000867)", {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  utils::write.csv(data.frame(STUDYID = "S", DOMAIN = "LB", LBORRES = c(" 5", "6"),
                              X = c("0x1A", "1e3"), N = c("1", "2.5")), f, row.names = FALSE)
  dt <- read_csv_dataset(f)
  expect_identical(dt$LBORRES, c(" 5", "6"))
  expect_identical(dt$X, c("0x1A", "1e3"))
  expect_identical(dt$N, c(1, 2.5))
})

test_that("a one-column CSV with spaces in its values is read whole", {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  writeLines(c("AETERM", "HEAD ACHE", "BACK PAIN"), f)
  dt <- read_csv_dataset(f)
  expect_identical(names(dt), "AETERM")
  expect_identical(dt$AETERM, c("HEAD ACHE", "BACK PAIN"))
})

test_that("domain= that contradicts the DOMAIN column is refused", {
  dm <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = c("1", "2"))
  expect_error(check_dataset(dm, domain = "AE", standard = "SDTMIG"), "DOMAIN column says DM")
  lb <- data.frame(STUDYID = "S1", DOMAIN = "LB", USUBJID = "1", LBSEQ = 1)
  expect_s3_class(check_dataset(lb, domain = "LB1", standard = "SDTMIG"), "coreval_result")
})

test_that("a rule about the whole study is skipped on one dataset (CORE-002084, CORE-002056)", {
  dm <- data.frame(STUDYID = "S1", DOMAIN = "DM", USUBJID = c("01", "02"))
  result <- check_dataset(dm, standard = "SDTMIG")
  expect_false(any(c("CORE-002084", "CORE-002056") %in% result$findings$rule_id))
  expect_match(result$skipped$reason[result$skipped$rule_id == "CORE-002084"][1],
               "whole study")
})

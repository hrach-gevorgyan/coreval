test_that("distinct (ungrouped) matches CDISC's reference results.csv - cross-dataset binding", {
  # CORE-000036: $tv_visit = distinct VISIT values from the TV dataset,
  # used to check SV.VISIT is_not_contained_by $tv_visit. Needs the full
  # study (TV and SV are different datasets) - the exact case that pushed
  # evaluate_rule() to accept a study, not just one dataset.
  rule <- .coreval_env$data$rules[["CORE-000036"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000036", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "SV")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "SV", nrow(study$datasets$SV$data))
    )
  }
})

test_that("record_count (grouped, filtered) matches CDISC's reference results.csv", {
  # CORE-000214: $disposition_event_count = record_count of DS rows where
  # DSCAT == "DISPOSITION EVENT", grouped by [USUBJID, EPOCH] - a grouped
  # binding joined back onto each row of the same (DS) dataset.
  rule <- .coreval_env$data$rules[["CORE-000214"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000214", case, "01")
    study <- read_study(file.path(dir, "data"))
    actual <- evaluate_rule(rule, study, domain = "DS")
    expect_equal(
      actual,
      expected_violations_for(file.path(dir, "results", "results.csv"), "DS", nrow(study$datasets$DS$data))
    )
  }
})

test_that("evaluate_rule accepts a plain dataset (no Operations) as before", {
  # Backward compatibility: passing list(data=, meta=) directly, without a
  # $datasets wrapper, must keep working for rules with no Operations.
  data <- data.table::data.table(A = c("X", "Y"))
  dataset <- list(data = data, meta = NULL)
  rule <- list(check = list(name = "A", operator = "equal_to", value = "X", value_is_literal = TRUE))
  expect_equal(evaluate_rule(rule, dataset, "TS"), c(TRUE, FALSE))
})

test_that("compute_operation: distinct excludes blank/NA and sorts", {
  study <- list(datasets = list(TV = list(
    data = data.table::data.table(VISIT = c("WEEK 2", "SCREENING", "", "SCREENING")),
    meta = NULL
  )))
  op <- list(domain = "TV", id = "$v", name = "VISIT", operator = "distinct")
  binding <- compute_operation(op, study, "TV", study$datasets$TV)
  expect_equal(binding$kind, "scalar")
  expect_equal(binding$value, c("SCREENING", "WEEK 2"))
})

test_that("compute_operation: record_count with a filter and no grouping is a single count", {
  study <- list(datasets = list(DS = list(
    data = data.table::data.table(DSCAT = c("DISPOSITION EVENT", "OTHER", "DISPOSITION EVENT")),
    meta = NULL
  )))
  op <- list(domain = "DS", id = "$n", name = "DSCAT", operator = "record_count", filter = list(DSCAT = "DISPOSITION EVENT"))
  binding <- compute_operation(op, study, "DS", study$datasets$DS)
  expect_equal(binding$kind, "scalar")
  expect_equal(binding$value, 2)
})

test_that("compute_operation: record_count grouped joins back per-row via resolve_binding", {
  ds_data <- data.table::data.table(
    USUBJID = c("S1", "S1", "S2"),
    EPOCH = c("A", "A", "A"),
    DSCAT = c("DISPOSITION EVENT", "OTHER", "OTHER")
  )
  study <- list(datasets = list(DS = list(data = ds_data, meta = NULL)))
  op <- list(
    domain = "DS", id = "$n", name = "DSCAT", operator = "record_count",
    group = c("USUBJID", "EPOCH"), filter = list(DSCAT = "DISPOSITION EVENT")
  )
  binding <- compute_operation(op, study, "DS", study$datasets$DS)
  expect_equal(binding$kind, "grouped")
  resolved <- resolve_binding(binding, study$datasets$DS)
  expect_equal(resolved, c(1, 1, 0))
})

test_that("compute_dy returns NA (not a crash) for a USUBJID with no matching DM record", {
  # Bug: `rfstdtc_by_subject[[usubjid[i]]]` on an atomic named vector errors
  # ("subscript out of bounds") for a name that isn't present, instead of
  # returning NULL like list indexing would - crashing the whole `dy`
  # computation for the entire dataset instead of yielding NA for that row.
  study <- list(datasets = list(
    DM = list(data = data.table::data.table(USUBJID = "S1", RFSTDTC = "2024-01-01"), meta = NULL),
    AE = list(data = data.table::data.table(USUBJID = c("S1", "S2"), AESTDTC = c("2024-01-05", "2024-01-05")), meta = NULL)
  ))
  op <- list(domain = "AE", id = "$dy", name = "AESTDTC", operator = "dy")
  binding <- compute_operation(op, study, "AE", study$datasets$AE)
  expect_equal(binding$kind, "per_row")
  expect_equal(binding$value, c(5, NA_real_))
})

test_that("compute_dy resolves a '--'-templated name against the CURRENT domain, not an empty string", {
  # Bug: compute_dy() didn't receive current_domain at all, so
  # resolve_var_name(op$name, "") turned "--STDTC" into "STDTC" instead of
  # "CMSTDTC" - the target column never existed, so $val_stdy was always
  # NA. Confirmed against CORE-000552's real fixture.
  study <- list(datasets = list(
    DM = list(data = data.table::data.table(USUBJID = "S1", RFSTDTC = "2024-01-01"), meta = NULL),
    CM = list(data = data.table::data.table(USUBJID = "S1", CMSTDTC = "2024-01-05"), meta = NULL)
  ))
  op <- list(id = "$val_stdy", name = "--STDTC", operator = "dy")
  binding <- compute_operation(op, study, "CM", study$datasets$CM)
  expect_equal(binding$kind, "per_row")
  expect_equal(binding$value, 5)
})

test_that("not_equal_to/equal_to matches CDISC's reference results.csv across the --DY/dy Operations family (CORE-000436/CORE-000529/CORE-000552/CORE-000553)", {
  for (id in c("CORE-000436", "CORE-000529", "CORE-000552", "CORE-000553")) {
    rule <- .coreval_env$data$rules[[id]]
    for (case in c("negative", "positive")) {
      cases <- fixture_cases(id, case)
      for (dir in cases) {
        study <- read_study(file.path(dir, "data"))
        results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
        for (domain in names(study$datasets)) {
          if (!rule_applies_to_domain(rule, domain)) next
          actual <- which(evaluate_rule(rule, study, domain))
          expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
          expect_equal(sort(unname(actual)), expected, info = paste(id, dir, domain))
        }
      }
    }
  }
})

test_that("not_equal_to leaves an unresolvable Operations aggregate's blank comparator unforced (CORE-000454)", {
  # An all-blank EXENDTC column makes max_date's $max_ex_exendtc binding
  # genuinely unresolvable (NA), not "blank" in the same sense as a
  # per-row column value that's simply missing - forcing not_equal_to TRUE
  # here would wrongly flag RFXENDTC as violating just because the
  # AGGREGATE had nothing to aggregate. Confirmed against CORE-000454's
  # real fixture (negative/02: EXENDTC blank on every row).
  rule <- .coreval_env$data$rules[["CORE-000454"]]
  for (case in c("negative", "positive")) {
    cases <- fixture_cases("CORE-000454", case)
    for (dir in cases) {
      study <- read_study(file.path(dir, "data"))
      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      for (domain in names(study$datasets)) {
        if (!rule_applies_to_domain(rule, domain)) next
        actual <- which(evaluate_rule(rule, study, domain))
        expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
        expect_equal(sort(unname(actual)), expected, info = paste(dir, domain))
      }
    }
  }
})

test_that("resolve_binding does not collide grouped-join keys across a multi-column boundary", {
  # Bug: pasting group columns together with no separator lets ("1", "23")
  # and ("12", "3") key to the same string "123", joining the wrong group's
  # aggregate onto a row.
  ds_data <- data.table::data.table(A = c("1", "12"), B = c("23", "3"))
  study <- list(datasets = list(DS = list(data = ds_data, meta = NULL)))
  table <- data.table::data.table(A = c("1", "12"), B = c("23", "3"), .value = c(10, 20))
  binding <- grouped_binding(c("A", "B"), table, ".value")
  expect_equal(resolve_binding(binding, study$datasets$DS), c(10, 20))
})

test_that("resolve_binding returns NULL (unresolvable), not a literal-NA vector, when the current dataset lacks the join column", {
  # A grouped-by-USUBJID binding computed from SV, applied to a domain like
  # TV that has no USUBJID column at all, can't be joined - it's
  # unresolvable, not "NA for every row". Returning NULL lets
  # guarded_op()'s `is.null(ctx$value)` guard make the whole condition NA,
  # rather than a literal-NA vector that downstream membership operators
  # (is_contained_by/is_not_contained_by) would wrongly treat as a real
  # (never-matching) value set - confirmed against CORE-000168's real
  # fixtures, where this bug flagged every row of the TV domain.
  ds_data <- data.table::data.table(VISITNUM = c(1, 2))
  dataset <- list(data = ds_data, meta = NULL)
  table <- data.table::data.table(USUBJID = "1", .value = list(c(1, 2)))
  binding <- grouped_binding("USUBJID", table, ".value")
  expect_null(resolve_binding(binding, dataset))
})

test_that("is_not_contained_by matches CDISC's reference results.csv across every applicable domain (CORE-000168)", {
  rule <- .coreval_env$data$rules[["CORE-000168"]]
  for (case in c("negative", "positive")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000168", case, "01")
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- which(evaluate_rule(rule, study, domain))
      expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
      expect_equal(sort(unname(actual)), expected, info = paste(case, domain))
    }
  }
})

test_that("domain_label matches CDISC's reference results.csv (CORE-000219)", {
  # "--SCAT equal_to_case_insensitive $domain_label" - the dataset's own
  # label (from _datasets.csv's Label column / an XPT dataset label), not
  # a per-variable label.
  rule <- .coreval_env$data$rules[["CORE-000219"]]
  for (case in c("negative/01", "negative/02", "positive/01", "positive/02")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000219", case)
    study <- read_study(file.path(dir, "data"))
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual <- which(evaluate_rule(rule, study, domain))
      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
      expect_equal(sort(unname(actual)), expected)
    }
  }
})

test_that("read_study captures each dataset's own label", {
  dir <- tempfile("coreval_label_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines("Filename,Label\ndm,Demographics", file.path(dir, "_datasets.csv"))
  writeLines("dataset,variable,label,type,length\nDM,USUBJID,Subject,Char,20", file.path(dir, "_variables.csv"))
  writeLines("USUBJID\n1", file.path(dir, "dm.csv"))
  study <- read_study(dir)
  expect_equal(study$datasets$DM$label, "Demographics")
})

test_that("expected_variables matches CDISC's reference results.csv (CORE-000334), version-aware", {
  # "variable_name not_contains_all $expected_variables" - the positive
  # fixture declares SDTMIG 3.4, the negative fixture SDTMIG 3.3, so this
  # also exercises picking the study's OWN declared version rather than
  # always defaulting to the newest.
  rule <- .coreval_env$data$rules[["CORE-000334"]]
  for (case in c("negative/01", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000334", case)
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in names(study$datasets)) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual_any <- any(evaluate_rule(rule, study, domain))
      expected_any <- nrow(results[results$Dataset == domain, ]) > 0
      expect_equal(actual_any, expected_any)
    }
  }
})

test_that("not_contains_all against an unresolvable $required_variables binding is NA, not a forced violation (CORE-000355)", {
  # Bug: contains_all() hard-coded FALSE when its value was unresolvable
  # (NULL) - e.g. $required_variables against a SENDIG-declared study,
  # which sdtmig_variables_for() deliberately refuses to guess for. Its
  # negation, not_contains_all, then came out TRUE (a fabricated
  # violation) for every domain the rule couldn't actually evaluate.
  # CORE-000355's own AE/LB/TA domains (all resolvable, all genuinely
  # compliant) now correctly report no violation; only EX still mismatches,
  # because it's genuinely missing a required SENDIG variable that this
  # package has no SENDIG variable-metadata to detect (a separate, already
  # documented gap - see sdtmig_variables_for()'s own docs).
  rule <- .coreval_env$data$rules[["CORE-000355"]]
  for (case in c("negative/01", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000355", case)
    study <- read_study(file.path(dir, "data"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    for (domain in setdiff(names(study$datasets), "EX")) {
      if (!rule_applies_to_domain(rule, domain)) next
      actual_any <- any(evaluate_rule(rule, study, domain))
      expected_any <- nrow(results[results$Dataset == domain, ]) > 0
      expect_equal(actual_any, expected_any, info = paste(case, domain))
    }
  }
})

test_that("sdtmig_variables_for resolves SUPPxx datasets via the SUPPQUAL template", {
  study <- list(standard = list(product = "SDTMIG", version = "3-4"))
  vars <- sdtmig_variables_for(study, "SUPPAE", "Exp")
  expect_setequal(vars, c("IDVAR", "IDVARVAL", "QEVAL"))
})

test_that("sdtmig_variables_for uses the study's OWN declared standard, not always SDTMIG", {
  # A test case that looks SDTM-flavoured need not be SDTMIG: CORE-000355's
  # EX fixture declares SENDIG 3.1. This used to return NULL for any
  # non-SDTMIG study - correct in that it refused to guess, but it meant
  # SEND studies could not be checked at all. Now the declared standard is
  # honoured, and the two genuinely differ: SENDIG's EX has no USUBJID
  # among its required variables, SDTMIG's does.
  sendig <- list(standard = list(product = "SENDIG", version = "3-1"))
  sendig_vars <- sdtmig_variables_for(sendig, "EX", "Req")
  expect_true(all(c("EXTRT", "EXROUTE") %in% sendig_vars))
  expect_false("USUBJID" %in% sendig_vars)

  sdtmig <- list(standard = list(product = "SDTMIG", version = "3-4"))
  expect_true("USUBJID" %in% sdtmig_variables_for(sdtmig, "EX", "Req"))
})

test_that("sdtmig_variables_for defaults to the newest NUMBERED version when none is declared", {
  study <- list(standard = list(product = NA_character_, version = NA_character_))
  vars <- sdtmig_variables_for(study, "EX", "Req")
  expect_true("EXTRT" %in% vars)
})

test_that("newest_library_version ignores appendix variants and compares numerically", {
  # The cache holds appendix variants keyed by name alongside the numbered
  # releases, so a plain max() picks "md-1-1" over "3-4" and silently
  # selects an appendix's variable list as the newest SDTMIG.
  expect_equal(
    newest_library_version(c("3-1-2", "3-1-3", "3-2", "3-3", "3-4", "ap-1-0", "md-1-1")),
    "3-4"
  )
  # Component-wise, so 3-10 is newer than 3-4 (string comparison says otherwise).
  expect_equal(newest_library_version(c("3-4", "3-10")), "3-10")
  # Only appendix-style versions available: fall back rather than fail.
  expect_equal(newest_library_version(c("ap-1-0", "md-1-1")), "md-1-1")
})

test_that("get_model_column_order matches CDISC's reference results.csv (CORE-000550)", {
  # "variable_name is_not_contained_by $allowed_variables" - $allowed_variables
  # is the full set of variable names the SDTM Model allows for the domain's
  # observation class (including inherited base-class variables).
  rule <- .coreval_env$data$rules[["CORE-000550"]]
  for (case in c("negative/01", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000550", case)
    study <- read_study(file.path(dir, "data"))
    for (domain in c("AE", "EG", "LB")) { # DM/APEG need IG-specific (not Model) variable data - not covered here
      if (!(domain %in% names(study$datasets)) || !rule_applies_to_domain(rule, domain)) next
      actual <- which(evaluate_rule(rule, study, domain))
      results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
      expected <- sort(unique(as.integer(results$Record[results$Dataset == domain])))
      expect_equal(sort(unname(actual)), expected)
    }
  }
})

test_that("get_model_column_order falls back to per-dataset Model variables for a class with no modeled variables", {
  # Special-Purpose/Relationship/Trial Design/Study Reference classes have no
  # generic class-level variable list in the Model - each domain in them (DM,
  # RELREC, TA, ...) defines its own bespoke variables instead. This used to
  # return NULL, which silently found nothing on DM: CORE-000550's invalid
  # ARMCDXX went unreported. The Model's per-dataset list is the answer, and
  # is where the reference engine reads it from too.
  study <- list(datasets = list(DM = list(data = data.table::data.table(A = 1), meta = NULL)))
  op <- list(domain = "DM", id = "$allowed", operator = "get_model_column_order")
  binding <- compute_operation(op, study, "DM", study$datasets$DM)
  expect_true("ARMCD" %in% binding$value)
  expect_false("ARMCDXX" %in% binding$value)
})

test_that("get_model_column_order returns NULL (unresolvable) for a domain the Model does not describe", {
  # NULL is still the honest answer where the Model says nothing at either
  # level: an empty allowed-set would make is_not_contained_by flag every
  # variable in the dataset as disallowed.
  study <- list(datasets = list(ZZ = list(data = data.table::data.table(A = 1), meta = NULL)))
  op <- list(domain = "ZZ", id = "$allowed", operator = "get_model_column_order")
  expect_null(compute_operation(op, study, "ZZ", study$datasets$ZZ))
})

test_that("get_model_column_order allows an Associated Persons dataset its AP variables", {
  # APEG is Findings (like EG) plus the variables that make it an AP dataset:
  # APID, RSUBJID, SREL. Without them coreval flagged all three as disallowed
  # and missed the variable that really was not in the Model.
  study <- list(datasets = list(
    APEG = list(data = data.table::data.table(APID = "1", RSUBJID = "2", SREL = "3"), meta = NULL)
  ))
  op <- list(domain = "APEG", id = "$allowed", operator = "get_model_column_order")
  binding <- compute_operation(op, study, "APEG", study$datasets$APEG)
  expect_true(all(c("APID", "RSUBJID", "SREL") %in% binding$value))
})

test_that("study_domains/dataset_names/variable_exists/domain_is_custom are local, no Library needed", {
  study <- list(datasets = list(
    AE = list(data = data.table::data.table(DOMAIN = "AE", AETERM = "X", AESCAN = "Y"), meta = NULL),
    ZZ = list(data = data.table::data.table(DOMAIN = "ZZ", A = 1), meta = NULL)
  ))
  # study_domains reads each dataset's DOMAIN value, not its name - see the
  # dedicated test below for why the distinction matters.
  expect_equal(compute_operation(list(id = "$d", operator = "study_domains"), study, "AE", study$datasets$AE)$value, c("AE", "ZZ"))
  expect_true(compute_operation(list(id = "$e", name = "AESCAN", operator = "variable_exists"), study, "AE", study$datasets$AE)$value)
  expect_false(compute_operation(list(id = "$e2", name = "NOPE", operator = "variable_exists"), study, "AE", study$datasets$AE)$value)
  expect_false(compute_operation(list(id = "$c", operator = "domain_is_custom"), study, "AE", study$datasets$AE)$value)
  expect_true(compute_operation(list(id = "$c2", operator = "domain_is_custom"), study, "ZZ", study$datasets$ZZ)$value)
})

test_that("dataset_names is UPPERCASE, matching the reference engine's own Filename.upper() convention", {
  # An earlier version used tolower() - an unverified assumption, contradicted
  # directly by CORE-000539/CORE-000540's own reference results.csv, whose
  # reported $list_dataset_names values are uppercase (e.g. "['QS1', 'QSAE']",
  # "['FA', 'FA1', 'FACM']") - traced to csv_metadata_reader.py's own
  # `str(single_match["Filename"]).upper()`.
  study <- list(datasets = list(qs1 = list(data = data.table::data.table(A = 1), meta = NULL)))
  expect_equal(compute_operation(list(id = "$d", operator = "dataset_names"), study, "qs1", study$datasets$qs1)$value, "QS1")
})

test_that("prefix_is_not_contained_by correctly identifies a missing parent domain (CORE-000539/CORE-000540)", {
  for (id in c("CORE-000539", "CORE-000540")) {
    rule <- .coreval_env$data$rules[[id]]
    for (polarity in c("negative", "positive")) {
      case_dirs <- fixture_cases(id, polarity)
      for (dir in case_dirs) {
        study <- read_study(file.path(dir, "data"))
        results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
        for (domain in names(study$datasets)) {
          if (!rule_applies_to_domain(rule, domain)) next
          actual <- evaluate_rule(rule, study, domain)
          expected_any <- nrow(results[results$Dataset == domain, ]) > 0
          expect_equal(any(actual), expected_any, info = paste(id, dir, domain))
        }
      }
    }
  }
})

test_that("an Operations filter value ending in \"&\" is a prefix wildcard, not a literal", {
  # The reference engine's _is_wildcard_pattern()/_apply_wildcard_filter()
  # (base_operation.py) route a filter value ending in "&" to
  # series.str.startswith(value.rstrip("&"), na=False); only a non-"&"
  # value falls through to the plain `== value` comparison. Read
  # literally, "RACE&" matches nothing at all, which silently collapses a
  # record_count to 0 rather than erroring.
  dt <- data.table::data.table(
    QNAM = c("RACE1", "RACE2", "RACEOTH", "ETHNIC", NA_character_),
    QVAL = c("a", "b", "c", "d", "e")
  )
  expect_equal(apply_operation_filter(dt, list(QNAM = "RACE&"))$QVAL, c("a", "b", "c"))
  # a value without the "&" suffix stays an exact-equality match
  expect_equal(apply_operation_filter(dt, list(QNAM = "RACE1"))$QVAL, "a")
  # na=False on the Python side: a blank cell is a non-match, never an
  # NA that propagates into the row index and drops the row silently
  expect_equal(apply_operation_filter(dt, list(QNAM = "ETHNIC"))$QVAL, "d")
})

test_that("a \"&\" prefix-wildcard filter matches CDISC's reference results.csv (CORE-000846)", {
  # $suppdm_race_count counts SUPPDM rows per USUBJID whose QNAM starts
  # with "RACE". positive/01 has subjects with 3 and 2 such rows, so
  # neither violates "less_than_or_equal_to 1"; a literal "RACE&" match
  # finds 0 rows for everyone and wrongly flags both. negative/01 passed
  # even with the bug only by accident (its true counts are 1 and 1).
  rule <- .coreval_env$data$rules[["CORE-000846"]]
  for (case in c("negative/01", "positive/01")) {
    dir <- test_path("fixtures", "core_rules", "CORE-000846", case)
    study <- read_study(file.path(dir, "data"))
    actual <- which(evaluate_rule(rule, study, domain = "DM"))
    results <- data.table::fread(file.path(dir, "results", "results.csv"), colClasses = "character")
    expected <- sort(unique(as.integer(results$Record[results$Dataset == "DM"])))
    expect_equal(sort(unname(actual)), expected, info = case)
  }
})

test_that("valid_codelist_dates lists CDISC's published CT package dates, filtered by type", {
  # Only the package DATES are bundled, not the terminology - the full CT
  # term data is ~438 MB, which is a separate data package's problem. The
  # dates are all this operation needs: CORE-000761 flags a TS record whose
  # TSVCDVER cites a CT version CDISC never published.
  study <- list(datasets = list(TS = list(data = data.table::data.table(X = 1), meta = NULL)))
  op <- list(operator = "valid_codelist_dates", id = "$valid_dates", ct_package_types = "SDTM")
  b <- compute_operation(op, study, "TS", study$datasets$TS)
  dates <- resolve_binding(b, study$datasets$TS)

  expect_true(length(dates) > 10)
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dates)))
  expect_false(is.unsorted(dates))

  # SDTM and SEND happen to share release dates - CDISC publishes them
  # together - so this asserts both resolve, not that they differ.
  op_send <- utils::modifyList(op, list(ct_package_types = "SEND"))
  send_dates <- resolve_binding(compute_operation(op_send, study, "TS", study$datasets$TS), study$datasets$TS)
  expect_true(length(send_dates) > 10)

  # An unknown type resolves to nothing rather than silently falling back
  # to every date, which would make the check vacuously pass.
  op_bad <- utils::modifyList(op, list(ct_package_types = "NOT-A-STANDARD"))
  expect_null(compute_operation(op_bad, study, "TS", study$datasets$TS))
})

test_that("standard_variable_order merges the IG into the Model's skeleton, positionally", {
  # This is the standard's expected variable ORDER, and it is neither source
  # read alone. The Model supplies a skeleton in three sections - General
  # Observations identifiers, the class's own variables, then General
  # Observations timing - and each IG variable either replaces a Model
  # variable of the same name (keeping its position) or is inserted at its
  # section's boundary. Order is the whole point: CORE-000852 asks whether a
  # dataset's column order is an ordered subset of this.
  study <- list(standard = list(product = "SDTMIG", version = "3-4"))
  cm <- list(data = data.table::data.table(DOMAIN = "CM"), meta = NULL)
  order_cm <- standard_variable_order(study, "CM", cm)

  expect_true(all(c("STUDYID", "USUBJID", "CMTRT", "CMDTC", "CMSTDTC") %in% order_cm))
  # Identifiers lead.
  expect_lt(match("USUBJID", order_cm), match("CMTRT", order_cm))
  # CMDTC comes from the MODEL's generic --DTC (the IG's CM list has no
  # CMDTC at all) and belongs with the timing variables at the end, NOT
  # appended after CMSTDTC - appending was tried and reported a false
  # violation for exactly this pair.
  expect_lt(match("CMSTDTC", order_cm), match("CMDTC", order_cm) + length(order_cm))
  expect_true(match("CMTRT", order_cm) < match("CMDTC", order_cm))
})

test_that("standard_variable_order takes the IG verbatim for a non-general-observation class", {
  # Only Findings/Interventions/Events/Findings About build from the Model.
  # Special Purpose, Trial Design and Relationship take the IG's list in its
  # own order; padding those with the Model's identifier/timing skeleton
  # makes an "ordered subset" check accept orders it should reject.
  study <- list(standard = list(product = "SDTMIG", version = "3-4"))
  se <- list(data = data.table::data.table(DOMAIN = "SE"), meta = NULL)
  order_se <- standard_variable_order(study, "SE", se)

  expect_true(length(order_se) > 0)
  ig <- library_variables_for(study, "SE")
  expect_equal(order_se, ig$variable[order(ig$ordinal)])
})

test_that("compute_dy uses the date portion only, ignoring any time on RFSTDTC or --DTC", {
  # Bug (CDISC.SENDIG.71): study day is defined on the DATE portion —
  # "(date portion of --DTC) - (date portion of RFSTDTC) + 1" — but parsing
  # kept the time, so difftime returned fractions and rows whose --DY was
  # perfectly correct compared unequal and were reported. Any study whose
  # RFSTDTC carries a time component would see nearly every --DY flagged.
  study <- list(datasets = list(
    DM = list(
      data = data.table::data.table(USUBJID = "S1", RFSTDTC = "2012-11-30T20:00"),
      meta = NULL
    ),
    VS = list(
      data = data.table::data.table(
        USUBJID = rep("S1", 4),
        VSDTC = c("2012-11-23", "2012-11-30T13:00", "2012-11-29T21:00", "2013-01-10")
      ),
      meta = NULL
    )
  ))
  op <- list(domain = "VS", id = "$val_dy", name = "VSDTC", operator = "dy")
  binding <- compute_operation(op, study, "VS", study$datasets$VS)
  # a week before; the reference date itself (day 1, despite the earlier
  # clock time); the day before (-1, study day has no zero); and 42 days on.
  expect_equal(binding$value, c(-7, 1, -1, 42))
})

test_that("study_domains is the set of DOMAIN values, not dataset names", {
  # Bug (CORE-000457): the reference is
  # `list({(dataset.domain or "") for dataset in get_datasets()})` where
  # domain is the DOMAIN column of each dataset's FIRST RECORD, "" when the
  # dataset has no DOMAIN column at all. Using dataset names instead made
  # "SUPP--.RDOMAIN must name a dataset present in the study" pass on a study
  # whose ec.csv has an unreadable header - the name EC was in the set even
  # though no dataset declares DOMAIN=EC.
  study <- list(datasets = list(
    DM = list(data = data.table::data.table(DOMAIN = c("DM", "DM"), USUBJID = c("1", "2")), meta = NULL),
    # No DOMAIN column: contributes "" (every SUPP-- dataset does this).
    SUPPDM = list(data = data.table::data.table(RDOMAIN = "DM", IDVAR = "USUBJID"), meta = NULL),
    # A file whose header did not parse: named EC, but declares no domain.
    EC = list(data = data.table::data.table(V1 = "", V2 = ""), meta = NULL)
  ))
  op <- list(id = "$study_domains", operator = "study_domains")
  binding <- compute_operation(op, study, "SUPPDM", study$datasets$SUPPDM)
  expect_equal(binding$kind, "scalar")
  expect_equal(binding$value, c("", "DM"))
  expect_false("EC" %in% binding$value)
})

test_that("domain_label is the standard's label, not the study's own", {
  # The reference reads this from the standard's dataset metadata
  # (operations/domain_label.py), and the standards genuinely disagree: SENDIG
  # calls LB "Laboratory", SDTMIG calls it "Laboratory Test Results".
  # CORE-000272 asks whether --CAT equals that label, and its own fixture's
  # .env declares SENDIG - so reading the study's own dataset label missed the
  # violation CDISC's engine reports.
  ds <- list(label = "Whatever the sponsor typed")

  send <- list(standard = list(product = "SENDIG", version = "3-1-1"))
  expect_equal(standard_domain_label(send, "LB", ds), "Laboratory")

  sdtm <- list(standard = list(product = "SDTMIG", version = "3-4"))
  expect_equal(standard_domain_label(sdtm, "LB", ds), "Laboratory Test Results")

  # A domain no standard defines falls back to the dataset's own label rather
  # than returning nothing.
  expect_equal(standard_domain_label(sdtm, "XY", ds), "Whatever the sponsor typed")

  # Lower-cased product and an undeclared version both still resolve.
  expect_equal(
    standard_domain_label(list(standard = list(product = "sendig")), "LB", ds),
    "Laboratory"
  )
})

test_that("codelist terms come from the CT package the caller names", {
  study <- list(ct_package = "sdtmct-2026-03-27")
  op <- list(operator = "codelist_terms", codelists = "SEX",
             level = "term", returntype = "value")
  expect_setequal(ct_terms_for(op, study), c("F", "INTERSEX", "M", "U"))

  # Terminology moves between releases, which is why every package is bundled
  # and none is guessed on the user's behalf: judging a 2014 study by 2026
  # terms would reject UNDIFFERENTIATED and accept INTERSEX.
  old <- list(ct_package = "sdtmct-2014-09-26")
  expect_setequal(ct_terms_for(op, old), c("F", "M", "U", "UNDIFFERENTIATED"))

  # returntype picks values or C-codes; level picks the codelist or its terms.
  codes <- ct_terms_for(
    list(operator = "codelist_terms", codelists = "SEX", level = "term",
         returntype = "code"), study
  )
  expect_length(codes, 4L)
  expect_true(all(grepl("^C[0-9]+$", codes)))
  expect_equal(
    ct_terms_for(list(operator = "codelist_terms", codelists = "SEX",
                      level = "codelist", returntype = "code"), study),
    "C66731"
  )

  # A codelist the package does not have must raise, not come back empty -
  # an empty term set makes `is_not_contained_by` true for every row, so the
  # whole column would be reported as invalid.
  expect_error(
    ct_terms_for(list(operator = "codelist_terms", codelists = "NOSUCHLIST",
                      level = "term", returntype = "value"), study),
    "not in controlled terminology package"
  )
})

test_that("an unimplemented Operations type is refused, not answered", {
  # The switch used to fall through to NULL for anything unrecognised, so the
  # rule's condition resolved to literal text and the rule reported nothing at
  # all. CORE-000934 did exactly that: CDISC's engine reports rows 4 and 5 on
  # its own fixture and check_study() reported none.
  expect_error(
    compute_operation(list(operator = "no_such_operation", id = "$x"),
                      list(datasets = list()), "AE", NULL),
    "unimplemented Operations type: no_such_operation"
  )
  # The harness reads this same vector, so the two cannot drift apart.
  expect_true("codelist_terms" %in% implemented_operation_types)
  # Something CDISC has never defined, so this assertion cannot quietly become
  # vacuous the way naming a real-but-unimplemented type did: `split_by` was
  # used here and then implemented.
  expect_false("no_such_operation" %in% implemented_operation_types)
})

test_that("a controlled terminology package name is checked up front", {
  expect_error(validate_ct_package("sdtmct-1999-01-01"), "not a bundled")
  expect_error(validate_ct_package(42), "single package name")
  expect_identical(validate_ct_package("sdtmct-2026-03-27"), "sdtmct-2026-03-27")
})

test_that("the CT version is taken from TS when the study declares one", {
  # Studies record it themselves: TSVCDREF names the publisher and TSVCDVER
  # the version. Asking the caller for something already in the data would be
  # the same mistake as making them declare the standard.
  ts <- data.table::data.table(
    STUDYID = "S", DOMAIN = "TS", TSSEQ = 1:3,
    TSPARMCD = c("A", "B", "C"),
    TSVCDREF = c("CDISC", "CDISC", "CDISC"),
    TSVCDVER = c("2020-03-27", "2020-03-27", "2020-03-27")
  )
  study <- list(datasets = list(TS = list(data = ts, meta = NULL)),
                standard = list(product = "SDTMIG"))
  expect_equal(ct_package_from_ts(study), "sdtmct-2020-03-27")

  # A SEND study cites SEND terminology, and the two genuinely differ.
  send <- study; send$standard$product <- "SENDIG"
  expect_equal(ct_package_from_ts(send), "sendct-2020-03-27")

  # Real TS datasets carry stale rows. The version most rows agree on wins.
  ts2 <- data.table::copy(ts)
  ts2$TSVCDVER <- c("2020-03-27", "2020-03-27", "2019-03-01")
  mixed <- study; mixed$datasets$TS$data <- ts2
  expect_equal(ct_package_from_ts(mixed), "sdtmct-2020-03-27")

  # Rows citing someone else's terminology are not CDISC's and are ignored.
  ts3 <- data.table::copy(ts)
  ts3$TSVCDREF <- c("SPONSOR", "SPONSOR", "SPONSOR")
  other <- study; other$datasets$TS$data <- ts3
  expect_null(ct_package_from_ts(other))

  # A version CDISC never published as a package is not silently swapped for
  # a near one - that would judge the study against terms it never declared.
  ts4 <- data.table::copy(ts)
  ts4$TSVCDVER <- rep("1999-01-01", 3)
  unknown <- study; unknown$datasets$TS$data <- ts4
  expect_null(ct_package_from_ts(unknown))

  # No TS, or no such columns, says nothing.
  expect_null(ct_package_from_ts(list(datasets = list())))
})

test_that("max and min are generic aggregates, and max_date/min_date stay date-aware", {
  dt <- data.table::data.table(
    grp = c("A", "A", "B", "B"),
    txt = c("Code_16", "Code_2", "Zeta", ""),
    num = c(4, 11, 2, NA),
    dte = c("2023-12-15", "2024-01-02", "not-a-date", "2020-06-01")
  )
  val <- function(op, want_max, fn = extreme_binding) {
    b <- fn(dt, op, want_max = want_max)
    if (is.null(b)) NULL else b$value
  }

  # Text: a plain lexicographic aggregate. The reference's Maximum is a bare
  # pandas .max(), so "Code_2" beats "Code_16" the way string order says.
  expect_identical(val(list(name = "txt"), TRUE), "Zeta")
  expect_identical(val(list(name = "txt"), FALSE), "Code_16")

  # Numbers compare as numbers, not as text, and NA is not a value.
  expect_identical(val(list(name = "num"), TRUE), 11)
  expect_identical(val(list(name = "num"), FALSE), 2)

  # The date-specific pair ignores an unparseable value; the generic pair does
  # not, because for it "not-a-date" is simply the largest string.
  expect_identical(
    date_extreme_binding(dt, list(name = "dte"), want_max = TRUE)$value,
    "2024-01-02"
  )
  expect_identical(val(list(name = "dte"), TRUE), "not-a-date")

  # Grouped, which is the shape USDM's CORE-000808 uses.
  grouped <- extreme_binding(dt, list(name = "txt", group = "grp"), want_max = FALSE)
  expect_equal(grouped$kind, "grouped")
  expect_setequal(grouped$table$.value, c("Code_16", "Zeta"))

  # An absent column yields no binding, which check_study() reports as a skip
  # with a reason rather than answering.
  expect_null(extreme_binding(dt, list(name = "NOSUCHCOL"), want_max = TRUE))
})

test_that("map binds a constant, or looks output up by its key columns", {
  dt <- data.table::data.table(
    parent_rel = c("contactModes", "other", "contactModes"),
    id = c("E1", "E2", "E3")
  )
  study <- list(datasets = list(ENC = list(data = dt)),
                standard = list(product = "USDM"))
  current <- list(data = dt)

  # The direct-assignment branch: one entry, no keys. Every bundled use of
  # this operation takes it.
  const <- compute_operation(
    list(id = "$c", operator = "map", map = list(list(output = "C66797"))),
    study, "ENC", current)
  expect_equal(const$kind, "scalar")
  expect_identical(const$value, "C66797")

  # Keyed: the row's output is the one whose key matches, NA where none does.
  keyed <- compute_operation(
    list(id = "$c", operator = "map",
         map = list(list(parent_rel = "contactModes", output = "C171445"))),
    study, "ENC", current)
  expect_equal(keyed$kind, "per_row")
  expect_identical(keyed$value, c("C171445", NA_character_, "C171445"))

  # Keying on a column nobody has is refused, not answered. Answering would
  # bind NA everywhere and the rule would quietly report nothing.
  expect_error(
    compute_operation(
      list(id = "$c", operator = "map",
           map = list(list(nosuchcol = "x", output = "y"))),
      study, "ENC", current),
    "does not have"
  )
})

test_that("group_aliases rename a grouped binding's join columns positionally", {
  binding <- grouped_binding(
    "parent_id",
    data.table::data.table(parent_id = c("S1", "S2"), .value = c(1L, 2L)),
    ".value"
  )
  aliased <- apply_group_aliases(binding, list(group = "parent_id", group_aliases = "id"))
  expect_identical(aliased$group_cols, "id")
  expect_true("id" %in% names(aliased$table))
  expect_false("parent_id" %in% names(aliased$table))

  # No aliases, or a scalar binding, must pass through untouched.
  plain <- grouped_binding("g", data.table::data.table(g = "x", .value = 1L), ".value")
  expect_identical(apply_group_aliases(plain, list(group = "g"))$group_cols, "g")
  expect_equal(apply_group_aliases(scalar_binding(1), list(group_aliases = "id"))$kind, "scalar")
})

test_that("an Operations parameter resolves as a binding, then a column, then itself", {
  dt <- data.table::data.table(code = c("C1", "C2"))
  bindings <- list(`$bound` = scalar_binding("C66797"))

  expect_identical(resolve_operation_reference("$bound", bindings, dt), "C66797")
  expect_identical(resolve_operation_reference("code", bindings, dt), c("C1", "C2"))
  # Neither a binding nor a column, so the rule means the text itself.
  expect_identical(resolve_operation_reference("C12345", bindings, dt), "C12345")
  expect_null(resolve_operation_reference(NULL, bindings, dt))
})

test_that("a column called 'name' does not shadow the aggregated column", {
  # data.table evaluates `j` with the columns in scope, so a lookup of the
  # variable `name` inside it found this column instead of the function's own
  # argument, then tried to resolve that column's first VALUE as a variable:
  # "object 'POP1' not found". No SDTM domain has a column called `name`;
  # every USDM entity does.
  dt <- data.table::data.table(
    id = c("A", "A", "B"),
    name = c("POP1", "POP2", "POP3"),
    parent_id = c("P1", "P2", "P1")
  )
  agg <- compute_group_agg(dt, "id", "parent_id", distinct_values)
  expect_false(is.null(agg))
  expect_setequal(agg$id, c("A", "B"))
  expect_setequal(unlist(agg$.value[agg$id == "A"]), c("P1", "P2"))
  expect_identical(unlist(agg$.value[agg$id == "B"]), "P1")

  # Aggregating the shadowing column itself must also work.
  named <- compute_group_agg(dt, "id", "name", distinct_values)
  expect_setequal(unlist(named$.value[named$id == "A"]), c("POP1", "POP2"))
})

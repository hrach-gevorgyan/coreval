expected_violations_for <- function(results_csv_path, dataset_name, n) {
  out <- rep(FALSE, n)
  results <- data.table::fread(results_csv_path, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  if (nrow(results) > 0) {
    out[as.integer(unique(results$Record))] <- TRUE
  }
  out
}

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
      cases <- Sys.glob(test_path("fixtures", "core_rules", id, case, "*"))
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
    cases <- Sys.glob(test_path("fixtures", "core_rules", "CORE-000454", case, "*"))
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

test_that("get_model_column_order returns NULL (unresolvable) for a class with no modeled variables", {
  # Special-Purpose/Relationship/Trial Design/Study Reference classes have
  # no generic class-level variable list in the Model - each domain in them
  # (DM, RELREC, TA, ...) defines its own bespoke variables instead. An
  # empty allowed-set would make is_not_contained_by flag every variable.
  study <- list(datasets = list(DM = list(data = data.table::data.table(A = 1), meta = NULL)))
  op <- list(domain = "DM", id = "$allowed", operator = "get_model_column_order")
  binding <- compute_operation(op, study, "DM", study$datasets$DM)
  expect_null(binding)
})

test_that("study_domains/dataset_names/variable_exists/domain_is_custom are local, no Library needed", {
  study <- list(datasets = list(
    AE = list(data = data.table::data.table(AETERM = "X", AESCAN = "Y"), meta = NULL),
    ZZ = list(data = data.table::data.table(A = 1), meta = NULL)
  ))
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
      case_dirs <- Sys.glob(test_path("fixtures", "core_rules", id, polarity, "*"))
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

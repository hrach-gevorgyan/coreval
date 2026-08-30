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

test_that("sdtmig_variables_for resolves SUPPxx datasets via the SUPPQUAL template", {
  study <- list(standard = list(product = "SDTMIG", version = "3-4"))
  vars <- sdtmig_variables_for(study, "SUPPAE", "Exp")
  expect_setequal(vars, c("IDVAR", "IDVARVAL", "QEVAL"))
})

test_that("sdtmig_variables_for returns NULL for a study explicitly declared as a different standard", {
  # Confirmed necessary against CORE-000355's own EX fixture, whose .env
  # declares SENDIG 3.1 - using SDTMIG data there would silently produce a
  # plausible-but-wrong answer.
  study <- list(standard = list(product = "SENDIG", version = "3-1"))
  expect_null(sdtmig_variables_for(study, "EX", "Req"))
})

test_that("sdtmig_variables_for defaults to the newest SDTMIG version when the study doesn't declare one", {
  study <- list(standard = list(product = NA_character_, version = NA_character_))
  vars <- sdtmig_variables_for(study, "EX", "Req")
  expect_true("EXTRT" %in% vars)
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

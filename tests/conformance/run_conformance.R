# The conformance harness: runs every bundled rule against CDISC's own
# positive/negative reference test cases and reports pass/fail/skipped.
#
# NOT part of the package, NOT run by R CMD check or on CRAN (per CRAN
# policy: no network access, no long-running checks). Needs a local clone
# of cdisc-org/cdisc-open-rules.
#
# Usage (from the package root):
#   git clone --depth 1 https://github.com/cdisc-org/cdisc-open-rules.git /some/scratch/dir
#   Rscript tests/conformance/run_conformance.R /some/scratch/dir
#
# What this does and does NOT check yet:
#   - Checks WHICH records a rule flags as violations, against the distinct
#     Record numbers in the reference results.csv for each Dataset.
#   - Does NOT yet check the exact Variable/Value columns results.csv
#     reports (that's Phase 9 - Output Variables/formatting - not built).
#   - For Sensitivity: Dataset rules, only checks "did a violation occur
#     anywhere" (any rows in results.csv) vs "did evaluate_rule() flag any
#     record" - not exact record positions, since a Dataset-sensitivity
#     rule's real output is one finding for the whole dataset, not one per
#     record (also Phase 9's job to assemble correctly).

devtools::load_all(quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
upstream_dir <- if (length(args) >= 1) args[[1]] else file.path("data-raw", "cdisc-open-rules")
if (!dir.exists(upstream_dir)) {
  stop("Upstream clone not found at: ", upstream_dir, call. = FALSE)
}

source_root <- function(source) {
  switch(source,
    published = file.path(upstream_dir, "Published"),
    deprecated_dir = file.path(upstream_dir, "Deprecated"),
    fda_business_rules_draft = file.path(upstream_dir, "Unpublished", "FDA Business Rules"),
    stop("Unknown rule source: ", source)
  )
}

rule_operators <- function(check, ops = character(0)) {
  if (is.null(check)) {
    return(ops)
  }
  if (!is.null(check$operator)) {
    ops <- c(ops, check$operator)
  }
  for (key in c("all", "any", "not")) {
    sub <- check[[key]]
    if (!is.null(sub)) {
      if (is.list(sub) && is.null(names(sub))) {
        for (item in sub) ops <- rule_operators(item, ops)
      } else {
        ops <- rule_operators(sub, ops)
      }
    }
  }
  ops
}

expected_records <- function(results_csv, dataset_name) {
  results <- data.table::fread(results_csv, colClasses = "character")
  results <- results[results$Dataset == dataset_name, ]
  as.integer(unique(results$Record))
}

# Runs one rule against one test case (a positive/NN or negative/NN dir).
# Returns list(status, reason).
run_case <- function(rule, case_dir) {
  data_dir <- file.path(case_dir, "data")
  results_csv <- file.path(case_dir, "results", "results.csv")
  if (!dir.exists(data_dir) || !file.exists(results_csv)) {
    return(list(status = "SKIPPED", reason = "missing data/ or results.csv"))
  }

  study <- tryCatch(read_study(data_dir), error = function(e) e)
  if (inherits(study, "error")) {
    return(list(status = "SKIPPED", reason = paste("read_study failed:", conditionMessage(study))))
  }

  domains <- names(study$datasets)
  applicable <- Filter(function(d) rule_applies_to_domain(rule, d), domains)
  if (length(applicable) == 0) {
    return(list(status = "SKIPPED", reason = "no dataset in this test case matches the rule's scope"))
  }

  for (domain in applicable) {
    violations <- tryCatch(
      evaluate_rule(rule, study, domain),
      error = function(e) e
    )
    if (inherits(violations, "error")) {
      return(list(status = "SKIPPED", reason = paste("evaluate_rule failed:", conditionMessage(violations))))
    }

    expected <- expected_records(results_csv, domain)

    if (identical(rule$sensitivity, "Dataset") || identical(rule$rule_type, "Domain Presence Check")) {
      actual_any <- any(violations)
      # A whole-study-level rule (e.g. Domain Presence Check's "is DM
      # present anywhere") reports its finding under a "STUDY" sentinel
      # Dataset, not the domain that happened to be iterated to produce it -
      # the reference results.csv row is the same regardless of which
      # domain the harness checks it against.
      expected_any <- length(expected) > 0 || length(expected_records(results_csv, "STUDY")) > 0
      if (!identical(actual_any, expected_any)) {
        return(list(status = "FAIL", reason = sprintf(
          "[%s] Dataset-sensitivity mismatch: expected violation=%s, got %s",
          domain, expected_any, actual_any
        )))
      }
    } else if (identical(rule$sensitivity, "Group") && !is.null(rule$grouping_variables)) {
      dataset <- study$datasets[[domain]]
      actual <- group_first_violations(dataset, violations, rule$grouping_variables, domain)
      if (!identical(sort(actual), sort(expected))) {
        return(list(status = "FAIL", reason = sprintf(
          "[%s] Group-sensitivity record mismatch: expected {%s}, got {%s}",
          domain, paste(expected, collapse = ","), paste(actual, collapse = ",")
        )))
      }
    } else {
      actual <- which(violations)
      if (!identical(sort(actual), sort(expected))) {
        return(list(status = "FAIL", reason = sprintf(
          "[%s] record mismatch: expected {%s}, got {%s}",
          domain, paste(expected, collapse = ","), paste(actual, collapse = ",")
        )))
      }
    }
  }
  list(status = "PASS", reason = NA_character_)
}

implemented_operations <- c(
  "distinct", "record_count", "max_date", "max", "min_date",
  "get_column_order_from_dataset", "variable_exists", "variable_count",
  "study_domains", "dataset_names", "domain_is_custom", "domain_label", "extract_metadata", "dy",
  "get_model_column_order", "required_variables", "expected_variables"
)

run_rule <- function(rule) {
  ops <- unique(rule_operators(rule$check))
  missing_ops <- setdiff(ops, ls(.operator_registry))
  if (length(missing_ops) > 0) {
    return(list(status = "SKIPPED", reason = paste("unimplemented operator(s):", paste(missing_ops, collapse = ", "))))
  }
  if (!is.null(rule$operations)) {
    op_types <- unique(vapply(rule$operations, function(o) o$operator, character(1)))
    missing <- setdiff(op_types, implemented_operations)
    if (length(missing) > 0) {
      return(list(status = "SKIPPED", reason = paste("unimplemented Operations type(s):", paste(missing, collapse = ", "))))
    }
  }
  rule_dir <- file.path(source_root(rule$source), rule$id)
  # Most rules number their cases (positive/01/, positive/02/, ...), but some
  # FDA Business Rules drafts put data/ and results/ directly under
  # positive/negative with no numbered subfolder at all (a flat layout).
  # Globbing one level deeper in that case would return "positive/data" and
  # "positive/results" as if they were case dirs, which then both fail the
  # data/+results.csv check and get silently SKIPPED - the case is never
  # actually tested, even though real test data exists right there.
  case_dirs_for <- function(polarity) {
    base <- file.path(rule_dir, polarity)
    if (dir.exists(file.path(base, "data"))) base else Sys.glob(file.path(base, "*"))
  }
  case_dirs <- c(case_dirs_for("positive"), case_dirs_for("negative"))
  if (length(case_dirs) == 0) {
    return(list(status = "SKIPPED", reason = "no test case folders found"))
  }

  results <- lapply(case_dirs, run_case, rule = rule)
  fails <- Filter(function(r) r$status == "FAIL", results)
  if (length(fails) > 0) {
    return(list(status = "FAIL", reason = fails[[1]]$reason))
  }
  skips <- Filter(function(r) r$status == "SKIPPED", results)
  if (length(skips) == length(results)) {
    return(list(status = "SKIPPED", reason = skips[[1]]$reason))
  }
  list(status = "PASS", reason = NA_character_)
}

rules <- .coreval_env$data$rules

# Optional targeted mode: any rule IDs after the upstream dir restrict the run
# to just those rules, which takes seconds instead of the full ~5-minute
# 756-rule sweep. Use it to verify one fix in a tight loop; run the full sweep
# (no IDs) before committing, since a shared operator change can regress a
# rule outside the targeted set. A targeted run does NOT rewrite
# scoreboard.csv - that file always reflects a full run, so it can't be
# silently truncated to a handful of rules.
#   Rscript tests/conformance/run_conformance.R <upstream_dir>
#   Rscript tests/conformance/run_conformance.R <upstream_dir> CORE-000109 CORE-000149
target_ids <- if (length(args) >= 2) args[-1] else NULL
if (!is.null(target_ids)) {
  unknown <- setdiff(target_ids, names(rules))
  if (length(unknown) > 0) {
    stop("No such rule id(s) in the bundled registry: ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  rules <- rules[target_ids]
}

cat(sprintf("Running conformance harness on %d rules...\n", length(rules)))

scoreboard <- data.table::rbindlist(lapply(rules, function(rule) {
  outcome <- tryCatch(run_rule(rule), error = function(e) {
    list(status = "SKIPPED", reason = paste("harness error:", conditionMessage(e)))
  })
  data.table::data.table(
    id = rule$id,
    source = rule$source,
    rule_type = rule$rule_type,
    executability = rule$executability,
    sensitivity = rule$sensitivity,
    status = outcome$status,
    reason = outcome$reason
  )
}))

cat("\n=== Overall ===\n")
print(table(scoreboard$status))

fully_executable <- scoreboard[scoreboard$executability == "Fully Executable", ]
cat(sprintf(
  "\nPass rate among Fully Executable rules: %d / %d (%.1f%%)\n",
  sum(fully_executable$status == "PASS"),
  nrow(fully_executable),
  100 * sum(fully_executable$status == "PASS") / nrow(fully_executable)
))

cat("\n=== By rule_type ===\n")
print(table(scoreboard$rule_type, scoreboard$status))

cat("\n=== Skip reasons (top 15) ===\n")
skip_reasons <- scoreboard[scoreboard$status == "SKIPPED", ]$reason
print(head(sort(table(skip_reasons), decreasing = TRUE), 15))

cat("\n=== Failures ===\n")
fail_rows <- scoreboard[scoreboard$status == "FAIL", ]
if (nrow(fail_rows) > 0) {
  for (i in seq_len(nrow(fail_rows))) {
    cat(fail_rows$id[i], "-", fail_rows$reason[i], "\n")
  }
} else {
  cat("(none)\n")
}

if (is.null(target_ids)) {
  out_path <- file.path("tests", "conformance", "scoreboard.csv")
  data.table::fwrite(scoreboard, out_path)
  cat("\nFull scoreboard written to", out_path, "\n")
} else {
  cat("\n(targeted run - scoreboard.csv left untouched)\n")
}

# Collects the `name` fields referenced in a Check tree, in order of first
# appearance, excluding `$`-prefixed Operations bindings (those aren't real
# dataset columns). Used as the fallback Output Variables set when a rule's
# Outcome doesn't specify one explicitly - confirmed against a real rule
# (CORE-000001 has no `Output Variables`, and its reference results.csv
# lists exactly its two Check condition names, in Check order: IECAT then
# IEORRES).
#' Collect the `name` fields referenced in a Check tree, in first-appearance order
#' @param check A Check node (or `NULL`).
#' @param names_seen Accumulator of names collected so far.
#' @return A character vector of column names (excluding `$`-prefixed Operations bindings).
#' @noRd
collect_check_names <- function(check, names_seen = character(0)) {
  if (is.null(check)) {
    return(names_seen)
  }
  if (!is.null(check$name) && is.character(check$name) && !startsWith(check$name, "$")) {
    if (!(check$name %in% names_seen)) {
      names_seen <- c(names_seen, check$name)
    }
  }
  for (key in c("all", "any", "not")) {
    sub <- check[[key]]
    if (!is.null(sub)) {
      if (is.list(sub) && is.null(names(sub))) {
        for (item in sub) names_seen <- collect_check_names(item, names_seen)
      } else {
        names_seen <- collect_check_names(sub, names_seen)
      }
    }
  }
  names_seen
}

# The exact, ordered set of columns a rule's findings should report -
# getting this wrong (wrong set OR wrong order) fails a differential test
# even when the underlying violation logic is correct.
#' Determine a rule's ordered Output Variables (declared, or inferred from its Check)
#' @param rule A rule record.
#' @param domain Domain code, used to resolve `"--"` templates.
#' @return A character vector of resolved variable names.
#' @noRd
get_output_variables <- function(rule, domain) {
  declared <- rule$outcome[["Output Variables"]]
  raw <- if (!is.null(declared)) declared else collect_check_names(rule$check)
  resolve_var_name(raw, domain)
}

# The rule types check_study() will actually run. Each one needs a
# genuinely different "what is one row" model, all of which
# prepare_dataset_for_rule() already builds (see its own comment) - this
# list exists so a rule type is run only when that modelling is DELIBERATE,
# rather than defaulting every unrecognised type down the record-level path
# where its pseudo-field names silently resolve to literal text.
#
# The two "against Define XML" types are included: define.xml IS read (see
# R/define.R), and evaluate_rule() refuses per-study when the study has no
# define.xml or `xml2` is missing, so a rule is skipped with a reason
# rather than evaluated against absent columns.
#
# "Define Item Metadata Check against Library Metadata" is included too:
# both halves it needs - define.xml and the Library's own variable metadata
# - are now available, and evaluate_rule() still refuses per study when the
# study has no define.xml.
#' Rule types `check_study()` can evaluate
#' @param rule_type A rule's `rule_type` string.
#' @return `TRUE` if `check_study()` should evaluate rules of this type.
#' @noRd
rule_type_is_supported <- function(rule_type) {
  isTRUE(rule_type %in% c(
    "Record Data",
    "Domain Presence Check",
    "Domain Presence Check against Define XML",
    "Dataset Metadata Check",
    "Variable Metadata Check",
    "Variable Metadata Check against Library Metadata",
    "Variable Metadata Check against Define XML",
    "Value Check with Variable Metadata",
    "Value Check with Dataset Metadata",
    "Define Item Metadata Check against Library Metadata"
  ))
}

#' An empty findings table with the correct columns
#' @return A zero-row [data.table::data.table()] with columns `Dataset`, `Record`, `Variable`, `Value`.
#' @noRd
empty_findings <- function() {
  data.table::data.table(
    Dataset = character(0), Record = integer(0),
    Variable = character(0), Value = character(0)
  )
}

# A rule's `Grouping_Variables` field (only present for Sensitivity: Group
# rules, e.g. CORE-000888's "SETCD") collapses one finding per GROUP rather
# than per record - confirmed against CORE-000888's real fixtures: a
# 3-record SETCD group where every record shares the same (grouped-binding-
# derived) violation result reports exactly ONE finding, at the group's
# first violating row.
#' Collapse per-row violations to one flagged row per distinct `grouping_vars` group
#' @param dataset The dataset that was checked.
#' @param violations Logical vector, one element per row.
#' @param grouping_vars Raw (possibly `"--"`-templated) grouping column name(s).
#' @param domain Domain code, used to resolve `"--"` templates.
#' @return An integer vector of row indices: the first violating row of each distinct group.
#' @noRd
group_first_violations <- function(dataset, violations, grouping_vars, domain) {
  violating_idx <- which(violations)
  resolved <- resolve_var_name(grouping_vars, dataset_wildcard(dataset, domain))
  resolved <- resolved[resolved %in% names(dataset$data)]
  if (length(resolved) == 0 || length(violating_idx) == 0) {
    return(violating_idx)
  }
  key <- do.call(paste, c(lapply(resolved, function(v) dataset$data[[v]]), sep = "\x1f"))[violating_idx]
  violating_idx[!duplicated(key)]
}

# Assembles one rule's findings for one dataset into the long format used by
# CDISC's own results.csv: one row per (Record, Variable), or for
# Sensitivity: Dataset rules, one row per Variable with Record blank (NA)
# and Value taken from the first violating record - the shape confirmed
# directly against real reference output (e.g. CORE-000864). Sensitivity:
# Group rules (see group_first_violations()) report the same
# one-row-per-(Record, Variable) shape as ordinary Record-sensitivity, just
# collapsed to one Record per group first.
#' Assemble one rule's findings for one dataset into the long results.csv format
#' @param rule A rule record.
#' @param dataset The dataset that was checked (post Match Datasets joins).
#' @param domain Domain code.
#' @param violations Logical vector from `evaluate_check()`, one element per row.
#' @param bindings Operations bindings for the rule (see `operation_bindings_for_rule()`),
#'   needed only when a `$`-prefixed Operations binding is itself declared as an
#'   Output Variable (e.g. CORE-000888's `$txparmcd`).
#' @return A [data.table::data.table()] with columns `Dataset`, `Record`, `Variable`, `Value`.
#' @noRd
assemble_findings <- function(rule, dataset, domain, violations, bindings = list()) {
  output_vars <- unique(get_output_variables(rule, dataset_wildcard(dataset, domain)))
  # An Output Variable that isn't a real column of THIS domain's dataset
  # (e.g. "POOLID" for a rule whose Check covers both USUBJID- and
  # POOLID-keyed domains, or a domain simply lacking a variable another
  # domain has) is still reported - as the reference engine's own literal
  # text "Not in dataset" - not silently dropped from the findings row.
  # Confirmed against CORE-000750's real fixture: AE's findings report
  # `USUBJID = "Not in dataset"` (AE is POOLID-keyed) right alongside
  # CM's findings reporting `POOLID = "Not in dataset"` (CM is
  # USUBJID-keyed) for the exact same rule. An unresolvable `$`-prefixed
  # Operations binding is the one exception that's still dropped entirely,
  # since a binding either resolves for the whole rule or doesn't exist as
  # a concept at all.
  output_vars <- output_vars[!startsWith(output_vars, "$") | output_vars %in% names(bindings)]
  if (length(output_vars) == 0 || !any(violations)) {
    return(empty_findings())
  }

  # Known limitation: a numeric value is reformatted via as.character() here,
  # which loses the source text's original formatting (e.g. "0.0" in the
  # source CSV becomes R double 0, printed back as "0", not "0.0"). Fixing
  # this needs read_study() to carry the raw source text alongside the
  # parsed numeric value specifically for reporting - not done yet.
  #
  # A second, separate known limitation: a `$`-prefixed Output Variable
  # bound to a `distinct` Operations set (e.g. CORE-000888's `$txparmcd`)
  # is reported here as a sorted Python-list-repr string
  # (e.g. "['ARMCD', 'PLANFSUBxxx', 'SPGRPCD']"). The reference engine's own
  # set iteration order is Python's, which is not alphabetical and not
  # reproducible from R - so this can format correctly (right elements)
  # without matching the reference's exact element ORDER byte-for-byte.
  format_binding_value <- function(x) {
    if (is.list(x)) x <- x[[1]]
    if (length(x) != 1) {
      return(paste0("[", paste(sprintf("'%s'", x), collapse = ", "), "]"))
    }
    if (is.na(x)) "" else as.character(x)
  }
  value_at <- function(row) {
    vapply(output_vars, function(v) {
      if (startsWith(v, "$")) {
        resolved <- resolve_binding(bindings[[v]], dataset)
        # A LIST holds one collection per row, so take this row's. An atomic
        # vector is ONE collection shared by every row (the same distinction
        # as_row_collections() makes), so the whole vector is this row's value.
        # Indexing it by row number took element 1 of a 17-element set and
        # reported that single name as if it were the finding - so
        # "$expected_variables = RFSTDTC" was shown when RFSTDTC was merely
        # the first of seventeen expected variables, and the ones actually
        # missing were never named at all.
        elem <- if (is.list(resolved)) resolved[row] else resolved
        return(format_binding_value(elem))
      }
      x <- if (is_relrec_wildcard(v)) {
        resolve_relrec_wildcard_value(v, dataset, for_display = TRUE)[row]
      } else if (!(v %in% names(dataset$data))) {
        return("Not in dataset")
      } else {
        dataset$data[[v]][row]
      }
      # A missing NUMERIC value's `as.character()` is `NA_character_`, not
      # `""` - this package's own blank contract (see read.R) says a numeric
      # blank is `NA` internally but must report as `""`, matching how a
      # missing character column already reports (its blank is already
      # `""`, never `NA`). Left uncorrected, a violation on a row with a
      # missing numeric Output Variable would emit the literal text "NA".
      if (is.na(x)) "" else as.character(x)
    }, character(1))
  }

  # A Match Datasets join can explode one original row into several (see
  # match_datasets.R): `Record` must report the ORIGINAL row number, and
  # the reported Value must come from whichever exploded row actually
  # violated (e.g. the one matched SE record whose date window fit),
  # never an arbitrary/first exploded copy.
  row_id <- dataset$data$.coreval_row_id
  record_of <- function(exploded_row) if (is.null(row_id)) exploded_row else row_id[exploded_row]

  # A "Domain Presence Check" is inherently a whole-study-level FACT (does
  # this domain exist anywhere?), never a per-record concept, regardless of
  # what its own `Sensitivity` field happens to say - confirmed against
  # every currently-passing rule of this type (all declare Sensitivity:
  # Dataset), while CORE-000183/CORE-000188 are the only two that instead
  # (evidently by authoring inconsistency, not intent) say Sensitivity:
  # Record despite reporting the exact same blank-Record, single-fact shape
  # under the "STUDY" sentinel dataset.
  if (identical(rule$sensitivity, "Dataset") || identical(rule$rule_type, "Domain Presence Check")) {
    first_row <- which(violations)[1]
    data.table::data.table(
      Dataset = domain, Record = NA_integer_,
      Variable = output_vars, Value = value_at(first_row)
    )
  } else {
    exploded_rows <- if (identical(rule$sensitivity, "Group") && !is.null(rule$grouping_variables)) {
      group_first_violations(dataset, violations, rule$grouping_variables, domain)
    } else {
      which(violations)
    }
    records <- record_of(exploded_rows)
    keep <- !duplicated(records) # one finding per original record
    exploded_rows <- exploded_rows[keep]
    records <- records[keep]
    if (length(exploded_rows) == 0) {
      return(empty_findings())
    }

    # One data.table for the whole set, not one per violating record. The
    # per-record version allocated a data.table per row and rbindlist'ed
    # thousands of them, which was over half the remaining runtime of a
    # check once the date operators stopped dominating.
    #
    # value_at() returns one value per output variable, so stacking those
    # columns gives a matrix of (variable x record). Reading it in column
    # order yields record 1's variables, then record 2's - exactly the order
    # rep(records, each =) and rep(output_vars, times =) produce.
    values <- vapply(exploded_rows, value_at, character(length(output_vars)))
    data.table::data.table(
      Dataset = domain,
      Record = rep(records, each = length(output_vars)),
      Variable = rep(output_vars, times = length(exploded_rows)),
      Value = as.vector(values)
    )
  }
}

#' Check a whole study against CDISC Open Rules
#'
#' Runs every rule that applies to every dataset in the study, including the
#' ones that compare datasets against each other. Use this once the datasets
#' exist as files; to check a single dataset while you are still writing the
#' code that builds it, see [check_dataset()].
#'
#' Findings come back one row per (dataset, record, variable), pointing at the
#' exact spot. Some rules ask about a dataset as a whole rather than a
#' particular row - those leave `Record` blank. A few ask about the study as a
#' whole, such as "is DM present at all?"; those are answered once and reported
#' under `Dataset = "STUDY"` rather than repeated for every domain.
#'
#' Rules comparing against a define.xml do run, as long as the study has one and
#' the `xml2` package is installed. Without both, they are skipped with a reason
#' instead of being run against columns that are not there, which would report
#' problems that do not exist. The same goes for any rule needing an operator or
#' join coreval does not implement yet.
#'
#' @param study A study object from [read_study()].
#' @param use_case Optional use case (e.g. `"INDH"`) to further filter
#'   which rules apply, as in [rules_for_domain()].
#' @return Two tables, and both are worth reading:
#'   * `findings` - what is wrong. Columns `rule_id`, `Dataset`, `Record`,
#'     `Variable`, `Value`, one row per problem. `Not in dataset` under `Value`
#'     means the rule wanted a variable you do not have, which is usually the
#'     finding itself.
#'   * `skipped` - what could not be checked, with a `reason` for each. Read
#'     this one: an empty `findings` table can mean clean data *or* rules that
#'     never ran, and they look identical otherwise.
#' @examples
#' \donttest{
#' dir <- tempfile("coreval_study_")
#' dir.create(dir)
#' haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
#' study <- read_study(dir)
#' result <- check_study(study)
#' result$findings
#' unlink(dir, recursive = TRUE)
#' }
#' @export
check_study <- function(study, use_case = NULL) {
  run_checks(study, use_case = use_case, require_referenced_domains = FALSE)
}

#' Evaluate every applicable rule against every domain in a study
#'
#' The single evaluation loop behind both [check_study()] and
#' [check_dataset()], so the two can never drift apart in what they run or how
#' they report it.
#'
#' @param study A study object.
#' @param use_case Optional use case filter.
#' @param require_referenced_domains When `TRUE`, a rule that references a
#'   domain absent from `study` is skipped with a reason instead of evaluated.
#'   See `assert_referenced_domains_available()` for why this is `FALSE` for a
#'   whole study and `TRUE` for a single dataset.
#' @return `list(findings, skipped)`, see [check_study()].
#' @noRd
run_checks <- function(study, use_case = NULL, require_referenced_domains = FALSE) {
  domains <- names(study$datasets)
  n_ran <- 0L
  all_findings <- list()
  all_skipped <- list()
  # A whole-study rule type asks one question about the STUDY (e.g. "is DM
  # present anywhere?"), so it must be answered ONCE and reported under the
  # "STUDY" sentinel dataset - not re-answered for each domain the scope
  # happens to match, which would repeat the identical fact under every
  # dataset name.
  study_level_done <- character(0)

  # Worked out up front so the progress bar knows the total, and so the rule
  # list is not recomputed per domain.
  plans <- lapply(domains, function(d) {
    rules_for_domain(d, use_case = use_case, dataset = study$datasets[[d]])$id
  })
  names(plans) <- domains

  # A big study still takes long enough that silence reads as a hang, and
  # people reach for Ctrl-C. Off when not interactive, so test and script
  # output stays clean; `options(coreval.progress = FALSE)` turns it off.
  show_progress <- isTRUE(getOption("coreval.progress", interactive())) &&
    sum(lengths(plans)) > 0
  if (show_progress) {
    pb <- utils::txtProgressBar(min = 0, max = sum(lengths(plans)), style = 3)
    on.exit(close(pb), add = TRUE)
    done <- 0L
  }

  for (domain in domains) {
    for (rule_id in plans[[domain]]) {
      if (show_progress) {
        done <- done + 1L
        utils::setTxtProgressBar(pb, done)
      }
      rule <- .coreval_env$data$rules[[rule_id]]
      if (!rule_type_is_supported(rule$rule_type)) {
        all_skipped[[length(all_skipped) + 1]] <- data.table::data.table(
          rule_id = rule_id, domain = domain,
          reason = paste0("unsupported rule type: ", rule$rule_type)
        )
        next
      }
      # Refused deliberately, so it is reported as its own reason rather than
      # through the generic "evaluation failed" path below: nothing failed,
      # the rule simply asks about data that was not supplied.
      if (require_referenced_domains) {
        absent <- missing_referenced_domains(rule, study, domain)
        if (length(absent) > 0) {
          all_skipped[[length(all_skipped) + 1]] <- data.table::data.table(
            rule_id = rule_id, domain = domain,
            reason = paste0(
              "needs ", paste(absent, collapse = ", "),
              ", which was not supplied - check the whole study folder to run this rule"
            )
          )
          next
        }
      }
      is_study_level <- identical(rule$rule_type, "Domain Presence Check")
      if (is_study_level) {
        if (rule_id %in% study_level_done) {
          next
        }
        study_level_done <- c(study_level_done, rule_id)
      }
      outcome <- tryCatch(
        {
          # Same guards evaluate_rule() applies - this path builds and
          # evaluates inline rather than calling it, so refusing a rule
          # whose define.xml or CDISC Library inputs are unavailable has
          # to happen here too, or it fabricates findings instead.
          assert_rule_inputs_available(rule, study)
          dataset <- prepare_dataset_for_rule(rule, study, domain)
          assert_referenced_metadata_available(rule, dataset)
          bindings <- operation_bindings_for_rule(rule, study, domain, dataset)
          violations <- evaluate_check(rule$check, dataset, domain, bindings, study)
          violations[is.na(violations)] <- FALSE
          list(dataset = dataset, violations = violations, bindings = bindings)
        },
        error = function(e) e
      )
      if (inherits(outcome, "error")) {
        all_skipped[[length(all_skipped) + 1]] <- data.table::data.table(
          rule_id = rule_id, domain = domain,
          reason = paste("evaluation failed:", conditionMessage(outcome))
        )
        next
      }
      n_ran <- n_ran + 1
      findings <- assemble_findings(rule, outcome$dataset, domain, outcome$violations, outcome$bindings)
      if (nrow(findings) > 0) {
        if (is_study_level) {
          findings$Dataset <- "STUDY"
        }
        findings$rule_id <- rule_id
        # The rule's own one-line statement of what is wrong. It is the single
        # most useful thing on the row - "Variable value is not in correct ISO
        # 8601 date or datetime format" tells you what to do; "CORE-000547"
        # does not - and it was being thrown away.
        findings$issue <- rule_message(rule)
        # Which findings deserve attention first. Not a CDISC severity - the
        # rules carry none - but the distinction that governs triage: a value
        # that is present and wrong is a bug, while a value that is absent may
        # be perfectly legitimate for this study.
        findings$triage <- finding_triage(findings, rule)
        all_findings[[length(all_findings) + 1]] <- findings
      }
    }
  }

  findings <- if (length(all_findings) > 0) {
    data.table::rbindlist(all_findings)[
      , c("Dataset", "Record", "Variable", "Value", "issue", "triage", "rule_id")
    ]
  } else {
    cbind(
      empty_findings(),
      issue = character(0), triage = character(0), rule_id = character(0)
    )[
      , c("Dataset", "Record", "Variable", "Value", "issue", "triage", "rule_id")
    ]
  }
  skipped <- if (length(all_skipped) > 0) {
    data.table::rbindlist(all_skipped)
  } else {
    data.table::data.table(rule_id = character(0), domain = character(0), reason = character(0))
  }

  structure(
    list(findings = findings, skipped = skipped),
    class = "coreval_result",
    checks_run = n_ran,
    domains = domains
  )
}

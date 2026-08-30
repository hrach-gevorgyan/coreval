# Substitutes a dataset's actual 2-letter domain code for a "--" variable
# name template (e.g. "--OCCUR" against domain "AE" -> "AEOCCUR"). This is a
# different use of "--" than the Domains scope wildcard (`SUPP--` etc.) -
# there it means "prefix match"; here it means "this domain's code goes
# here."
# What a "--" template actually expands to. NOT the dataset/file name: the
# reference engine uses `wildcard_replacement = ap_suffix or domain or ""`,
# where `domain` is the DOMAIN COLUMN's own value
# (sdtm_dataset_metadata.py), and its documented table spells out the
# consequence - a domain SPLIT ACROSS FILES (`QSX`, `QSXX`, both carrying
# `DOMAIN=QS`) expands `--` to `QS` for every one of them, and an
# Associated Persons dataset `APQS` expands to its `QS` suffix.
#
# Using the file name instead silently mis-resolves every "--" template on
# a split dataset (`lbae.csv` with `DOMAIN=LB` gave `LBAESEQ`, not
# `LBSEQ`), so the column simply doesn't exist and the condition quietly
# evaluates to "unresolvable" rather than checking anything. 251 of the 756
# bundled rules use a "--" template, and splitting a large domain across
# files is routine in real submissions, so this is a correctness bug well
# beyond the conformance fixtures.
#
# Deliberate deviation: the reference yields `""` when there is no DOMAIN
# column (SUPP/RELREC datasets), which would turn `--SEQ` into the bare
# `SEQ`. Falling back to the dataset name instead keeps the previous
# behaviour for those and never fabricates a bare, prefix-less column name.
#' The value a `"--"` variable-name template expands to for a dataset
#' @param dataset The dataset being checked (`list(data, meta)`), or `NULL`.
#' @param domain The dataset's key/file name, used as the fallback.
#' @return A single string to substitute for `"--"`.
#' @noRd
dataset_wildcard <- function(dataset, domain) {
  up <- toupper(domain)
  # An Associated Persons dataset (APQS) expands to the domain it is
  # associated with (QS), which is its own name minus the "AP" prefix.
  if (startsWith(up, "AP") && nchar(up) > 2 && !startsWith(up, "APID")) {
    return(substr(up, 3, nchar(up)))
  }
  dom_col <- dataset$data[["DOMAIN"]]
  if (!is.null(dom_col) && length(dom_col) > 0) {
    first <- as.character(dom_col[1])
    if (!is.na(first) && nzchar(first)) {
      return(toupper(first))
    }
  }
  up
}

#' Substitute a domain code into a `"--"`-prefixed variable name template
#' @param name Variable name, possibly starting with `"--"`.
#' @param domain The value to substitute for `"--"`. Pass
#'   `dataset_wildcard()`'s result, not a raw dataset/file name - the two
#'   differ for a split or Associated Persons dataset.
#' @return The resolved variable name.
#' @noRd
resolve_var_name <- function(name, domain) {
  # ifelse() returns logical(0) - NOT character(0) - for a zero-length
  # input, since with nothing to test it never looks at the yes/no
  # branches to learn their type. That silently changes this function's
  # return type for an empty name list, and the logical(0) then errors out
  # of the next startsWith() several frames away. Reachable in practice:
  # a rule that declares no Output Variables and whose Check references
  # only `$`-bound Operations bindings (e.g. CORE-000893) yields exactly
  # that empty set, which used to crash check_study() on any study
  # containing the matching domain.
  if (length(name) == 0) {
    return(character(0))
  }
  ifelse(
    startsWith(name, "--"),
    paste0(toupper(domain), substr(name, 3, nchar(name))),
    name
  )
}

# A RELREC-joined column name can itself use a "--"-style template, but with
# "**" instead of the CURRENT domain's code - since the joined columns come
# from whichever domain RELREC actually paired this row with, which can vary
# ROW BY ROW (e.g. one FA row's RELREC partner is AE, another's is DS).
# "RELREC.**TERM" therefore means "this row's own RELREC partner domain's
# TERM variable" - confirmed against CORE-000744's real fixture, where FA
# rows linked to different AE records via RELREC report
# `RELREC.**TERM = "FATIGUE"` (AETERM) for one row and `"INJECTION SITE
# REACTION"` for another, and `RELREC.**DECOD`/`RELREC.**TRT` (AE has no
# AEDECOD/AETRT) report the literal text `"Not in dataset"` rather than
# blank/NA - a real fallback value the reference engine reports, not a
# missing-data sentinel. The literal "**" in the OUTPUT VARIABLE label is
# never resolved (results.csv's own Variable column keeps it verbatim) -
# only the per-row VALUE is domain-substituted.
#' Is `name` a RELREC-joined "**"-wildcarded variable template (e.g. "RELREC.**TERM")?
#' @param name A variable name (or vector of them).
#' @return A logical vector.
#' @noRd
is_relrec_wildcard <- function(name) {
  is.character(name) & grepl("^[^.]+\\.\\*\\*.+$", name)
}

#' Resolve a RELREC-joined "**"-wildcarded variable template to its per-row values
#'
#' Two distinct fallbacks, per the reference engine's own behavior: a row
#' with NO RELREC partner at all (or whose partner domain's schema simply
#' doesn't have this variable) resolves to a genuinely BLANK value for
#' CHECK EVALUATION purposes - confirmed necessary against CORE-000744's
#' `negative/02` fixture, where FA rows with no RELREC entry at all must
#' NOT be flagged by `not_equal_to` (a blank target/comparator is a
#' non-violation per the reference truth table, whereas comparing against a
#' fabricated non-blank placeholder string would wrongly flag every
#' unrelated row). `for_display = TRUE` instead reports the reference
#' engine's own literal `"Not in dataset"` text for a genuinely
#' schema-missing variable (e.g. AE has no AETRT) - but NOT for a row with
#' no RELREC partner, since a real violation (and therefore this value ever
#' being rendered) can't happen on such a row - confirmed against
#' CORE-000744's own reported Values, which show blank (not "Not in
#' dataset") for a variable that DOES exist in the partner's schema but
#' happens to be blank on that particular row (e.g. `RELREC.**DECOD`).
#' @param name The wildcarded name, e.g. `"RELREC.**TERM"`.
#' @param dataset The dataset being checked (post RELREC join).
#' @param for_display Report the reference engine's own `"Not in dataset"`
#'   text for a schema-missing variable, instead of blank.
#' @return A character vector, one element per row.
#' @noRd
resolve_relrec_wildcard_value <- function(name, dataset, for_display = FALSE) {
  n <- nrow(dataset$data)
  missing_text <- if (for_display) "Not in dataset" else ""
  m <- regmatches(name, regexec("^([^.]+)\\.\\*\\*(.+)$", name))[[1]]
  prefix <- m[2]
  suffix <- m[3]
  domain_col <- paste0(prefix, ".DOMAIN")
  if (!(domain_col %in% names(dataset$data))) {
    return(rep(missing_text, n))
  }
  row_domains <- toupper(dataset$data[[domain_col]])
  result <- rep("", n)
  for (d in unique(stats::na.omit(row_domains))) {
    idx <- which(row_domains == d)
    col <- paste0(prefix, ".", d, suffix)
    result[idx] <- if (col %in% names(dataset$data)) {
      as.character(dataset$data[[col]][idx])
    } else {
      missing_text
    }
  }
  result
}

# Resolves a condition's comparison target per `value_is_literal`. Returns
# NULL only if the condition has no `value` at all.
#
# The trap is subtler than "value_is_literal defaults to FALSE = column
# reference": per the reference engine's own resolution (comparator not in
# row or value_is_literal -> literal, else row[comparator]), `value` is
# tried as a column reference ONLY when a column by that exact name exists
# in the dataset; otherwise it falls back to being the literal text, even
# with value_is_literal absent. Two concrete failure modes this fixes:
#   - `value: Y` with no column named "Y" in the dataset means the literal
#     string "Y", not a failed column lookup - returning NULL (an earlier
#     version of this function did) silently turned the condition into
#     "always false," since NA propagates to FALSE.
#   - `value: [Y, N]` (a literal array, common for is_contained_by/
#     is_not_contained_by) is never a column reference regardless of
#     value_is_literal - a multi-element value simply never matches a
#     single column name, so it falls through to the literal-array case
#     here on its own; no length-based special-casing is needed. The
#     grouping operators (is_not_unique_set, ...) don't use this resolved
#     value at all - they read raw column names from `condition$value`
#     themselves via ctx$dataset, ignoring whatever this returns.
#
# A `$`-prefixed value (e.g. `$tv_visit`) refers to an Operations binding
# instead of a column - see operations.R.
#' Resolve a Check condition's comparison value (column reference, Operations binding, or literal)
#' @param condition One Check condition.
#' @param dataset The dataset being checked.
#' @param domain Domain code, used to resolve `"--"` templates.
#' @param bindings Operations bindings for the current rule.
#' @return The resolved value, or `NULL` if the condition has no `value`.
#' @noRd
resolve_condition_value <- function(condition, dataset, domain, bindings = list()) {
  if (is.null(condition$value)) {
    return(NULL)
  }
  if (isTRUE(condition$value_is_literal)) {
    return(condition$value)
  }
  if (length(condition$value) == 1 && is.character(condition$value)) {
    if (startsWith(condition$value, "$")) {
      binding <- bindings[[condition$value]]
      return(if (is.null(binding)) NULL else resolve_binding(binding, dataset))
    }
    ref_name <- resolve_var_name(condition$value, domain)
    if (ref_name %in% names(dataset$data)) {
      return(dataset$data[[ref_name]])
    }
    if (is_relrec_wildcard(ref_name)) {
      return(resolve_relrec_wildcard_value(ref_name, dataset))
    }
  }
  condition$value
}

# A condition's `negative` field is NOT a generic "negate this result" flag,
# despite its name suggesting one - confirmed by checking every rule that
# uses it (only 4, in the entire 756-rule set) against the upstream Python
# engine's own source (`Rule.py`'s condition parsing feeds `negative`
# straight into the operator's own `value` dict, and `invalid_duration` is
# the only operator that reads it there, as a parameter meaning "allow a
# leading minus sign", per its own bundled comment "negative: true means:
# allow negative durations"). An earlier version of this function
# generically negated `result` here whenever `negative: true` was set,
# double-negating `invalid_duration`'s own already-negative-aware result
# and silently flagging a perfectly valid duration like "P40Y" as invalid.
#' Evaluate one leaf Check condition against a dataset
#' @param condition One Check condition (`name`, `operator`, optional `value`).
#' @param dataset The dataset being checked.
#' @param domain Domain code, used to resolve `"--"` templates.
#' @param bindings Operations bindings for the current rule.
#' @param study Full study object, needed only to resolve a Domain Presence
#'   Check's pseudo-field `name` (a bare domain code) against which datasets
#'   the STUDY has - `NULL` when unavailable (e.g. a unit test constructing
#'   a bare `list(data, meta)`), in which case such a condition falls back
#'   to the ordinary "not a real column" behavior.
#' @return A logical vector (recycled from scalar for dataset-level operators).
#' @noRd
evaluate_condition <- function(condition, dataset, domain, bindings = list(), study = NULL) {
  # "--" expands to the DOMAIN column's value, not the dataset/file name -
  # see dataset_wildcard(). Computed once here and carried on ctx so every
  # operator resolving its own column names (op_grouping, op_sequence, ...)
  # uses the same expansion.
  wildcard <- dataset_wildcard(dataset, domain)
  if (is.character(condition$name) && startsWith(condition$name, "$")) {
    binding <- bindings[[condition$name]]
    name <- condition$name
    exists <- !is.null(binding)
    target <- if (exists) resolve_binding(binding, dataset) else NULL
  } else {
    name <- resolve_var_name(condition$name, wildcard)
    exists <- name %in% names(dataset$data)
    target <- if (exists) dataset$data[[name]] else NULL

    # Domain Presence Check rules use `exists`/`not_exists` with `name` set
    # to a bare domain code (e.g. "DM", "ADSL", "SUPPDM") - a question about
    # what datasets the STUDY has, not a column in the dataset currently
    # being checked. Only takes over when the ordinary column lookup found
    # nothing, so a dataset that (implausibly) has a real column literally
    # named e.g. "DM" still wins.
    if (!exists && !is.null(study) && condition$operator %in% c("exists", "not_exists")) {
      exists <- toupper(name) %in% toupper(names(study$datasets))
    }
  }

  ctx <- list(
    name = name,
    exists = exists,
    target = target,
    value = resolve_condition_value(condition, dataset, wildcard, bindings),
    n = nrow(dataset$data),
    condition = condition,
    dataset = dataset,
    wildcard = wildcard,
    domain = domain
  )

  op_fn <- get_operator(condition$operator)
  result <- op_fn(ctx)
  # Every leaf condition must return one value per row of `dataset` -
  # documented as the contract of evaluate_check() itself, but a
  # dataset-level operator (exists/not_exists, or `equal_to` against a
  # scalar Operations binding) naturally returns a single value, not one
  # per row. Recycling here (rather than relying on evaluate_check()'s
  # `all`/`any` combinators to broadcast it against a sibling per-row
  # condition via ordinary R recycling) also covers a Check whose EVERY
  # leaf is dataset-level - confirmed necessary against CORE-000291's real
  # fixture: a Match Datasets self-join explodes the dataset to 5 rows, but
  # every one of this rule's two conditions is scalar, so the unrecycled
  # length-1 result silently produced NA (out-of-bounds logical indexing)
  # for every row past the first when collapse_exploded_violations() later
  # indexed into it by row id.
  rep_len(result, ctx$n)
}

# Walks an arbitrarily nested Check tree (all/any/not), returning a per-row
# logical vector (recycled from a scalar for dataset-level conditions like
# exists/not_exists). TRUE means the record violates the rule.
#' Recursively evaluate a Check tree (leaf condition, or `all`/`any`/`not`)
#' @param check A Check node.
#' @param dataset The dataset being checked.
#' @param domain Domain code, used to resolve `"--"` templates.
#' @param bindings Operations bindings for the current rule.
#' @param study Full study object, passed through to `evaluate_condition()`
#'   (see its docs) - `NULL` when unavailable.
#' @return A per-row logical vector; `TRUE` means the record violates the rule.
#' @noRd
evaluate_check <- function(check, dataset, domain, bindings = list(), study = NULL) {
  if (!is.null(check$name) && !is.null(check$operator)) {
    return(evaluate_condition(check, dataset, domain, bindings, study))
  }
  if (!is.null(check$all)) {
    parts <- lapply(check$all, evaluate_check, dataset = dataset, domain = domain, bindings = bindings, study = study)
    return(Reduce(`&`, parts))
  }
  if (!is.null(check$any)) {
    parts <- lapply(check$any, evaluate_check, dataset = dataset, domain = domain, bindings = bindings, study = study)
    return(Reduce(`|`, parts))
  }
  if (!is.null(check$not)) {
    return(!evaluate_check(check$not, dataset, domain, bindings, study))
  }
  stop("Unrecognized Check node: ", paste(names(check), collapse = ", "))
}

#' Evaluate one rule's Check against one dataset
#'
#' @param rule A rule record, e.g. `.coreval_env$data$rules[[id]]` or an
#'   equivalent list with `$check`.
#' @param dataset_or_study Either a single dataset entry from a study object
#'   (`list(data, meta)`, as returned inside [read_study()]'s result), or a
#'   full study object (`list(datasets, define, ct)`). A full study is
#'   required when `rule` has an `Operations` block that reads from a
#'   different domain than the one being checked (e.g. computing a
#'   `distinct` value from the `TV` dataset while evaluating `SV`).
#' @param domain The dataset's domain code (e.g. `"AE"`), used to resolve
#'   `"--"` variable name templates.
#' @return A logical vector, one element per row of the dataset being
#'   checked: `TRUE` where the record violates the rule. `NA` (from a
#'   comparison against a missing/incomparable value, or an unresolvable
#'   Operations binding) is treated as "not a confirmed violation."
#' @examples
#' data <- data.table::data.table(USUBJID = c("1", "2", "3"), AGE = c(30, 45, 130))
#' dataset <- list(data = data, meta = NULL)
#' rule <- list(check = list(
#'   name = "AGE", operator = "greater_than", value = 120, value_is_literal = TRUE
#' ))
#' evaluate_rule(rule, dataset, domain = "DM")
#' @export
evaluate_rule <- function(rule, dataset_or_study, domain) {
  # Refuse rules that compare against define.xml. This package has no
  # define.xml reader, so the define-side pseudo-columns those rules name
  # (e.g. `define_variable_label`) are simply absent, and
  # resolve_condition_value()'s documented "not a real column -> literal
  # text" fallback would silently turn the comparison into
  # `variable_label != "define_variable_label"` - true for every variable,
  # in the compliant and non-compliant case alike. That is worse than not
  # running the rule: it manufactures confident findings out of missing
  # input. Erroring lets callers record "could not evaluate" (check_study()
  # already reports these under `$skipped`, since none of them are the
  # "Record Data" type it runs) rather than a fabricated verdict.
  if (isTRUE(grepl("Define", rule$rule_type, fixed = TRUE))) {
    stop(
      "rule type '", rule$rule_type,
      "' needs define.xml, which coreval does not read",
      call. = FALSE
    )
  }
  study <- as_study(dataset_or_study, domain)
  dataset <- prepare_dataset_for_rule(rule, study, domain)
  bindings <- operation_bindings_for_rule(rule, study, domain, dataset)

  result <- evaluate_check(rule$check, dataset, domain, bindings, study)
  result[is.na(result)] <- FALSE
  collapse_exploded_violations(dataset, result)
}

# A Match Datasets join can explode one original row into several (see
# match_datasets.R) via `.coreval_row_id`. This function's callers document
# "one result per row of the dataset being checked" - i.e. per ORIGINAL
# row - so exploded per-row results collapse back via "any exploded copy of
# this row violates", matching how CORE-000097 relies on its own Check
# conditions to pick the one matching exploded row per original record.
#' Collapse per-exploded-row results back to one per original row
#' @param dataset The (possibly Match-Datasets-exploded) dataset.
#' @param result A per-row logical vector aligned to `dataset$data`.
#' @return `result` unchanged if there was no join explosion, otherwise
#'   collapsed to one value per original row (`TRUE` if any exploded copy is).
#' @noRd
collapse_exploded_violations <- function(dataset, result) {
  row_id <- dataset$data$.coreval_row_id
  if (is.null(row_id)) {
    return(result)
  }
  # Not tapply()/factor()-based: factor() sorts integer levels as text
  # ("1", "10", "2", ...), which would silently misorder rows past 9.
  vapply(seq_len(max(row_id)), function(i) any(result[row_id == i]), logical(1))
}

# Normalizes either a single dataset (list(data, meta)) or a full study
# (list(datasets, ...)) into a study, so callers can pass whichever they
# have without evaluate_rule() itself needing two code paths downstream.
#' Normalize a single dataset or a full study into a study object
#' @param dataset_or_study Either `list(data, meta)` or a full study object.
#' @param domain Domain code to key a single dataset under.
#' @return A full study object (`list(datasets = ...)`).
#' @noRd
as_study <- function(dataset_or_study, domain) {
  if (!is.null(dataset_or_study$datasets)) {
    dataset_or_study
  } else {
    list(datasets = stats::setNames(list(dataset_or_study), domain))
  }
}

# The dataset actually used for evaluation: the current domain's data with
# Match Datasets joins applied. Exposed so check_study() can build findings
# from the SAME augmented dataset evaluate_rule() checked against - using
# the un-joined dataset there would silently drop any Output Variable that
# only exists on the matched side (e.g. DM.DTHDTC).
#' Get the dataset a rule's Check should run against, with Match Datasets joins applied
#' @param rule A rule record.
#' @param study Full study object.
#' @param domain Domain code being checked.
#' @return The joined dataset, `list(data, meta)`.
#' @noRd
prepare_dataset_for_rule <- function(rule, study, domain) {
  dataset <- study$datasets[[domain]]
  # rule$rule_type is often absent on rules built directly in tests/by
  # callers (defaults to the ordinary record-level path) - %in% a vector of
  # exact strings, rather than switch(), so a NULL/missing rule_type never
  # errors. The "against Library Metadata"/"against Define XML" suffixed
  # variants describe what metadata SOURCE the Check compares against, not
  # a different "what is one row" shape - a rule can be plain "Variable
  # Metadata Check" or "... against Library Metadata" and still need the
  # exact same one-row-per-variable dataset (confirmed against CORE-000902:
  # its Check only needs the LOCAL get_model_column_order Operations
  # binding, no CDISC Library data at all, despite the "against Library
  # Metadata" label - an earlier version's exact-string match sent it down
  # the ordinary record-level path instead, where its pseudo-field
  # `variable_name` doesn't exist as a real column, silently resolving to
  # "no violation" rather than actually evaluating the rule).
  if (isTRUE(rule$rule_type %in% c(
    "Variable Metadata Check", "Variable Metadata Check against Library Metadata",
    "Variable Metadata Check against Define XML"
  ))) {
    return(build_variable_metadata_dataset(dataset))
  }
  if (identical(rule$rule_type, "Dataset Metadata Check")) {
    return(build_dataset_metadata_dataset(dataset, domain))
  }
  if (isTRUE(rule$rule_type %in% c("Value Check with Variable Metadata", "Value Check with Dataset Metadata"))) {
    return(build_variable_value_check_dataset(dataset))
  }
  apply_match_datasets(dataset, rule, study, domain)
}

# Three rule types check metadata FACTS rather than record values, and each
# needs a genuinely different "what is one row" model than the record-level
# default - built once here, upstream of the ordinary Check-tree evaluator,
# so evaluate_check()/evaluate_condition()/assemble_findings() need no
# special-casing at all: the pseudo-field names below (variable_name,
# dataset_name, ...) just become real columns of a synthetic dataset.
#
# - Variable Metadata Check: one row per VARIABLE (from dataset$meta), e.g.
#   "variable_name longer_than 8" - confirmed against CORE-000182's real
#   fixtures, including that "Record" (for Sensitivity: Record rules) is the
#   variable's 1-based position within that dataset's variable list, exactly
#   matching _variables.csv's own row order (CORE-000569).
# - Dataset Metadata Check: a single synthetic row (the dataset-level fact is
#   constant, so N real records would just repeat it) - confirmed against
#   CORE-000357 (Sensitivity: Record), whose reference reports exactly
#   Record = 1 regardless of how many real records the dataset actually has.
# - Value Check with Variable Metadata: one row per (record, variable) pair -
#   confirmed against CORE-000867's real fixtures (multiple different
#   records flagged for the SAME variable, e.g. STUDYID). `.coreval_row_id`
#   is stamped to the ORIGINAL record number so the existing Match-Datasets-
#   style collapse-back-to-one-result-per-original-row machinery in
#   `collapse_exploded_violations()` does the right thing with zero new code.

#' Build a single-row synthetic dataset for a Dataset Metadata Check rule
#'
#' Also carries through the real dataset's own `DOMAIN` variable (its first
#' record's value) - confirmed necessary against CORE-000598 ("the dataset
#' name must begin with the DOMAIN value"), which compares `dataset_name`
#' against the real `DOMAIN` column, not a literal string - a split dataset
#' like `AB` legitimately has `DOMAIN == "LB"` inside its own data.
#' @param real_dataset The domain's real dataset (`list(data, meta)`).
#' @param domain Domain code (used as-is for `dataset_name` - matches the
#'   observed uppercase convention in reference `results.csv` Values).
#' @return A single-row synthetic dataset with columns `dataset_name` and (if present) `DOMAIN`.
#' @noRd
build_dataset_metadata_dataset <- function(real_dataset, domain) {
  cols <- list(dataset_name = domain)
  if ("DOMAIN" %in% names(real_dataset$data)) {
    cols$DOMAIN <- real_dataset$data$DOMAIN[1]
  }
  list(data = data.table::as.data.table(cols), meta = NULL)
}

#' Build a per-variable synthetic dataset for a Variable Metadata Check rule
#' @param real_dataset The domain's real dataset (`list(data, meta)`).
#' @return A synthetic dataset with columns `variable_name`/`variable_label`/`variable_data_type`.
#' @noRd
build_variable_metadata_dataset <- function(real_dataset) {
  meta <- real_dataset$meta
  list(
    data = data.table::data.table(
      variable_name = meta$variable,
      variable_label = meta$label,
      variable_data_type = meta$type
    ),
    meta = NULL
  )
}

#' Build a per-(record, variable) synthetic dataset for a Value Check with Variable Metadata rule
#' @param real_dataset The domain's real dataset (`list(data, meta)`).
#' @return A synthetic dataset with columns `variable_name`/`variable_data_type`/`variable_value`,
#'   `.coreval_row_id` set to the original record number.
#' @noRd
build_variable_value_check_dataset <- function(real_dataset) {
  meta <- real_dataset$meta
  data <- real_dataset$data
  n_records <- nrow(data)
  melted <- lapply(seq_len(nrow(meta)), function(i) {
    v <- meta$variable[i]
    if (!(v %in% names(data))) {
      return(NULL)
    }
    data.table::data.table(
      .coreval_row_id = seq_len(n_records),
      variable_name = v,
      variable_data_type = meta$type[i],
      variable_value = as.character(data[[v]])
    )
  })
  list(data = data.table::rbindlist(melted), meta = NULL)
}

#' Compute a rule's Operations bindings, if it has any
#' @param rule A rule record.
#' @param study Full study object.
#' @param domain Domain code being checked.
#' @param dataset The dataset being checked.
#' @return A named list of bindings (empty if the rule has no Operations).
#' @noRd
operation_bindings_for_rule <- function(rule, study, domain, dataset) {
  if (is.null(rule$operations)) {
    return(list())
  }
  compute_operation_bindings(rule, study, domain, dataset)
}

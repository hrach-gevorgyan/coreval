# Substitutes a dataset's actual 2-letter domain code for a "--" variable
# name template (e.g. "--OCCUR" against domain "AE" -> "AEOCCUR"). This is a
# different use of "--" than the Domains scope wildcard (`SUPP--` etc.) -
# there it means "prefix match"; here it means "this domain's code goes
# here."
#' Substitute a domain code into a `"--"`-prefixed variable name template
#' @param name Variable name, possibly starting with `"--"`.
#' @param domain Domain code to substitute.
#' @return The resolved variable name.
#' @noRd
resolve_var_name <- function(name, domain) {
  ifelse(
    startsWith(name, "--"),
    paste0(toupper(domain), substr(name, 3, nchar(name))),
    name
  )
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
  }
  condition$value
}

#' Evaluate one leaf Check condition against a dataset
#' @param condition One Check condition (`name`, `operator`, optional `value`).
#' @param dataset The dataset being checked.
#' @param domain Domain code, used to resolve `"--"` templates.
#' @param bindings Operations bindings for the current rule.
#' @return A logical vector (recycled from scalar for dataset-level operators).
#' @noRd
evaluate_condition <- function(condition, dataset, domain, bindings = list()) {
  if (is.character(condition$name) && startsWith(condition$name, "$")) {
    binding <- bindings[[condition$name]]
    name <- condition$name
    exists <- !is.null(binding)
    target <- if (exists) resolve_binding(binding, dataset) else NULL
  } else {
    name <- resolve_var_name(condition$name, domain)
    exists <- name %in% names(dataset$data)
    target <- if (exists) dataset$data[[name]] else NULL
  }

  ctx <- list(
    name = name,
    exists = exists,
    target = target,
    value = resolve_condition_value(condition, dataset, domain, bindings),
    n = nrow(dataset$data),
    condition = condition,
    dataset = dataset,
    domain = domain
  )

  op_fn <- get_operator(condition$operator)
  result <- op_fn(ctx)

  if (isTRUE(condition$negative)) {
    result <- !result
  }
  result
}

# Walks an arbitrarily nested Check tree (all/any/not), returning a per-row
# logical vector (recycled from a scalar for dataset-level conditions like
# exists/not_exists). TRUE means the record violates the rule.
#' Recursively evaluate a Check tree (leaf condition, or `all`/`any`/`not`)
#' @param check A Check node.
#' @param dataset The dataset being checked.
#' @param domain Domain code, used to resolve `"--"` templates.
#' @param bindings Operations bindings for the current rule.
#' @return A per-row logical vector; `TRUE` means the record violates the rule.
#' @noRd
evaluate_check <- function(check, dataset, domain, bindings = list()) {
  if (!is.null(check$name) && !is.null(check$operator)) {
    return(evaluate_condition(check, dataset, domain, bindings))
  }
  if (!is.null(check$all)) {
    parts <- lapply(check$all, evaluate_check, dataset = dataset, domain = domain, bindings = bindings)
    return(Reduce(`&`, parts))
  }
  if (!is.null(check$any)) {
    parts <- lapply(check$any, evaluate_check, dataset = dataset, domain = domain, bindings = bindings)
    return(Reduce(`|`, parts))
  }
  if (!is.null(check$not)) {
    return(!evaluate_check(check$not, dataset, domain, bindings))
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
  study <- as_study(dataset_or_study, domain)
  dataset <- prepare_dataset_for_rule(rule, study, domain)
  bindings <- operation_bindings_for_rule(rule, study, domain, dataset)

  result <- evaluate_check(rule$check, dataset, domain, bindings)
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
  apply_match_datasets(study$datasets[[domain]], rule, study, domain)
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

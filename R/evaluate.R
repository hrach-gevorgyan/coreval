# Substitutes a dataset's actual 2-letter domain code for a "--" variable
# name template (e.g. "--OCCUR" against domain "AE" -> "AEOCCUR"). This is a
# different use of "--" than the Domains scope wildcard (`SUPP--` etc.) -
# there it means "prefix match"; here it means "this domain's code goes
# here."
resolve_var_name <- function(name, domain) {
  ifelse(
    startsWith(name, "--"),
    paste0(toupper(domain), substr(name, 3, nchar(name))),
    name
  )
}

# Resolves a condition's comparison target per `value_is_literal` (defaults
# to FALSE/absent - the trap: `value` names a column unless explicitly
# marked literal). Returns NULL if the condition has no `value`, or `value`
# is a vector of column names rather than a single reference - that shape is
# only used by the grouping operators (is_not_unique_set, ...), which read
# the raw names from `condition$value` themselves via ctx$dataset instead.
resolve_condition_value <- function(condition, dataset, domain) {
  if (is.null(condition$value) || length(condition$value) != 1) {
    return(NULL)
  }
  if (isTRUE(condition$value_is_literal)) {
    return(condition$value)
  }
  ref_name <- resolve_var_name(condition$value, domain)
  if (ref_name %in% names(dataset$data)) dataset$data[[ref_name]] else NULL
}

evaluate_condition <- function(condition, dataset, domain) {
  name <- resolve_var_name(condition$name, domain)
  exists <- name %in% names(dataset$data)
  ctx <- list(
    name = name,
    exists = exists,
    target = if (exists) dataset$data[[name]] else NULL,
    value = resolve_condition_value(condition, dataset, domain),
    n = nrow(dataset$data),
    condition = condition,
    dataset = dataset
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
evaluate_check <- function(check, dataset, domain) {
  if (!is.null(check$name) && !is.null(check$operator)) {
    return(evaluate_condition(check, dataset, domain))
  }
  if (!is.null(check$all)) {
    parts <- lapply(check$all, evaluate_check, dataset = dataset, domain = domain)
    return(Reduce(`&`, parts))
  }
  if (!is.null(check$any)) {
    parts <- lapply(check$any, evaluate_check, dataset = dataset, domain = domain)
    return(Reduce(`|`, parts))
  }
  if (!is.null(check$not)) {
    return(!evaluate_check(check$not, dataset, domain))
  }
  stop("Unrecognized Check node: ", paste(names(check), collapse = ", "))
}

#' Evaluate one rule's Check against one dataset
#'
#' @param rule A rule record, e.g. `.coreval_env$data$rules[[id]]` or an
#'   equivalent list with `$check`.
#' @param dataset A single dataset entry from a study object:
#'   `list(data, meta)`, as returned inside [read_study()]'s result.
#' @param domain The dataset's domain code (e.g. `"AE"`), used to resolve
#'   `"--"` variable name templates.
#' @return A logical vector, one element per row of `dataset$data`: `TRUE`
#'   where the record violates the rule. `NA` (from a comparison against a
#'   missing/incomparable value) is treated as "not a confirmed violation."
#' @export
evaluate_rule <- function(rule, dataset, domain) {
  result <- evaluate_check(rule$check, dataset, domain)
  result[is.na(result)] <- FALSE
  result
}

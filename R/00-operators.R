.operator_registry <- new.env(parent = emptyenv())

#' Register a Check condition operator implementation
#' @param name Operator name as it appears in a rule's `operator` field.
#' @param fn Function of one `ctx` argument (see `evaluate_condition()`), returning a logical vector.
#' @noRd
register_operator <- function(name, fn) {
  assign(name, fn, envir = .operator_registry)
}

#' Look up a registered operator implementation by name
#' @param name Operator name.
#' @return The operator's function.
#' @noRd
get_operator <- function(name) {
  if (!exists(name, envir = .operator_registry, inherits = FALSE)) {
    stop("Unimplemented operator: ", name, call. = FALSE)
  }
  get(name, envir = .operator_registry, inherits = FALSE)
}

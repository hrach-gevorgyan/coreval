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

#' Build an operator that returns NA when the target/value don't exist, otherwise runs `fn(ctx)`
#'
#' Most operators share the exact same "can't evaluate this row" guard
#' (`!ctx$exists || is.null(ctx$value)` -> `NA` for every row); this factory
#' centralizes it so each operator only needs to supply its actual logic.
#' @param fn Function of `ctx` returning a logical vector, called only once the guard passes.
#' @return An operator function of `ctx`.
#' @noRd
guarded_op <- function(fn) {
  function(ctx) {
    if (!ctx$exists || is.null(ctx$value)) {
      return(rep(NA, ctx$n))
    }
    fn(ctx)
  }
}

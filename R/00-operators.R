.operator_registry <- new.env(parent = emptyenv())

register_operator <- function(name, fn) {
  assign(name, fn, envir = .operator_registry)
}

get_operator <- function(name) {
  if (!exists(name, envir = .operator_registry, inherits = FALSE)) {
    stop("Unimplemented operator: ", name, call. = FALSE)
  }
  get(name, envir = .operator_registry, inherits = FALSE)
}

#' Build a scalar/vector comparison operator from a two-argument comparator
#' @param fn Function of `(target, value)` returning a logical vector.
#' @return An operator function of `ctx`.
#' @noRd
compare_op <- function(fn) {
  function(ctx) {
    if (!ctx$exists || is.null(ctx$value)) {
      return(rep(NA, ctx$n))
    }
    fn(ctx$target, ctx$value)
  }
}

# Operators: equal_to / not_equal_to / less_than / less_than_or_equal_to /
# greater_than / greater_than_or_equal_to, and case-insensitive equality variants
register_operator("equal_to", compare_op(function(t, v) t == v))
register_operator("not_equal_to", compare_op(function(t, v) t != v))
register_operator("less_than", compare_op(function(t, v) t < v))
register_operator("less_than_or_equal_to", compare_op(function(t, v) t <= v))
register_operator("greater_than", compare_op(function(t, v) t > v))
register_operator("greater_than_or_equal_to", compare_op(function(t, v) t >= v))
register_operator("equal_to_case_insensitive", compare_op(function(t, v) toupper(t) == toupper(v)))
register_operator("not_equal_to_case_insensitive", compare_op(function(t, v) toupper(t) != toupper(v)))

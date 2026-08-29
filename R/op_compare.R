compare_op <- function(fn) {
  function(ctx) {
    if (!ctx$exists || is.null(ctx$value)) {
      return(rep(NA, ctx$n))
    }
    fn(ctx$target, ctx$value)
  }
}

register_operator("equal_to", compare_op(function(t, v) t == v))
register_operator("not_equal_to", compare_op(function(t, v) t != v))
register_operator("less_than", compare_op(function(t, v) t < v))
register_operator("less_than_or_equal_to", compare_op(function(t, v) t <= v))
register_operator("greater_than", compare_op(function(t, v) t > v))
register_operator("greater_than_or_equal_to", compare_op(function(t, v) t >= v))
register_operator("equal_to_case_insensitive", compare_op(function(t, v) toupper(t) == toupper(v)))
register_operator("not_equal_to_case_insensitive", compare_op(function(t, v) toupper(t) != toupper(v)))

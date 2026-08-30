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

#' Build an ordinal (`<`/`<=`/`>`/`>=`) comparison operator, coercing a
#' numeric-looking string to a real number when compared against a numeric
#' column
#' @param fn Function of `(target, value)` returning a logical vector.
#' @return An operator function of `ctx`.
#' @noRd
ordinal_compare_op <- function(fn) {
  function(ctx) {
    if (!ctx$exists || is.null(ctx$value)) {
      return(rep(NA, ctx$n))
    }
    target <- ctx$target
    value <- ctx$value
    # If one side is numeric and the other is a numeric-looking string
    # (e.g. a quoted literal `value: "65"` against a Num column, or a
    # comparator resolved as text), base R's `<`/`>` would otherwise coerce
    # the NUMBER to a STRING (since one side is character) and compare
    # lexicographically - "9" > "65" is TRUE character-wise, even though
    # 9 > 65 is FALSE numerically. Only coerce when the string side parses
    # cleanly as numeric everywhere it isn't already NA/blank, so a
    # genuine text ordinal comparison (two character columns) is untouched.
    parses_as_numeric <- function(x) {
      x_num <- suppressWarnings(as.numeric(x))
      !any(is.na(x_num) & !is.na(x) & x != "")
    }
    if (is.numeric(target) && is.character(value) && parses_as_numeric(value)) {
      value <- suppressWarnings(as.numeric(value))
    } else if (is.numeric(value) && is.character(target) && parses_as_numeric(target)) {
      target <- suppressWarnings(as.numeric(target))
    }
    fn(target, value)
  }
}

# Operators: equal_to / not_equal_to / less_than / less_than_or_equal_to /
# greater_than / greater_than_or_equal_to, and case-insensitive equality variants
register_operator("equal_to", compare_op(function(t, v) t == v))
register_operator("not_equal_to", compare_op(function(t, v) t != v))
register_operator("less_than", ordinal_compare_op(function(t, v) t < v))
register_operator("less_than_or_equal_to", ordinal_compare_op(function(t, v) t <= v))
register_operator("greater_than", ordinal_compare_op(function(t, v) t > v))
register_operator("greater_than_or_equal_to", ordinal_compare_op(function(t, v) t >= v))
register_operator("equal_to_case_insensitive", compare_op(function(t, v) toupper(t) == toupper(v)))
register_operator("not_equal_to_case_insensitive", compare_op(function(t, v) toupper(t) != toupper(v)))

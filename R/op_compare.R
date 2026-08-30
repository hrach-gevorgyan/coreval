#' Normalize a value for a `type_insensitive` comparison (numeric strings
#' compare by value, not by formatting - "200.00" and "200" are equal)
#' @param x A vector.
#' @return A character vector, canonical-numeric where `x` parses as numeric.
#' @noRd
canonicalize_numeric_string <- function(x) {
  x_chr <- trimws(as.character(x))
  num <- suppressWarnings(as.numeric(x_chr))
  # as.character() on a numeric formats each element independently ("200"
  # stays "200", "200.01" stays "200.01") - format() was tried first but
  # rejected: format() aligns decimal places across the WHOLE vector, so
  # c(200, 200.01) becomes c("200.00", "200.01") instead of c("200", "200.01").
  ifelse(is.na(num) | x_chr == "", x_chr, as.character(num))
}

#' Build a scalar/vector comparison operator from a two-argument comparator
#' @param fn Function of `(target, value)` returning a logical vector.
#' @return An operator function of `ctx`.
#' @noRd
compare_op <- function(fn) {
  function(ctx) {
    if (!ctx$exists || is.null(ctx$value)) {
      return(rep(NA, ctx$n))
    }
    target <- ctx$target
    value <- ctx$value
    # `type_insensitive` means numeric-looking values compare by VALUE, not
    # by formatting - "200.00" and "200" (or the number 200) are equal.
    # Confirmed against CORE-000542's real fixtures: LBSTRESC="200.00"
    # (character) vs LBSTRESN=200 (numeric) must NOT be flagged as
    # not_equal_to, even though they differ as raw strings.
    if (isTRUE(ctx$condition$type_insensitive)) {
      target <- canonicalize_numeric_string(target)
      value <- canonicalize_numeric_string(value)
    }
    result <- fn(target, value)
    # Clinical-data equality convention: two BLANK values are never
    # "equal" and never "not equal" to each other - both resolve to FALSE,
    # matching the reference engine's own truth table (`_check_equality`/
    # `_check_inequality` in check_operators/dataframe_operators.py: "''
    # or null" vs "'' or null" -> False for BOTH operators). Confirmed
    # against CORE-000195's real fixture: a row with AESCAT and AEDECOD
    # both blank must NOT be flagged by equal_to_case_insensitive, even
    # though "" == "" is naturally TRUE in R.
    both_blank <- is_blank(ctx$target) & is_blank(ctx$value)
    result[both_blank] <- FALSE
    result
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

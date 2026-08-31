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
    # Clinical-data equality convention, straight from the reference
    # engine's `_check_equality`/`_check_inequality`
    # (check_operators/dataframe_operators.py). Both compute
    # `both_null = is_null_or_empty(comparison) & is_null_or_empty(target)`,
    # return FALSE when that holds, and otherwise fall through to a plain
    # `==` / `!=`. So:
    #
    #   equal_to      either side blank  -> FALSE (never equal)
    #   not_equal_to  both sides blank   -> FALSE (not a difference)
    #   not_equal_to  exactly one blank  -> TRUE  (a real difference)
    #
    # ...with one necessary distinction the truth table doesn't make. A
    # blank COMPARATOR means two different things depending on where it came
    # from:
    #
    #   * a real per-row COLUMN that happens to be blank on this row - a
    #     genuine "populated vs missing" difference, which the reference
    #     flags (CORE-001082: a variable defined in neither the IG nor the
    #     SDTM Model has no library_variable_data_type to compare against,
    #     and the reference reports that as a mismatch).
    #   * an Operations AGGREGATE that resolved to nothing - e.g.
    #     CORE-000454's `$max_ex_exendtc`, a `max_date` over an all-blank
    #     column. Its fixture expects NO violation there: "the aggregate
    #     could not be computed" is not a difference between two values.
    #
    # `is_blank()` cannot tell those apart, so resolve_condition_value()
    # marks the comparator's PROVENANCE as it resolves it, and the
    # comparator half of the truth table is applied only to genuinely
    # per-row comparators. Length was tried as the discriminator first and
    # is wrong: on a single-row dataset a scalar aggregate and a per-row
    # column are both length 1, which silently disabled the rule for exactly
    # the one-row CO/SUPP datasets that need it (CORE-000206).
    #
    # The target half needs no such qualification - CORE-000552/553 pin it:
    # not_equal_to must be TRUE when the target (--STDY/--ENDY) is a genuine
    # per-row blank and the comparator is populated.
    target_blank <- is_blank(ctx$target)
    value_blank <- is_blank(ctx$value)
    value_is_per_row <- isTRUE(attr(ctx$value, "coreval_per_row"))
    is_negation <- startsWith(ctx$condition$operator, "not_")
    if (is_negation) {
      result[target_blank & !value_blank] <- TRUE
      if (value_is_per_row) {
        result[!target_blank & value_blank] <- TRUE
        result[target_blank & value_blank] <- FALSE
      }
    } else {
      result[target_blank] <- FALSE
      if (value_is_per_row) {
        result[value_blank] <- FALSE
      }
    }
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

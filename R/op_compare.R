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

#' Is this operand a set per row (the shape a grouped Operations binding has)?
#' @param x An operand.
#' @return `TRUE` for a list column.
#' @noRd
is_set_valued <- function(x) is.list(x) && !is.data.frame(x)

#' Compare set-valued operands row by row
#'
#' A grouped Operations binding resolves to one SET per row, not one value, so
#' `==` on it raises "comparison of these types is not implemented" and the
#' whole rule stops running. The reference has no such problem: `equal_to` and
#' `not_equal_to` are `apply(axis=1)` over `_check_equality`/`_check_inequality`
#' (dataframe_operators.py:307-395), where a cell holding a Python list is
#' compared with plain `==`, which is ordered element-wise equality. Grouped
#' `distinct` sorts and deduplicates every group (distinct.py's
#' `_apply_dropna_list` is `sorted(x.dropna())` over `drop_duplicates`), so on
#' the operands that actually occur, ordered equality and set equality agree.
#' Ordered is what is written here, because that is what the reference does.
#'
#' Both sides null or empty is FALSE for equality and inequality alike, which
#' is the reference's own truth table (`both_null -> return False` in both
#' helpers), and `pd.isna()` on an empty list is vacuously all-true so an empty
#' set counts as null. The aggregate-provenance exception in the scalar path
#' below is deliberately NOT applied here: it exists for a scalar aggregate
#' that resolved to nothing (CORE-000454) and was measured there.
#'
#' @param eq `TRUE` for equality, `FALSE` for inequality.
#' @return A function of `(target, value, n)` returning a logical vector.
#' @noRd
set_compare <- function(eq) {
  function(target, value, n) {
    as_rows <- function(x) if (is_set_valued(x)) rep_len(x, n) else as.list(rep_len(x, n))
    t_rows <- as_rows(target)
    v_rows <- as_rows(value)
    vapply(seq_len(n), function(i) {
      a <- t_rows[[i]]
      b <- v_rows[[i]]
      a_null <- length(a) == 0 || all(is_blank(a))
      b_null <- length(b) == 0 || all(is_blank(b))
      if (a_null && b_null) {
        return(FALSE)
      }
      same <- identical(as.character(a), as.character(b))
      if (eq) same else !same
    }, logical(1))
  }
}

#' Build a scalar/vector comparison operator from a two-argument comparator
#' @param fn Function of `(target, value)` returning a logical vector.
#' @param set_fn Row-wise comparator used when either operand is set-valued.
#' @return An operator function of `ctx`.
#' @noRd
compare_op <- function(fn, set_fn = NULL) {
  function(ctx) {
    if (!ctx$exists || is.null(ctx$value)) {
      return(rep(NA, ctx$n))
    }
    target <- ctx$target
    value <- ctx$value
    if (is_set_valued(target) || is_set_valued(value)) {
      if (is.null(set_fn)) {
        stop("comparison of set-valued operands is not implemented for ",
             ctx$condition$operator, call. = FALSE)
      }
      return(set_fn(target, value, ctx$n))
    }
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
    # An ordinal comparison against a SET has no meaning, and R will not say
    # so: `list(c("1","2"), c("3")) < "2"` does not raise, it deparses each
    # element and compares `c("1", "2")` as a string, answering FALSE FALSE.
    # That is an answer nobody can tell from a correct one. Refuse instead,
    # which check_study() records as a SKIPPED row naming the operator.
    if (is_set_valued(target) || is_set_valued(value)) {
      stop("comparison of set-valued operands is not implemented for ",
           ctx$condition$operator, call. = FALSE)
    }
    # If one side is numeric and the other is a numeric-looking string
    # (e.g. a quoted literal `value: "65"` against a Num column, or a
    # comparator resolved as text), base R's `<`/`>` would otherwise coerce
    # the NUMBER to a STRING (since one side is character) and compare
    # lexicographically - "9" > "65" is TRUE character-wise, even though
    # 9 > 65 is FALSE numerically. Only coerce when the string side parses
    # cleanly as numeric everywhere it isn't already NA/blank, so a genuine
    # text ordinal comparison is untouched.
    #
    # The same trap catches two CHARACTER columns compared against each other,
    # which is the common case in SDTM - every variable read from an XPT is
    # text. CORE-000698 compares PDVALTRG against PDVALMIN; with the values
    # "1000" and "999" a lexicographic `<` says TRUE, so coreval reported a
    # target below its own minimum where there was none. Both sides parsing
    # cleanly as numbers is the signal that a numeric comparison was meant.
    parses_as_numeric <- function(x) {
      x_num <- suppressWarnings(as.numeric(x))
      !any(is.na(x_num) & !is.na(x) & x != "")
    }
    if (is.numeric(target) && is.character(value) && parses_as_numeric(value)) {
      value <- suppressWarnings(as.numeric(value))
    } else if (is.numeric(value) && is.character(target) && parses_as_numeric(target)) {
      target <- suppressWarnings(as.numeric(target))
    } else if (is.character(target) && is.character(value)) {
      # Two character columns. A whole-column gate is no use here: the columns
      # these rules compare are usually mixed, holding numbers on the rows the
      # rule cares about and text elsewhere (CORE-000698's PDVALTRG carries
      # "1000" and "YES" in the same column). So decide per row, and only where
      # BOTH sides parse - every other row keeps the plain string comparison it
      # had before, which leaves genuine text ordinals untouched.
      n <- max(length(target), length(value))
      target_num <- suppressWarnings(as.numeric(target))
      value_num <- suppressWarnings(as.numeric(value))
      both <- rep_len(!is.na(target_num), n) & rep_len(!is.na(value_num), n)
      if (any(both)) {
        result <- rep_len(fn(target, value), n)
        result[both] <- rep_len(fn(target_num, value_num), n)[both]
        return(result)
      }
    }
    fn(target, value)
  }
}

# Operators: equal_to / not_equal_to / less_than / less_than_or_equal_to /
# greater_than / greater_than_or_equal_to, and case-insensitive equality variants
register_operator("equal_to", compare_op(function(t, v) t == v, set_compare(TRUE)))
register_operator("not_equal_to", compare_op(function(t, v) t != v, set_compare(FALSE)))
register_operator("less_than", ordinal_compare_op(function(t, v) t < v))
register_operator("less_than_or_equal_to", ordinal_compare_op(function(t, v) t <= v))
register_operator("greater_than", ordinal_compare_op(function(t, v) t > v))
register_operator("greater_than_or_equal_to", ordinal_compare_op(function(t, v) t >= v))
register_operator("equal_to_case_insensitive", compare_op(function(t, v) toupper(t) == toupper(v)))
register_operator("not_equal_to_case_insensitive", compare_op(function(t, v) toupper(t) != toupper(v)))
# Which of these ever meets a set, across the 1054-rule build: `not_equal_to`
# on exactly one rule (CORE-000877, two grouped `distinct` operations compared
# against each other), and `equal_to`, the case-insensitive pair and every
# ordinal operator on none. So `set_compare(TRUE)` is not exercised by any rule
# today; it is here because the reference computes equality and inequality from
# one shared helper pair, inverting a single line
# (dataframe_operators.py:189-303), and splitting them would be the invention.
# The ordinal and case-insensitive operators get no set_fn: there is nothing to
# measure a semantics for them against, and guessing one is how a check comes
# to quietly answer something plausible. They refuse.

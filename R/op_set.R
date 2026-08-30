# `ctx$value` is normally one set used for every row (`%in%` handles that
# directly). But a grouped `distinct` Operations binding (e.g. "the set of
# values seen for this row's own USUBJID") produces a *row-varying* list -
# one set per row - which needs an elementwise check instead.
#' Shared `%in%` check for `is_contained_by`/`is_not_contained_by`, row-varying or scalar
#' @param ctx Operator context, see `evaluate_condition()`.
#' @return A logical vector.
#' @noRd
membership_check <- function(ctx) {
  if (is.list(ctx$value) && length(ctx$value) == ctx$n) {
    vapply(seq_len(ctx$n), function(i) ctx$target[i] %in% ctx$value[[i]], logical(1))
  } else {
    ctx$target %in% ctx$value
  }
}

# Operator: is_contained_by - target's value is a member of value
register_operator("is_contained_by", guarded_op(membership_check))

# Operator: is_not_contained_by - negation of is_contained_by
register_operator("is_not_contained_by", guarded_op(function(ctx) !membership_check(ctx)))

# Dataset-level (scalar, like exists/not_exists): does the target column's
# set of values contain ALL of the expected values? An unresolvable
# `value` (e.g. $required_variables against a non-SDTMIG study, which
# sdtmig_variables_for() deliberately returns NULL for rather than
# guessing) must stay NA (unresolvable), not hard-code to FALSE - a NULL
# value is never a legitimate "the set of required values is empty" fact
# (that case is a real, empty character(0) vector instead, which
# `all(character(0) %in% target)` already handles correctly as
# vacuously TRUE). Confirmed against CORE-000355's real fixture: coding
# unresolvable as FALSE made not_contains_all's negation wrongly TRUE
# (a "violation") for a domain this rule can't actually evaluate.
#
# The verdict attaches to the FIRST RECORD ONLY, not to every row. The
# reference engine's `contains_all` computes a bare Python bool and hands
# it to `convert_to_series()`, which for a scalar returns `pd.Series(x)` -
# a LENGTH-1 series indexed at 0 - never a broadcast one. It pointedly
# does NOT use the sibling `get_series_from_value()` helper (the one that
# passes `index=self._data.index`), and operators that really do mean
# "every row" broadcast explicitly instead, e.g. `exists` writes
# `convert_to_series([True] * len(self.value))`. Upstream's own unit test
# pins this down: `test_contains_all` runs a 3-row dataset and asserts
# `result.equals(df.convert_to_series(expected_result))` against a SCALAR
# expected value. When that length-1 series is then combined with a
# length-n sibling condition, pandas index alignment fills rows 2..n with
# NaN, which its boolean ops treat as FALSE - so only record 1 can ever
# carry the verdict. Confirmed against CORE-000737/740/741's real
# fixtures, whose results.csv each report exactly one record despite
# every row satisfying the check.
#
# Padding with FALSE reproduces that fill exactly (FALSE is the identity
# for `|` and absorbing for `&`). The unresolvable-NA case above stays a
# bare scalar so `evaluate_condition()`'s `rep_len()` still broadcasts it
# to every row - "this rule can't be evaluated here" is genuinely a
# whole-dataset fact, unlike the verdict itself.
#' Attach a dataset-level verdict to record 1 only, padding later rows FALSE
#' @param x Scalar logical verdict.
#' @param n Number of rows in the dataset.
#' @return A logical vector of length `n`.
#' @noRd
verdict_on_first_row <- function(x, n) {
  if (n < 1L) {
    return(logical(0))
  }
  c(isTRUE(x), rep(FALSE, n - 1L))
}

# Operator: contains_all - dataset-level: target column's values cover all of value
register_operator("contains_all", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(NA)
  }
  verdict_on_first_row(all(ctx$value %in% ctx$target), ctx$n)
})

# Operator: not_contains_all - negation of contains_all. The reference
# engine negates with `~self.contains_all(...)`, i.e. BEFORE any index
# alignment, so the negation applies to the scalar verdict and the
# first-row-only shape is preserved rather than inverted into "every row
# but the first".
register_operator("not_contains_all", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(NA)
  }
  verdict_on_first_row(!all(ctx$value %in% ctx$target), ctx$n)
})

# Both operators below compare SETS/SEQUENCES, so their target and value are
# normally `$`-bound Operations bindings that resolve to a list (one
# collection per row) rather than a plain column. A scalar is treated as a
# one-element collection, matching the reference engine's own
# `set(row[t]) if isinstance(row[t], (list, set)) else {row[t]}`.
#' Coerce an operator side to a per-row list of collections
#' @param x A list (one collection per row) or an atomic vector.
#' @param n Number of rows.
#' @return A list of length `n`.
#' @noRd
as_row_collections <- function(x, n) {
  # A LIST is already one collection per row (a grouped `distinct` binding).
  # An atomic vector is a single collection that applies to every row - a
  # scalar binding like `$dataset_variables` IS the whole variable list, so
  # it must be repeated whole, not split into one element per row.
  if (is.list(x)) {
    return(rep_len(x, n))
  }
  rep(list(x), n)
}

# Operator: shares_no_elements_with - target and value have an empty intersection
register_operator("shares_no_elements_with", guarded_op(function(ctx) {
  targets <- as_row_collections(ctx$target, ctx$n)
  values <- as_row_collections(ctx$value, ctx$n)
  vapply(seq_len(ctx$n), function(i) {
    length(intersect(targets[[i]], values[[i]])) == 0
  }, logical(1))
}))

# Every element of the target must appear in the comparator AND their
# positions there must ascend - i.e. the target is a subsequence of the
# comparator, order preserved. A target element missing from the comparator
# is FALSE outright, per the reference's own early return. Used to check a
# dataset's variable order against the standard's (CORE-000852).
# Operator: is_ordered_subset_of - target is an order-preserving subsequence of value
register_operator("is_ordered_subset_of", guarded_op(function(ctx) {
  targets <- as_row_collections(ctx$target, ctx$n)
  values <- as_row_collections(ctx$value, ctx$n)
  vapply(seq_len(ctx$n), function(i) {
    positions <- match(targets[[i]], values[[i]])
    if (anyNA(positions)) {
      return(FALSE)
    }
    identical(positions, sort(positions))
  }, logical(1))
}))

# Operator: is_not_ordered_subset_of - negation of is_ordered_subset_of
register_operator("is_not_ordered_subset_of", function(ctx) {
  !get_operator("is_ordered_subset_of")(ctx)
})

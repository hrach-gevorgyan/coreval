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
# Operator: contains_all - dataset-level: target column's values cover all of value
register_operator("contains_all", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(NA)
  }
  all(ctx$value %in% ctx$target)
})

# Operator: not_contains_all - negation of contains_all
register_operator("not_contains_all", function(ctx) {
  !get_operator("contains_all")(ctx)
})

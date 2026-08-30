# `ctx$value` is normally one set used for every row (`%in%` handles that
# directly). But a grouped `distinct` Operations binding (e.g. "the set of
# values seen for this row's own USUBJID") produces a *row-varying* list -
# one set per row - which needs an elementwise check instead.
membership_check <- function(ctx) {
  if (is.list(ctx$value) && length(ctx$value) == ctx$n) {
    vapply(seq_len(ctx$n), function(i) ctx$target[i] %in% ctx$value[[i]], logical(1))
  } else {
    ctx$target %in% ctx$value
  }
}

register_operator("is_contained_by", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  membership_check(ctx)
})

register_operator("is_not_contained_by", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  !membership_check(ctx)
})

# Dataset-level (scalar, like exists/not_exists): does the target column's
# set of values contain ALL of the expected values?
register_operator("contains_all", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(FALSE)
  }
  all(ctx$value %in% ctx$target)
})

register_operator("not_contains_all", function(ctx) {
  !get_operator("contains_all")(ctx)
})

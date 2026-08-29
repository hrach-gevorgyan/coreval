register_operator("is_contained_by", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  ctx$target %in% ctx$value
})

register_operator("is_not_contained_by", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  !(ctx$target %in% ctx$value)
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

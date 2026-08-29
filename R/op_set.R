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

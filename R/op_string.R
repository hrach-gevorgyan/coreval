register_operator("matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  grepl(ctx$value, ctx$target, perl = TRUE)
})

register_operator("not_matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  !grepl(ctx$value, ctx$target, perl = TRUE)
})

register_operator("longer_than", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  nchar(ctx$target) > ctx$value
})

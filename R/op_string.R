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

register_operator("shorter_than", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  nchar(ctx$target) < ctx$value
})

# target contains the literal substring `value` (value can be a vector -
# matches if target contains ANY of them).
register_operator("contains", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  Reduce(`|`, lapply(ctx$value, function(v) grepl(v, ctx$target, fixed = TRUE)))
})

register_operator("does_not_contain", function(ctx) {
  !get_operator("contains")(ctx)
})

register_operator("starts_with", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  Reduce(`|`, lapply(ctx$value, function(v) startsWith(ctx$target, v)))
})

register_operator("ends_with", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  Reduce(`|`, lapply(ctx$value, function(v) endsWith(ctx$target, v)))
})

register_operator("has_equal_length", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  if (is.numeric(ctx$value)) nchar(ctx$target) == ctx$value else nchar(ctx$target) == nchar(ctx$value)
})

register_operator("has_not_equal_length", function(ctx) {
  !get_operator("has_equal_length")(ctx)
})

register_operator("is_contained_by_case_insensitive", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  toupper(ctx$target) %in% toupper(ctx$value)
})

register_operator("is_not_contained_by_case_insensitive", function(ctx) {
  !get_operator("is_contained_by_case_insensitive")(ctx)
})

# prefix/suffix regex: search `pattern` within the first/last N characters of
# target, where N comes from the condition's `prefix`/`suffix` field.
register_operator("prefix_matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  n <- ctx$condition$prefix
  grepl(ctx$value, substr(ctx$target, 1, n), perl = TRUE)
})

register_operator("not_prefix_matches_regex", function(ctx) {
  !get_operator("prefix_matches_regex")(ctx)
})

register_operator("suffix_matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  n <- ctx$condition$suffix
  len <- nchar(ctx$target)
  grepl(ctx$value, substr(ctx$target, pmax(len - n + 1, 1), len), perl = TRUE)
})

register_operator("not_suffix_matches_regex", function(ctx) {
  !get_operator("suffix_matches_regex")(ctx)
})

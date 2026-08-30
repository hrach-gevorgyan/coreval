# Operator: matches_regex - target matches the given Perl regex
register_operator("matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  grepl(ctx$value, ctx$target, perl = TRUE)
})

# Operator: not_matches_regex - negation of matches_regex
register_operator("not_matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  !grepl(ctx$value, ctx$target, perl = TRUE)
})

# Operator: longer_than - target's character length exceeds value
register_operator("longer_than", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  nchar(ctx$target) > ctx$value
})

# Operator: shorter_than - target's character length is less than value
register_operator("shorter_than", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  nchar(ctx$target) < ctx$value
})

# target contains the literal substring `value` (value can be a vector -
# matches if target contains ANY of them).
# Operator: contains - target contains any of value as a literal substring
register_operator("contains", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  Reduce(`|`, lapply(ctx$value, function(v) grepl(v, ctx$target, fixed = TRUE)))
})

# Operator: does_not_contain - negation of contains
register_operator("does_not_contain", function(ctx) {
  !get_operator("contains")(ctx)
})

# Operator: starts_with - target starts with any of value
register_operator("starts_with", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  Reduce(`|`, lapply(ctx$value, function(v) startsWith(ctx$target, v)))
})

# Operator: ends_with - target ends with any of value
register_operator("ends_with", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  Reduce(`|`, lapply(ctx$value, function(v) endsWith(ctx$target, v)))
})

# Operator: has_equal_length - target's length equals value (a number or reference string)
register_operator("has_equal_length", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  if (is.numeric(ctx$value)) nchar(ctx$target) == ctx$value else nchar(ctx$target) == nchar(ctx$value)
})

# Operator: has_not_equal_length - negation of has_equal_length
register_operator("has_not_equal_length", function(ctx) {
  !get_operator("has_equal_length")(ctx)
})

# Operator: is_contained_by_case_insensitive - target matches value set, ignoring case
register_operator("is_contained_by_case_insensitive", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  toupper(ctx$target) %in% toupper(ctx$value)
})

# Operator: is_not_contained_by_case_insensitive - negation of is_contained_by_case_insensitive
register_operator("is_not_contained_by_case_insensitive", function(ctx) {
  !get_operator("is_contained_by_case_insensitive")(ctx)
})

# prefix/suffix regex: search `pattern` within the first/last N characters of
# target, where N comes from the condition's `prefix`/`suffix` field.
# Operator: prefix_matches_regex - regex matches within the first N characters of target
register_operator("prefix_matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  n <- ctx$condition$prefix
  grepl(ctx$value, substr(ctx$target, 1, n), perl = TRUE)
})

# Operator: not_prefix_matches_regex - negation of prefix_matches_regex
register_operator("not_prefix_matches_regex", function(ctx) {
  !get_operator("prefix_matches_regex")(ctx)
})

# Operator: suffix_matches_regex - regex matches within the last N characters of target
register_operator("suffix_matches_regex", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(NA, ctx$n))
  }
  n <- ctx$condition$suffix
  len <- nchar(ctx$target)
  grepl(ctx$value, substr(ctx$target, pmax(len - n + 1, 1), len), perl = TRUE)
})

# Operator: not_suffix_matches_regex - negation of suffix_matches_regex
register_operator("not_suffix_matches_regex", function(ctx) {
  !get_operator("suffix_matches_regex")(ctx)
})

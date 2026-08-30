# Operator: matches_regex - target matches the given Perl regex
register_operator("matches_regex", guarded_op(function(ctx) {
  grepl(ctx$value, ctx$target, perl = TRUE)
}))

# Operator: not_matches_regex - negation of matches_regex
register_operator("not_matches_regex", guarded_op(function(ctx) {
  !grepl(ctx$value, ctx$target, perl = TRUE)
}))

# Operator: longer_than - target's character length exceeds value
register_operator("longer_than", guarded_op(function(ctx) {
  nchar(ctx$target) > ctx$value
}))

# Operator: shorter_than - target's character length is less than value
register_operator("shorter_than", guarded_op(function(ctx) {
  nchar(ctx$target) < ctx$value
}))

#' OR a match function across every element of a (possibly multi-value) comparator
#' @param target Target vector.
#' @param values Comparator values, matches if target matches ANY of them.
#' @param match_fn Function of `(target, one_value)` returning a logical vector.
#' @return A logical vector.
#' @noRd
any_value_match <- function(target, values, match_fn) {
  Reduce(`|`, lapply(values, function(v) match_fn(target, v)))
}

# target contains the literal substring `value` (value can be a vector -
# matches if target contains ANY of them).
# Operator: contains - target contains any of value as a literal substring
register_operator("contains", guarded_op(function(ctx) {
  any_value_match(ctx$target, ctx$value, function(t, v) grepl(v, t, fixed = TRUE))
}))

# Operator: does_not_contain - negation of contains
register_operator("does_not_contain", function(ctx) {
  !get_operator("contains")(ctx)
})

# Operator: starts_with - target starts with any of value
register_operator("starts_with", guarded_op(function(ctx) {
  any_value_match(ctx$target, ctx$value, startsWith)
}))

# Operator: ends_with - target ends with any of value
register_operator("ends_with", guarded_op(function(ctx) {
  any_value_match(ctx$target, ctx$value, endsWith)
}))

# Operator: has_equal_length - target's length equals value (a number or reference string)
register_operator("has_equal_length", guarded_op(function(ctx) {
  if (is.numeric(ctx$value)) nchar(ctx$target) == ctx$value else nchar(ctx$target) == nchar(ctx$value)
}))

# Operator: has_not_equal_length - negation of has_equal_length
register_operator("has_not_equal_length", function(ctx) {
  !get_operator("has_equal_length")(ctx)
})

# Operator: is_contained_by_case_insensitive - target matches value set, ignoring case
register_operator("is_contained_by_case_insensitive", guarded_op(function(ctx) {
  toupper(ctx$target) %in% toupper(ctx$value)
}))

# Operator: is_not_contained_by_case_insensitive - negation of is_contained_by_case_insensitive
register_operator("is_not_contained_by_case_insensitive", function(ctx) {
  !get_operator("is_contained_by_case_insensitive")(ctx)
})

# prefix/suffix regex: search `pattern` within the first/last N characters of
# target, where N comes from the condition's `prefix`/`suffix` field.
# Operator: prefix_matches_regex - regex matches within the first N characters of target
register_operator("prefix_matches_regex", guarded_op(function(ctx) {
  n <- ctx$condition$prefix
  grepl(ctx$value, substr(ctx$target, 1, n), perl = TRUE)
}))

# Operator: not_prefix_matches_regex - negation of prefix_matches_regex
register_operator("not_prefix_matches_regex", function(ctx) {
  !get_operator("prefix_matches_regex")(ctx)
})

# Operator: suffix_matches_regex - regex matches within the last N characters of target
register_operator("suffix_matches_regex", guarded_op(function(ctx) {
  n <- ctx$condition$suffix
  len <- nchar(ctx$target)
  grepl(ctx$value, substr(ctx$target, pmax(len - n + 1, 1), len), perl = TRUE)
}))

# Operator: not_suffix_matches_regex - negation of suffix_matches_regex
register_operator("not_suffix_matches_regex", function(ctx) {
  !get_operator("suffix_matches_regex")(ctx)
})

# Operator: prefix_equal_to - target's first N characters (condition's `prefix`) literally equal value
register_operator("prefix_equal_to", guarded_op(function(ctx) {
  substr(ctx$target, 1, ctx$condition$prefix) == ctx$value
}))

# Operator: prefix_not_equal_to - negation of prefix_equal_to
register_operator("prefix_not_equal_to", function(ctx) {
  !get_operator("prefix_equal_to")(ctx)
})

# Operator: prefix_is_contained_by - target's first N characters (condition's `prefix`) are a member of value
register_operator("prefix_is_contained_by", guarded_op(function(ctx) {
  substr(ctx$target, 1, ctx$condition$prefix) %in% ctx$value
}))

# Operator: prefix_is_not_contained_by - negation of prefix_is_contained_by
register_operator("prefix_is_not_contained_by", function(ctx) {
  !get_operator("prefix_is_contained_by")(ctx)
})

# Operator: suffix_is_contained_by - target's last N characters (condition's `suffix`) are a member of value
register_operator("suffix_is_contained_by", guarded_op(function(ctx) {
  n <- ctx$condition$suffix
  len <- nchar(ctx$target)
  substr(ctx$target, pmax(len - n + 1, 1), len) %in% ctx$value
}))

# Operator: suffix_is_not_contained_by - negation of suffix_is_contained_by
register_operator("suffix_is_not_contained_by", function(ctx) {
  !get_operator("suffix_is_contained_by")(ctx)
})

# Extracts a substring from `value` via the condition's `regex` (a single
# capture group), then checks target != that substring. Confirmed against
# CORE-000538's real fixtures: "RDOMAIN does_not_equal_string_part
# regex: .{4}(..).*, value: $dataset_name" extracts characters 5-6 of the
# dataset name (e.g. "AE" from "SUPPAE") and flags every row where RDOMAIN
# doesn't match it.
# Operator: does_not_equal_string_part - target doesn't match a regex-captured substring of value
register_operator("does_not_equal_string_part", guarded_op(function(ctx) {
  extracted <- sub(ctx$condition$regex, "\\1", ctx$value, perl = TRUE)
  ctx$target != extracted
}))

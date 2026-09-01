# The reference engine matches a rule's regex from the START of the string
# (like Python's re.match(), not re.search()) - R's grepl() searches for a
# match ANYWHERE in the string by default, which is a real behavioral gap
# for a pattern with no explicit leading "^" but an end anchor "$" (common
# in these rules, e.g. CORE-000576's number-format check
# "[+-]?([0-9]*[.])?[0-9]+$"): grepl() happily matches just the trailing
# numeric substring of "-5.18,3.1416,2,2.88", while the reference engine
# requires the WHOLE string to satisfy the pattern from position 0 and
# correctly rejects it. Confirmed empirically against all 51 bundled rules
# using these operators: forcing a start anchor changes the outcome for
# exactly 3 real fixture cases, and in every one it flips a wrong FALSE to
# the correct TRUE - never the reverse - so this isn't a guess, it's a
# verified strict improvement with no regression risk.
#' Does target match `value` as a Perl regex, anchored at the string's start?
#' @param ctx Operator context, see `evaluate_condition()`.
#' @return A logical vector.
#' @noRd
matches_regex_check <- function(ctx) {
  grepl(paste0("^(?:", ctx$value, ")"), ctx$target, perl = TRUE)
}

# A blank target is exempt from format validation entirely: the reference
# engine's own matches_regex/not_matches_regex (`converted_strings.notna()
# & ...`) is FALSE for BOTH operators when the target is blank/NA - not a
# simple negation of each other, since `!matches_regex(blank)` would
# otherwise make not_matches_regex wrongly TRUE for every blank value.
# Confirmed against CORE-000558's real fixture: a numeric --DY value left
# blank must not be flagged by "not_matches_regex ^-?[1-9]{1}\\d*$" (an
# empty string trivially fails that digit-requiring pattern, but a MISSING
# value isn't a formatting violation - there's nothing to validate).
# Operator: matches_regex - target matches the given Perl regex, anchored at the start
register_operator("matches_regex", guarded_op(function(ctx) {
  !is_blank(ctx$target) & matches_regex_check(ctx)
}))

# Operator: not_matches_regex - target does NOT match, but only when populated
register_operator("not_matches_regex", guarded_op(function(ctx) {
  !is_blank(ctx$target) & !matches_regex_check(ctx)
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
# matches if target contains ANY of them). A `$`-bound grouped `distinct`
# Operation (e.g. CORE-000888's `$txparmcd`) resolves to a LIST target - one
# SET of values per row, not one string - so this means something different
# there: "is value an exact MEMBER of the row's set", not a substring
# search. Confirmed against CORE-000888/CORE-000993's real fixtures: a
# group whose set contains only "PLANFSUBxxx" (not the exact string
# "PLANFSUB") is reported as NOT containing PLANFSUB - a substring match
# would wrongly say it does (the whole point of the underlying rule is that
# a near-miss variable name like "PLANFSUBxxx" doesn't count as the real
# "PLANFSUB").
# Operator: contains - target contains any of value (substring for a plain
# string target, exact set membership for a `distinct`-Operation SET target)
register_operator("contains", guarded_op(function(ctx) {
  # A whole-dataset collection (a `distinct` Operation) is one set, so the
  # question has one answer for every row. CDISC.SENDIG-DART.SEND399 asks
  # whether TS's distinct TSPARMCD values contain "SNDIGVER"; comparing the
  # collection elementwise against the rows instead flagged every record of
  # every case, including the one where SNDIGVER is plainly there.
  if (isTRUE(ctx$target_is_collection)) {
    return(rep(any(as.character(ctx$value) %in% as.character(ctx$target)), ctx$n))
  }
  if (is.list(ctx$target)) {
    return(vapply(ctx$target, function(t) any(ctx$value %in% t), logical(1)))
  }
  any_value_match(ctx$target, ctx$value, function(t, v) grepl(v, t, fixed = TRUE))
}))

# Operator: does_not_contain - negation of contains
register_operator("does_not_contain", function(ctx) {
  !get_operator("contains")(ctx)
})

# Operator: contains_case_insensitive - contains, ignoring case. Same set/
# substring split as `contains`: a SET target (from a `distinct` Operation)
# matches whole elements, a plain string matches a substring - so a variable
# list containing "PLANFSUBxxx" still does not contain "PLANFSUB", case
# regardless.
register_operator("contains_case_insensitive", guarded_op(function(ctx) {
  if (isTRUE(ctx$target_is_collection)) {
    return(rep(
      any(toupper(as.character(ctx$value)) %in% toupper(as.character(ctx$target))),
      ctx$n
    ))
  }
  if (is.list(ctx$target)) {
    value <- toupper(as.character(ctx$value))
    return(vapply(ctx$target, function(t) any(value %in% toupper(as.character(t))), logical(1)))
  }
  any_value_match(ctx$target, ctx$value, function(t, v) {
    grepl(toupper(v), toupper(t), fixed = TRUE)
  })
}))

# Operator: does_not_contain_case_insensitive - negation of the above
register_operator("does_not_contain_case_insensitive", function(ctx) {
  !get_operator("contains_case_insensitive")(ctx)
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

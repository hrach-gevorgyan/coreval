#' Elementwise blank test (NA, or empty string for character vectors)
#' @param x A vector.
#' @return A logical vector.
#' @noRd
is_blank <- function(x) is.na(x) | (is.character(x) & x == "")

# TRUE where a record's combination of values across [name, value...] columns
# duplicates another record's combination anywhere in the dataset. Blanks
# count as a real, matching value for grouping purposes (two blank rows in
# the same columns are a genuine duplicate) - matches the reference engine's
# own fillna("_NaN_")-before-grouping behavior.
# Operator: is_not_unique_set - flags rows whose combination of columns duplicates another row's
register_operator("is_not_unique_set", function(ctx) {
  cols <- unique(c(ctx$name, ctx$condition$value))
  cols <- cols[cols %in% names(ctx$dataset$data)]
  if (length(cols) == 0) {
    return(rep(FALSE, ctx$n))
  }
  dt <- ctx$dataset$data[, cols, with = FALSE]
  # The blank sentinel and the between-column separator both use the ASCII
  # Unit Separator (0x1F), which can't appear in ordinary clinical text -
  # a plain "NA" sentinel would collide with a genuine data value of "NA",
  # and pasting columns together with no separator at all would collide
  # across column boundaries (e.g. ("1","23") vs ("12","3")).
  normalized <- lapply(dt, function(col) {
    ifelse(is_blank(col), "\x1fBLANK\x1f", as.character(col))
  })
  key <- do.call(paste, c(normalized, sep = "\x1f"))
  as.vector(ave(seq_along(key), key, FUN = length)) > 1
})

# Operator: is_unique_set - negation of is_not_unique_set
register_operator("is_unique_set", function(ctx) {
  !get_operator("is_not_unique_set")(ctx)
})

# Enforces a one-to-one (bijective, ignoring blanks) relationship between two
# columns: every non-blank target value must map to exactly one comparator
# value, and vice versa. A row is flagged if either side of its pair is part
# of an inconsistent mapping - e.g. one ETCD value paired with two different
# ELEMENT values somewhere in the dataset.
# Operator: is_not_unique_relationship - flags rows breaking a one-to-one mapping between two columns
register_operator("is_not_unique_relationship", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(FALSE, ctx$n))
  }
  t_col <- ctx$target
  c_col <- ctx$value

  keep <- !(is_blank(t_col) & is_blank(c_col))
  pairs <- unique(data.frame(t = t_col[keep], c = c_col[keep], stringsAsFactors = FALSE))

  find_violations <- function(key_vals, val_vals) {
    blank_key <- is_blank(key_vals)
    grouped <- split(val_vals[!blank_key], key_vals[!blank_key])
    violated <- vapply(grouped, function(vals) {
      blank_v <- is_blank(vals)
      distinct_nonblank <- unique(vals[!blank_v])
      length(distinct_nonblank) > 1 || (length(distinct_nonblank) >= 1 && any(blank_v))
    }, logical(1))
    names(grouped)[violated]
  }

  violated_targets <- find_violations(pairs$t, pairs$c)
  violated_comparators <- find_violations(pairs$c, pairs$t)

  result <- rep(FALSE, ctx$n)
  if (length(violated_targets) > 0) {
    result <- result | (as.character(t_col) %in% violated_targets)
  }
  if (length(violated_comparators) > 0) {
    result <- result | (as.character(c_col) %in% violated_comparators)
  }
  result
})

# Operator: is_unique_relationship - negation of is_not_unique_relationship
register_operator("is_unique_relationship", function(ctx) {
  !get_operator("is_not_unique_relationship")(ctx)
})

# Flags a row whose target value is inconsistent with other rows sharing the
# same grouping-key tuple (e.g. every record for a given VISITNUM/DOMAIN/
# --TPTREF/--TPTNUM combination must report the same --ELTM). Unlike
# is_not_unique_relationship (a bidirectional 1:1 pairing between exactly two
# columns), this is one-directional and supports an arbitrary-arity grouping
# key: it only checks the target's consistency *within* each group, not
# whether the key tuple is itself unique per target value. Grouping-column
# names come from the condition's raw `value` (like is_not_unique_set) and
# need `resolve_var_name()` since they can be "--"-prefixed templates.
# Operator: is_inconsistent_across_dataset - flags rows whose target value is inconsistent within its group
register_operator("is_inconsistent_across_dataset", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  cols <- resolve_var_name(ctx$condition$value, ctx$domain)
  cols <- cols[cols %in% names(ctx$dataset$data)]
  if (length(cols) == 0) {
    return(rep(FALSE, ctx$n))
  }
  dt <- ctx$dataset$data[, cols, with = FALSE]
  normalized <- lapply(dt, function(col) ifelse(is_blank(col), "\x1fBLANK\x1f", as.character(col)))
  key <- do.call(paste, c(normalized, sep = "\x1f"))

  grouped <- split(ctx$target, key)
  inconsistent <- vapply(grouped, function(vals) length(unique(vals[!is_blank(vals)])) > 1, logical(1))
  key %in% names(grouped)[inconsistent]
})

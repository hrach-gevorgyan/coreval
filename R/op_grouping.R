is_blank <- function(x) is.na(x) | (is.character(x) & x == "")

# TRUE where a record's combination of values across [name, value...] columns
# duplicates another record's combination anywhere in the dataset. Blanks
# count as a real, matching value for grouping purposes (two blank rows in
# the same columns are a genuine duplicate) - matches the reference engine's
# own fillna("_NaN_")-before-grouping behavior.
register_operator("is_not_unique_set", function(ctx) {
  cols <- unique(c(ctx$name, ctx$condition$value))
  cols <- cols[cols %in% names(ctx$dataset$data)]
  if (length(cols) == 0) {
    return(rep(FALSE, ctx$n))
  }
  dt <- ctx$dataset$data[, cols, with = FALSE]
  normalized <- lapply(dt, function(col) {
    ifelse(is_blank(col), "NA", as.character(col))
  })
  key <- do.call(paste, c(normalized, sep = ""))
  as.vector(ave(seq_along(key), key, FUN = length)) > 1
})

register_operator("is_unique_set", function(ctx) {
  !get_operator("is_not_unique_set")(ctx)
})

# Enforces a one-to-one (bijective, ignoring blanks) relationship between two
# columns: every non-blank target value must map to exactly one comparator
# value, and vice versa. A row is flagged if either side of its pair is part
# of an inconsistent mapping - e.g. one ETCD value paired with two different
# ELEMENT values somewhere in the dataset.
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
    keys <- unique(key_vals[!blank_key])
    violated <- character(0)
    for (k in keys) {
      vals <- val_vals[!blank_key & key_vals == k]
      blank_v <- is_blank(vals)
      distinct_nonblank <- unique(vals[!blank_v])
      inconsistent <- length(distinct_nonblank) > 1 ||
        (length(distinct_nonblank) >= 1 && any(blank_v))
      if (inconsistent) {
        violated <- c(violated, as.character(k))
      }
    }
    violated
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

register_operator("is_unique_relationship", function(ctx) {
  !get_operator("is_not_unique_relationship")(ctx)
})

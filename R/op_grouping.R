#' Elementwise blank test (NA, or empty string for character vectors)
#' @param x A vector.
#' @return A logical vector.
#' @noRd
is_blank <- function(x) is.na(x) | (is.character(x) & x == "")

#' Expand an Operations reference sitting in a grouping-column list
#'
#' Grouping operators read `condition$value` raw, because they need column
#' NAMES. An entry like `$TIMING_VARIABLES` is not a column - it names an
#' Operations binding whose value IS a list of columns (CORE-001034 groups by
#' `[USUBJID, --TESTCD, $TIMING_VARIABLES]`). The reference engine flattens
#' these with `flatten_list()`; left unexpanded the key silently collapses to
#' the few literal entries, which is a far looser key.
#'
#' @param values The condition's raw `value` entries.
#' @param bindings The rule's Operations bindings.
#' @return A character vector of column names.
#' @noRd
expand_binding_columns <- function(values, bindings) {
  if (length(values) == 0) {
    return(character(0))
  }
  unlist(lapply(values, function(v) {
    if (is.character(v) && length(v) == 1L && startsWith(v, "$")) {
      binding <- bindings[[v]]
      if (!is.null(binding) && identical(binding$kind, "scalar")) {
        return(as.character(binding$value))
      }
      return(character(0))
    }
    as.character(v)
  }), use.names = FALSE)
}

#' Reduce grouping-column values to the part a rule's `regex` matches
#'
#' A rule can carry a `regex` alongside its grouping columns, meaning "group
#' on this much of the value". CORE-001034 groups records by their timing
#' variables with `^\\d{4}-\\d{2}-\\d{2}`, so `--DTC` values of `2022-01-14`
#' and `2022-01-14T07:00` belong to the SAME day. Ignoring the regex split
#' them into separate groups, and the rule's own record-count condition then
#' never saw the group it was counting.
#'
#' Follows the reference engine (`is_unique_set` and `RecordCount.
#' _apply_regex_to_grouping_columns`) in two details that matter: the regex is
#' applied only to columns whose FIRST non-missing value matches it - so a
#' `VISIT` or `--TPT` column sitting in the same grouping list is left alone -
#' and matching is anchored at the start of the value, as Python's `re.match`
#' is, not searched anywhere within it.
#'
#' @param dt A data.table of grouping columns.
#' @param cols Column names to consider.
#' @param regex The rule's regex, or `NULL`.
#' @return `dt`, with matching columns reduced to their matched prefix.
#' @noRd
apply_grouping_regex <- function(dt, cols, regex) {
  if (is.null(regex) || !nzchar(regex)) {
    return(dt)
  }
  out <- data.table::copy(dt)
  for (col in intersect(cols, names(out))) {
    v <- out[[col]]
    if (!is.character(v)) {
      next
    }
    present <- v[!is.na(v)]
    if (length(present) == 0 || regexpr(regex, present[1]) != 1L) {
      next
    }
    m <- regexpr(regex, v)
    idx <- which(m == 1L & !is.na(v) & nzchar(v))
    if (length(idx) > 0) {
      v[idx] <- substr(v[idx], 1L, attr(m, "match.length")[idx])
      out[[col]] <- v
    }
  }
  out
}

# TRUE where a record's combination of values across [name, value...] columns
# duplicates another record's combination anywhere in the dataset. Blanks
# count as a real, matching value for grouping purposes (two blank rows in
# the same columns are a genuine duplicate) - matches the reference engine's
# own fillna("_NaN_")-before-grouping behavior.
# Operator: is_not_unique_set - flags rows whose combination of columns duplicates another row's
register_operator("is_not_unique_set", function(ctx) {
  # The grouping columns in `condition$value` need the same "--" -> domain
  # expansion that `ctx$name` already got in evaluate_condition(). The
  # reference engine's `_resolve_prefixes()` walks EVERY entry of the
  # operator's argument dict and applies `replace_all_prefixes()` to any
  # LIST value, so a comparator like ["--TESTCD", "--CAT", "USUBJID"]
  # arrives as ["LBTESTCD", "LBCAT", "USUBJID"] - never with the "--"
  # still on it. Left raw, those entries match no real column, get
  # silently dropped by the filter below, and the uniqueness key collapses
  # to whatever few columns happened to be literal - a far looser key that
  # flags huge numbers of rows as duplicates. Confirmed against
  # CORE-000914/915, where the key degraded to (LBBLFL, USUBJID) and
  # flagged every baseline-flagged row of any subject with 2+ of them.
  # (The sibling is_inconsistent_across_dataset already resolves its own
  # grouping columns this way.)
  cols <- unique(c(ctx$name, resolve_var_name(
    expand_binding_columns(ctx$condition$value, ctx$bindings), ctx$wildcard
  )))
  cols <- cols[cols %in% names(ctx$dataset$data)]
  if (length(cols) == 0) {
    return(rep(FALSE, ctx$n))
  }
  # A domain SPLIT ACROSS FILES is still one domain: --SEQ must be unique
  # per subject across lbae.csv AND lbds.csv together, and a value appearing
  # once in each is a genuine duplicate that is invisible to either file
  # alone. So the key is built over every sibling file, and only the current
  # file's slice of the answer is returned - findings are still reported per
  # physical file, with that file's own record numbers, which is what the
  # reference does (CORE-000750 expects LBAE and LBDS each flagged
  # separately).
  siblings <- split_domain_siblings(ctx)
  dt <- if (length(siblings) == 0) {
    ctx$dataset$data[, cols, with = FALSE]
  } else {
    data.table::rbindlist(
      lapply(siblings, function(d) d[, cols, with = FALSE]),
      use.names = TRUE, fill = TRUE
    )
  }
  dt <- apply_grouping_regex(dt, names(dt), ctx$condition$regex)
  # The blank sentinel and the between-column separator both use the ASCII
  # Unit Separator (0x1F), which can't appear in ordinary clinical text -
  # a plain "NA" sentinel would collide with a genuine data value of "NA",
  # and pasting columns together with no separator at all would collide
  # across column boundaries (e.g. ("1","23") vs ("12","3")).
  normalized <- lapply(dt, function(col) {
    ifelse(is_blank(col), "\x1fBLANK\x1f", as.character(col))
  })
  key <- do.call(paste, c(normalized, sep = "\x1f"))
  # "Does this key occur more than once?" - which is all the group SIZE was
  # ever used for. stats::ave() answered it by building an interaction factor
  # and sorting it, and on a 200 000-row dataset that one line was 53% of the
  # entire check, sorting alone 36%. duplicated() answers the same question by
  # hashing: no factor, no sort.
  duplicated_any <- duplicated(key) | duplicated(key, fromLast = TRUE)
  # Return only this file's rows. rbindlist stacked the siblings in
  # split_domain_siblings()'s order, which puts the current dataset first.
  duplicated_any[seq_len(ctx$n)]
})

# Every dataset the current domain is split across, current one FIRST so a
# result computed over the stack can be sliced back to this file's rows.
# Returns an empty list when the domain isn't split, so callers can keep
# their single-dataset path.
#' The data.tables of every file a split domain spans, current file first
#' @param ctx Operator context, see `evaluate_condition()`.
#' @return A list of data.tables, or an empty list if the domain isn't split.
#' @noRd
split_domain_siblings <- function(ctx) {
  datasets <- ctx$study$datasets
  if (is.null(datasets) || length(datasets) < 2) {
    return(list())
  }
  unsplit <- dataset_unsplit_name(ctx$dataset, ctx$domain)
  others <- setdiff(names(datasets), ctx$domain)
  matching <- others[vapply(others, function(k) {
    identical(dataset_unsplit_name(datasets[[k]], k), unsplit)
  }, logical(1))]
  if (length(matching) == 0) {
    return(list())
  }
  c(list(ctx$dataset$data), lapply(datasets[matching], function(d) d$data))
}

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

# Dataset-level (like exists/contains_all): does the target column have
# exactly one distinct non-blank value across the WHOLE dataset? Confirmed
# against CORE-000365's real fixtures: MHCAT is literally "GENERAL" for
# every one of 3 records (1 distinct value) -> all 3 flagged; a 12-record
# fixture with 2 distinct MHCAT values -> none flagged. Recycled to every
# row like other dataset-level facts (see evaluate.R's "dataset-level exists
# condition" test), so a sibling non_empty condition still filters out any
# genuinely blank rows in the same "all:" block.
# Operator: has_same_values - dataset-level: target has exactly one distinct non-blank value
register_operator("has_same_values", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  distinct <- unique(ctx$target[!is_blank(ctx$target)])
  rep(length(distinct) == 1, ctx$n)
})

# Flags a row whose target VALUE appears on more than one row sharing the
# same value of the condition's `within` column (e.g. "DSDECOD
# present_on_multiple_rows_within: USUBJID" - does this subject have more
# than one row with this same DSDECOD value?). Confirmed against
# CORE-000363's real fixtures: a subject with two "INFORMED CONSENT
# OBTAINED" DSDECOD rows has BOTH rows flagged by this operator alone (the
# rule's other AND-ed conditions then narrow down which subject actually
# violates the full rule).
#' Shared "target value duplicated within a group" check for present(_)_on_multiple_rows_within
#' @param ctx Operator context, see `evaluate_condition()`.
#' @return A logical vector.
#' @noRd
present_on_multiple_rows_within_check <- function(ctx) {
  within_col <- resolve_var_name(ctx$condition$within, ctx$wildcard)
  if (!ctx$exists || !(within_col %in% names(ctx$dataset$data))) {
    return(rep(FALSE, ctx$n))
  }
  group <- ctx$dataset$data[[within_col]]
  normalize <- function(x) ifelse(is_blank(x), "\x1fBLANK\x1f", as.character(x))
  key <- paste(normalize(group), normalize(ctx$target), sep = "\x1f")
  # Same substitution as is_not_unique_set(), for the same reason.
  duplicated(key) | duplicated(key, fromLast = TRUE)
}

# Operator: present_on_multiple_rows_within - target's value appears on >1 row sharing the same `within` value
register_operator("present_on_multiple_rows_within", present_on_multiple_rows_within_check)

# Operator: not_present_on_multiple_rows_within - negation of present_on_multiple_rows_within
register_operator("not_present_on_multiple_rows_within", function(ctx) {
  !present_on_multiple_rows_within_check(ctx)
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
#
# An earlier version flagged EVERY row in an inconsistent group. The
# reference engine's own `_check_inconsistency()` is more targeted: within a
# group with >1 distinct target value, it finds the MAJORITY value and flags
# only the MINORITY rows (the ones that differ from it) - unless there's a
# TIE for most-common value, in which case every row in the group is
# flagged. Confirmed against CORE-000142's real fixtures: a group of 4 rows
# with target values PT1H/PT1H/PT2H/PT1H is NOT a violation for the 3
# PT1H rows (the majority) - only the single PT2H row would be, and even
# that one is excluded from THIS rule's overall Check by a sibling
# `non_empty` condition on a different variable. Blank target values are
# NOT excluded from this comparison either - a blank is just another
# distinct value that can be the majority or the minority, matching the
# reference's `fillna("_NaN_")` (blanks become their own bucket, not
# dropped).
#' Flag minority-value rows in each group (or all rows, on a tie for majority)
#' @param key A vector of group keys, same length as `target`.
#' @param target A vector of values to check for per-group consistency.
#' @return A logical vector, same length as `target`.
#' @noRd
flag_inconsistent_minority <- function(key, target) {
  target_key <- ifelse(is_blank(target), "\x1fBLANK_TARGET\x1f", as.character(target))
  result <- rep(FALSE, length(target))
  for (k in unique(key)) {
    idx <- which(key == k)
    vals <- target_key[idx]
    counts <- table(vals)
    if (length(counts) <= 1) {
      next
    }
    max_count <- max(counts)
    most_common <- names(counts)[counts == max_count]
    if (length(most_common) > 1) {
      result[idx] <- TRUE
    } else {
      result[idx[vals != most_common]] <- TRUE
    }
  }
  result
}

# Operator: is_inconsistent_across_dataset - flags the minority-value rows within each group (all, if tied)
register_operator("is_inconsistent_across_dataset", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  cols <- resolve_var_name(ctx$condition$value, ctx$wildcard)
  cols <- cols[cols %in% names(ctx$dataset$data)]
  if (length(cols) == 0) {
    return(rep(FALSE, ctx$n))
  }
  dt <- ctx$dataset$data[, cols, with = FALSE]
  normalized <- lapply(dt, function(col) ifelse(is_blank(col), "\x1fBLANK\x1f", as.character(col)))
  key <- do.call(paste, c(normalized, sep = "\x1f"))

  flag_inconsistent_minority(key, ctx$target)
})

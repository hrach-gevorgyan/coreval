# Operators that need rows ordered WITHIN a group, unlike op_grouping.R's
# operators (which only care about unordered set membership/counts).

#' Sort key for an ordering column: numeric if every value parses cleanly, else the raw values
#' @param x A vector.
#' @return A numeric vector, or `x` unchanged if not uniformly numeric.
#' @noRd
sequence_sort_key <- function(x) {
  num <- suppressWarnings(as.numeric(x))
  if (!anyNA(num)) num else x
}

# Within each `within`-group, sorted by `ordering`: does this row's target
# equal the NEXT row's `value` (already resolved to a real column, e.g.
# SESTDTC)? The group's last row has no next row and is never flagged.
# Confirmed against CORE-000352's real fixtures: "SEENDTC
# does_not_have_next_corresponding_record ordering: SESEQ, value: SESTDTC,
# within: USUBJID" flags a subject's row whenever its SEENDTC doesn't equal
# the following record's SESTDTC.
# Operator: does_not_have_next_corresponding_record - target doesn't equal the next ordered row's value
register_operator("does_not_have_next_corresponding_record", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(FALSE, ctx$n))
  }
  within_col <- resolve_var_name(ctx$condition$within, ctx$wildcard)
  ordering_col <- resolve_var_name(ctx$condition$ordering, ctx$wildcard)
  dt <- ctx$dataset$data
  # CDISC's engine sorts by these and fails on a column that is not there.
  # FALSE here was a clean answer from a rule that never ran (CORE-000352).
  absent <- setdiff(c(within_col, ordering_col), names(dt))
  if (length(absent) > 0) {
    stop("sorts by ", paste(absent, collapse = ", "), ", which the dataset does not have", call. = FALSE)
  }
  group <- dt[[within_col]]
  ord <- sequence_sort_key(dt[[ordering_col]])
  result <- rep(FALSE, ctx$n)
  for (g in unique(group)) {
    idx <- which(group == g)
    ord_idx <- idx[order(ord[idx])]
    if (length(ord_idx) < 2) {
      next
    }
    for (i in seq_len(length(ord_idx) - 1)) {
      cur <- ord_idx[i]
      nxt <- ord_idx[i + 1]
      if (!identical(ctx$target[cur], ctx$value[nxt])) {
        result[cur] <- TRUE
      }
    }
  }
  result
})

# Within each group (`value`, already resolved to a real column, e.g.
# USUBJID), sorted by `ordering`: flags a blank target UNLESS it's the
# group's last row in that sort order. Confirmed against CORE-000527's real
# fixtures: "SEENDTC empty_within_except_last_row ordering: SESTDTC,
# value: USUBJID" only flags a blank SEENDTC when a later record exists for
# the same subject - the group's genuinely last element may legitimately
# have a blank end date.
# Operator: empty_within_except_last_row - target is blank on a non-last row of its ordered group
register_operator("empty_within_except_last_row", function(ctx) {
  if (!ctx$exists || is.null(ctx$value)) {
    return(rep(FALSE, ctx$n))
  }
  ordering_col <- resolve_var_name(ctx$condition$ordering, ctx$wildcard)
  dt <- ctx$dataset$data
  if (!(ordering_col %in% names(dt))) {
    stop("sorts by ", ordering_col, ", which the dataset does not have", call. = FALSE)
  }
  group <- ctx$value
  ord <- sequence_sort_key(dt[[ordering_col]])
  result <- rep(FALSE, ctx$n)
  for (g in unique(group)) {
    idx <- which(group == g)
    ord_idx <- idx[order(ord[idx])]
    non_last <- ord_idx[-length(ord_idx)]
    if (length(non_last) > 0) {
      result[non_last] <- is_blank(ctx$target[non_last])
    }
  }
  result
})

# Operator: target_is_not_sorted_by - within a group, the target's own order doesn't sort a value column as specified
register_operator("target_is_not_sorted_by", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  # `within` can name several columns (CORE-002016: USUBJID and MIDSTYPE).
  # Taken as one, the second was dropped by `[[` with "subscript out of
  # bounds" and the rule could not run.
  within_col <- vapply(as.character(unlist(ctx$condition$within)),
                       function(v) resolve_var_name(v, ctx$wildcard), character(1), USE.NAMES = FALSE)
  spec <- ctx$condition$value[[1]]
  sort_col <- resolve_var_name(spec$name, ctx$wildcard)
  dt <- ctx$dataset$data
  if (!all(c(within_col, sort_col) %in% names(dt))) {
    # A condition on a missing column is FALSE in CORE 1.0; CDISC's engine
    # fails on it (KeyError) and skips the rule.
    if (engine_is_core1()) {
      return(rep(FALSE, ctx$n))
    }
    stop("sorts within ", paste(setdiff(c(within_col, sort_col), names(dt)), collapse = ", "),
         ", which this dataset does not have", call. = FALSE)
  }
  group <- if (length(within_col) == 1) {
    dt[[within_col]]
  } else {
    do.call(paste, c(lapply(within_col, function(v) {
      x <- as.character(dt[[v]])
      ifelse(is.na(x), "\x1eNA", x)
    }), sep = "\x1f"))
  }
  target <- ctx$target
  # CORE 1.0's `regex`: the target is the integer its first capture group
  # holds, as `CAST((regexp_match(target, regex))[1] AS INTEGER)`, so MIDS
  # "CHEMO2" sorts as 2. No match is a missing value.
  if (!is.null(ctx$condition$regex)) {
    hit <- regmatches(as.character(target), regexec(ctx$condition$regex, as.character(target), perl = TRUE))
    target <- vapply(hit, function(m) if (length(m) >= 2) suppressWarnings(as.integer(m[[2]])) else NA_integer_,
                     integer(1))
  }
  # CORE 1.0's `strict_incremental_ordering` (target_is_sorted_by_operator.py,
  # _strict_incremental_sql): within each group, rows ordered by the sort
  # columns must carry exactly 1, 2, 3, ... in that order. A missing target
  # counts as sorted.
  if (isTRUE(ctx$condition$strict_incremental_ordering)) {
    keys <- lapply(ctx$condition$value, function(sp) {
      col <- dt[[resolve_var_name(sp$name, ctx$wildcard)]]
      # A blank text value is "", not missing, in CORE 1.0 as read from a
      # transport file (xpt_data_reader.py only trims), so it sorts first
      # ascending; null_position applies to a missing number only. CDISC's
      # engine takes any blank as null (_strict_incremental_check).
      # A numeric column stays numeric: as text, 10 sorts before 9.
      if (is.numeric(col)) {
        return(col)
      }
      x <- as.character(col)
      if (!is.character(col) || !engine_is_core1()) x[is_blank(col)] <- NA_character_
      x
    })
    decreasing <- vapply(ctx$condition$value, function(sp) identical(tolower(sp$sort_order %||% "asc"), "desc"),
                         logical(1))
    nulls_first <- vapply(ctx$condition$value, function(sp) identical(tolower(sp$null_position %||% "last"), "first"),
                          logical(1))
    position <- rep(NA_integer_, ctx$n)
    for (g in unique(group)) {
      idx <- which(group == g | (is.na(group) & is.na(g)))
      parts <- list()
      for (k in seq_along(keys)) {
        v <- keys[[k]][idx]
        parts <- c(parts, list(if (nulls_first[k]) !is.na(v) else is.na(v)),
                   list(if (decreasing[k]) -xtfrm(v) else xtfrm(v)))
      }
      parts <- c(parts, list(seq_along(idx)))
      position[idx[do.call(order, c(parts, list(method = "radix", na.last = TRUE)))]] <- seq_along(idx)
    }
    # A blank passes, and only a blank. CDISC's engine compares the number, so
    # 1.5 and "abc" fail the row (target_null | target_num == position). 1.0
    # casts to an integer: a number rounds, and text that is no whole number
    # ends the rule.
    # CDISC's _strict_incremental_check strips before testing for blank, so
    # "  " passes there. 1.0 casts the text, and "  " is no whole number.
    blank <- is_blank(if (is.character(target) && !engine_is_core1()) trimws(target) else target)
    tv <- suppressWarnings(as.numeric(as.character(target)))
    if (engine_is_core1()) {
      bad <- if (is.numeric(target)) FALSE else !blank & (is.na(tv) | tv != round(tv))
      if (any(bad)) {
        stop(ctx$name, " is not a whole number: \"", as.character(target)[which(bad)[1]], "\"", call. = FALSE)
      }
      tv <- round(tv)
    }
    return(!(blank | (!is.na(tv) & tv == position)))
  }
  if (engine_is_core1()) {
    return(!core1_sorted_by(target, dt, group, ctx))
  }
  # Every sort specification must hold, as the engine ANDs them; the first
  # alone was read before.
  sorted <- rep(TRUE, ctx$n)
  for (sp in ctx$condition$value) {
    col <- resolve_var_name(sp$name, ctx$wildcard)
    if (!col %in% names(dt)) {
      stop("sorts by ", col, ", which this dataset does not have", call. = FALSE)
    }
    sorted <- sorted & cdisc_sorted_by(
      target, dt[[col]], group,
      descending = identical(tolower(sp$sort_order %||% "asc"), "desc"),
      null_first = identical(tolower(sp$null_position %||% "last"), "first")
    )
  }
  !sorted
})

#' target_is_sorted_by as CDISC's engine answers it
#'
#' A port of `target_is_sorted_by()` and
#' `check_target_ascending_in_sorted_group_with_regex()` (dataframe_operators.py).
#' Within each group, rows taken in target order:
#'
#' * blank sort values are all out of place when any sits on the wrong side
#'   of a filled one (`_mark_invalid_null_positions`);
#' * two dates of different precision where one contains the other (`2020`
#'   and `2020-01`) are both out of place (`check_date_overlaps`);
#' * of the rest, a row is out of place when its target differs from the one
#'   at its position once the rows are sorted by the date;
#' * and a row still in place is out of place if its date is earlier than the
#'   previous filled date or later than the next one, in target order
#'   (`_verify_neighbor_consistency`).
#'
#' Pairs of neighbours were compared before, and both rows of a bad pair
#' flagged, where the engine flags the rows that are actually misplaced.
#'
#' @param target The target values, already reduced by any `regex`.
#' @param sort_values The sort column.
#' @param group The group key for each row.
#' @param descending,null_first The sort specification.
#' @return A logical vector, TRUE where the row is in place.
#' @noRd
cdisc_sorted_by <- function(target, sort_values, group, descending, null_first) {
  n <- length(target)
  valid <- rep(TRUE, n)
  numeric_sort <- is.numeric(sort_values)
  numeric_target <- is.numeric(target)
  text <- as.character(sort_values)
  blank <- is.na(sort_values) | (!numeric_sort & !nzchar(trimws(text)))
  is_date <- !numeric_sort & !blank & is_valid_date_str(ifelse(blank, "", text))
  # parse_date(): the date part before any "--" interval, and how many of its
  # components are filled.
  date_part <- sub("--.*$", "", text)
  precision <- lengths(regmatches(date_part, gregexpr("[^-T:]+", date_part)))
  # Python compares strings by code point; so does a radix order in R.
  less <- function(a, b) {
    if (numeric_sort) return(a < b)
    o <- order(c(a, b), method = "radix")
    a != b && o[1] == 1L
  }
  # pandas drops a missing group key, and a dropped row reads as in place.
  for (g in unique(group[!is.na(group)])) {
    idx <- which(group == g)
    # Rows in target order, missing targets last; ties keep row order.
    idx <- idx[order(is.na(target[idx]), target[idx], method = "radix")]
    b <- blank[idx]
    if (any(b) && any(!b)) {
      pos_b <- which(b)
      pos_f <- which(!b)
      misplaced <- if (null_first) max(pos_b) > min(pos_f) else min(pos_b) < max(pos_f)
      if (misplaced) valid[idx[b]] <- FALSE
    }
    # check_date_overlaps(): numeric sort values never overlap.
    overlap <- rep(FALSE, length(idx))
    if (!numeric_sort) {
      d <- which(!b & is_date[idx])
      for (i in d) {
        for (j in d) {
          if (i != j && precision[idx[i]] != precision[idx[j]]) {
            short <- if (precision[idx[i]] < precision[idx[j]]) i else j
            long <- if (short == i) j else i
            # dates_overlap() is given the raw strings; parse_date() only
            # counts the precision.
            if (startsWith(text[idx[long]], text[idx[short]])) {
              overlap[c(i, j)] <- TRUE
            }
          }
        }
      }
    }
    checked <- idx[!b & !overlap]
    if (length(checked) > 0) {
      by_value <- checked[order(if (numeric_sort) sort_values[checked] else text[checked],
                                decreasing = descending, method = "radix")]
      actual <- target[checked]
      expected <- target[by_value]
      for (i in seq_along(checked)) {
        a <- actual[i]
        e <- expected[i]
        if (is.na(a) && is.na(e)) next
        same <- if (is.na(a) || is.na(e)) {
          FALSE
        } else if (!numeric_target && is_valid_date_str(a) && is_valid_date_str(e)) {
          sub("--.*$", "", a) == sub("--.*$", "", e)
        } else {
          a == e
        }
        if (!same) valid[checked[i]] <- FALSE
      }
    }
    # _verify_neighbor_consistency(): filled rows in target order.
    filled <- idx[!b]
    vals <- if (numeric_sort) sort_values[filled] else text[filled]
    for (i in seq_along(filled)) {
      r <- filled[i]
      if (!valid[r] || (!numeric_sort && !is_date[r])) next
      prev <- if (i > 1) vals[i - 1] else NULL
      nxt <- if (i < length(filled)) vals[i + 1] else NULL
      cur <- vals[i]
      bad <- if (!descending) {
        (!is.null(prev) && less(cur, prev)) || (!is.null(nxt) && less(nxt, cur))
      } else {
        (!is.null(prev) && less(prev, cur)) || (!is.null(nxt) && less(cur, nxt))
      }
      if (bad) valid[r] <- FALSE
    }
    valid[idx[overlap]] <- FALSE
  }
  valid
}

#' target_is_sorted_by as CORE 1.0 answers it, without strict ordering
#'
#' From target_is_sorted_by_operator.py. Within each group, every row's
#' position when ordered by the target (blanks last, ties broken by the sort
#' columns, then by row) must equal its position when ordered by each sort
#' column (ties broken by the target, then by row); a row whose sort value is
#' missing is never in place. And a partial date must not contain the next
#' row's date: "2020" then "2020-01" is an overlap, not an order. Compared
#' with CDISC's engine, which checks neighbouring pairs at their common
#' precision, it reports different rows (CORE-000535).
#'
#' @param target The target values, already reduced by any `regex`.
#' @param dt The dataset's data.
#' @param group The group key for each row.
#' @param ctx Operator context, for the sort specification.
#' @return A logical vector, TRUE where the row is in order.
#' @noRd
core1_sorted_by <- function(target, dt, group, ctx) {
  specs <- ctx$condition$value
  n <- length(target)
  cols <- lapply(specs, function(sp) {
    # As above: a blank text sort value is "", which sorts first ascending.
    as.character(dt[[resolve_var_name(sp$name, ctx$wildcard)]])
  })
  desc <- vapply(specs, function(sp) identical(tolower(sp$sort_order %||% "asc"), "desc"), logical(1))
  nfirst <- vapply(specs, function(sp) identical(tolower(sp$null_position %||% "last"), "first"), logical(1))
  tkey <- if (is.numeric(target)) target else suppressWarnings(as.numeric(target))
  if (anyNA(tkey[!is.na(target)])) tkey <- xtfrm(as.character(target))
  tkey[is.na(target) | (is.character(target) & !nzchar(target))] <- NA
  sort_key <- function(k, idx) {
    v <- cols[[k]][idx]
    list(if (nfirst[k]) !is.na(v) else is.na(v), if (desc[k]) -xtfrm(v) else xtfrm(v))
  }
  target_key <- function(idx) list(is.na(tkey[idx]), tkey[idx])
  rank_by <- function(idx, keys) {
    pos <- integer(length(idx))
    pos[do.call(order, c(keys, list(seq_along(idx), method = "radix", na.last = TRUE)))] <- seq_along(idx)
    pos
  }
  year <- "^[0-9]{4}$"
  year_month <- "^[0-9]{4}-[0-9]{2}$"
  iso_ok <- function(x) grepl(paste0("^[0-9]{4}(-[0-9]{2}(-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?)?)?)?$|",
                                     "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$|",
                                     "^[0-9]{4}(-[0-9]{2})?--$|^[0-9]{4}----$"), x)
  ok <- rep(TRUE, n)
  # A missing group value is a group of its own, as NULL is in PARTITION BY;
  # only the overlap test is not applied to it.
  within_missing <- is.na(group)
  gkey <- ifelse(within_missing, "\x1eNA", as.character(group))
  for (g in unique(gkey)) {
    idx <- which(gkey == g)
    by_target <- rank_by(idx, c(target_key(idx), unlist(lapply(seq_along(cols), sort_key, idx = idx),
                                                         recursive = FALSE)))
    agree <- rep(TRUE, length(idx))
    for (k in seq_along(cols)) {
      by_col <- rank_by(idx, c(sort_key(k, idx), target_key(idx)))
      agree <- agree & !is.na(cols[[k]][idx]) & by_col == by_target
    }
    # The next row's first sort value, in sort-column order.
    ord <- do.call(order, c(unlist(lapply(seq_along(cols), sort_key, idx = idx), recursive = FALSE),
                            list(seq_along(idx), method = "radix")))
    first <- cols[[1]][idx]
    nxt <- rep(NA_character_, length(idx))
    nxt[ord[-length(ord)]] <- first[ord[-1]]
    valid <- !is.na(first) & !is.na(nxt) & iso_ok(first) & iso_ok(nxt)
    starts <- function(a, b) startsWith(b, a)
    overlap <- valid & (
      (grepl(year, first) & grepl("^[0-9]{4}-[0-9]{2}", nxt) & starts(first, nxt)) |
        (grepl(year_month, first) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", nxt) & starts(first, nxt)) |
        (grepl(year, nxt) & grepl("^[0-9]{4}-[0-9]{2}", first) & starts(nxt, first)) |
        (grepl(year_month, nxt) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", first) & starts(nxt, first))
    )
    ok[idx] <- agree & !(overlap & !within_missing[idx])
  }
  ok
}

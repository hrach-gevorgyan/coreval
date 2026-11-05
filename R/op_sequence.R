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
  if (!all(c(within_col, ordering_col) %in% names(dt))) {
    return(rep(FALSE, ctx$n))
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
    return(rep(FALSE, ctx$n))
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

# Within each `within`-group, sorted by the TARGET column's own value (its
# declared row-sequence number, e.g. --SEQ): is the sort key named in
# `value[[1]]$name` (e.g. --STDTC) monotonically ordered per `sort_order`
# ("asc"/"desc")? Confirmed against CORE-000386's real fixtures: a subject
# whose target order gives dates 03-01 -> 03-03 -> 03-02 has BOTH rows of
# the inverted pair (03-03, 03-02) flagged, not just one; the row before
# the inversion (03-01) is never flagged.
#
# Each consecutive pair is compared at their OWN common (coarser) date
# precision - the same "truncate both to common precision" rule op_date.R's
# compare_dates_one() already uses - not a naive default-missing-components-
# to-1 comparison. Confirmed necessary against CORE-000535's real fixtures:
# a subject with dates "2005-10" (month precision), "2005-10-08" (day),
# "2005-10-06" (day), "2005-11" (month) in --SEQ order flags records 1, 2,
# AND 3 - not just the day-precision pair (2,3) that's a plain decrease.
# Truncating pair (1,2) to their common month precision makes them EQUAL
# ("2005-10" == "2005-10" truncated from "2005-10-08") - and equal (not
# strictly increasing) at truncated precision counts as "not sorted" too,
# exactly like op_date.R's date_equal_to treats differing-precision values
# as never truly equal. Only a single sort key has been observed in bundled
# rules (a list of length 1) - a real multi-key sort spec isn't implemented.
#' Does the pair (a then b) violate the requested sort order, truncating both to their common date precision?
#' @param a,b Single (possibly partial) date strings, or `NA`/`""` for blank.
#' @param descending If `TRUE`, checks for a non-increasing pair instead of non-decreasing.
#' @param null_first If `TRUE`, a blank/invalid value sorts before everything; otherwise after.
#' @return A single logical.
#' @noRd
sequence_date_pair_violates <- function(a, b, descending, null_first) {
  valid_a <- is_valid_date_str(a)
  valid_b <- is_valid_date_str(b)
  # A genuinely BLANK value sorts per null_position (a real, meaningful
  # absence). A PRESENT but unparseable value (e.g. a non-ISO "YYYY-MM-DD
  # HH:MM:SS" datetime using a space instead of "T", confirmed to appear in
  # some real SE fixtures) is a different situation entirely - there's no
  # sound value to sort it by, so the pair is left unflagged rather than
  # guessing via the same sentinel, which would otherwise make every such
  # value falsely "equal" to every other and flag the whole sequence.
  if (!valid_a && !is_blank(a)) {
    return(FALSE)
  }
  if (!valid_b && !is_blank(b)) {
    return(FALSE)
  }
  if (!valid_a || !valid_b) {
    sentinel <- if (null_first) -Inf else Inf
    if (descending) {
      sentinel <- -sentinel
    }
    va <- if (valid_a) as.numeric(parse_date_one(a)) else sentinel
    vb <- if (valid_b) as.numeric(parse_date_one(b)) else sentinel
    if (descending) vb >= va else vb <= va
  } else {
    # Precisions EQUAL (no truncation needed): only a genuine decrease is a
    # violation - a same-precision tie is fine (confirmed against
    # CORE-000386's own positive fixture: two same-day, same-precision
    # entries are NOT flagged). Precisions DIFFERENT: truncating to the
    # common (coarser) one can make the pair artificially equal, which
    # counts as a violation too (nothing proves it's actually non-
    # decreasing) - confirmed against CORE-000535's own fixture (a month-
    # precision date "equal" to a truncated day-precision one IS flagged).
    pa <- detect_precision_one(a)
    pb <- detect_precision_one(b)
    common <- min(pa, pb)
    va <- as.numeric(parse_date_one(a, common))
    vb <- as.numeric(parse_date_one(b, common))
    if (pa == pb) {
      if (descending) vb > va else vb < va
    } else {
      if (descending) vb >= va else vb <= va
    }
  }
}

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
    return(rep(FALSE, ctx$n))
  }
  descending <- identical(spec$sort_order, "desc")
  null_first <- identical(spec$null_position, "first")
  raw <- dt[[sort_col]]
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
      # ascending; null_position applies to a missing number only.
      x <- as.character(col)
      if (!is.character(col)) x[is_blank(col)] <- NA_character_
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
    tv <- suppressWarnings(as.integer(target))
    return(!(is.na(tv) | tv == position))
  }
  if (engine_is_core1()) {
    return(!core1_sorted_by(target, dt, group, ctx))
  }
  target_ord <- sequence_sort_key(target)

  result <- rep(FALSE, ctx$n)
  for (g in unique(group)) {
    idx <- which(group == g)
    ord_idx <- idx[order(target_ord[idx])]
    if (length(ord_idx) < 2) {
      next
    }
    for (i in seq_len(length(ord_idx) - 1)) {
      a <- ord_idx[i]
      b <- ord_idx[i + 1]
      if (sequence_date_pair_violates(raw[a], raw[b], descending, null_first)) {
        result[a] <- TRUE
        result[b] <- TRUE
      }
    }
  }
  result
})

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

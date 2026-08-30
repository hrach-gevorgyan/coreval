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
  within_col <- resolve_var_name(ctx$condition$within, ctx$domain)
  ordering_col <- resolve_var_name(ctx$condition$ordering, ctx$domain)
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
  ordering_col <- resolve_var_name(ctx$condition$ordering, ctx$domain)
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

# The Operations pipeline: pre-computes `$`-bound values before a rule's
# Check runs. A binding is one of:
#   - kind "scalar": a value (atomic vector, or a list for a set) used the
#     same way for every row of the dataset being checked.
#   - kind "grouped": an aggregate computed per group (e.g. per USUBJID),
#     joined back onto each row of the dataset being checked by matching
#     group-column values.
#   - kind "per_row": already one value per row of the CURRENT dataset
#     (only `dy`, which is inherently row-aligned - it doesn't aggregate).
# Operators needing CDISC Library metadata (codelist terms, the official
# SDTM Model's variable order/labels, etc.) are not implemented - there is
# no bundled data for them - and simply return NULL, which surfaces as an
# unresolvable binding.

apply_operation_filter <- function(dt, filter) {
  if (is.null(filter)) {
    return(dt)
  }
  keep <- rep(TRUE, nrow(dt))
  for (col in names(filter)) {
    if (col %in% names(dt)) {
      keep <- keep & (dt[[col]] == filter[[col]])
    }
  }
  dt[keep, ]
}

scalar_binding <- function(value) list(kind = "scalar", value = value)
grouped_binding <- function(group_cols, table, value_col) {
  list(kind = "grouped", group_cols = group_cols, table = table, value_col = value_col)
}
per_row_binding <- function(value) list(kind = "per_row", value = value)

distinct_values <- function(x) {
  x <- x[!is.na(x) & x != ""]
  sort(unique(x))
}

# Picks the max/min of a set of (possibly partial) date strings, ignoring
# invalid ones, using the same partial-date comparison as the date
# operators (op_date.R).
pick_date <- function(x, want_max) {
  x <- x[is_valid_date_str(x)]
  if (length(x) == 0) {
    return(NA_character_)
  }
  precisions <- vapply(x, detect_precision_one, integer(1))
  values <- vapply(seq_along(x), function(i) as.numeric(parse_date_one(x[i], precisions[i])), numeric(1))
  x[if (want_max) which.max(values) else which.min(values)]
}

compute_group_agg <- function(dt, group_cols, name, fn) {
  group_cols <- group_cols[group_cols %in% names(dt)]
  if (length(group_cols) == 0) {
    return(NULL)
  }
  agg <- dt[, list(.value = list(fn(get(name)))), by = group_cols]
  # Unlist scalar (non-set) results back into a plain column.
  if (all(lengths(agg$.value) == 1) && !is.list(fn(character(0)))) {
    agg$.value <- unlist(agg$.value)
  }
  agg
}

compute_dy <- function(op, study, current_dataset) {
  n <- nrow(current_dataset$data)
  dm <- study$datasets[["DM"]]
  if (is.null(dm) || !("RFSTDTC" %in% names(dm$data)) || !("USUBJID" %in% names(current_dataset$data))) {
    return(per_row_binding(rep(NA_character_, n)))
  }
  target_name <- resolve_var_name(op$name, "")
  if (!(target_name %in% names(current_dataset$data))) {
    return(per_row_binding(rep(NA_character_, n)))
  }
  rfstdtc_by_subject <- stats::setNames(dm$data$RFSTDTC, dm$data$USUBJID)
  target_vals <- current_dataset$data[[target_name]]
  usubjid <- current_dataset$data$USUBJID
  day <- vapply(seq_len(n), function(i) {
    tv <- target_vals[i]
    rf <- rfstdtc_by_subject[[usubjid[i]]]
    if (is.null(rf) || is.na(rf) || rf == "" || is.na(tv) || tv == "" ||
      !is_valid_date_str(tv) || !is_valid_date_str(rf)) {
      return(NA_real_)
    }
    delta_days <- as.numeric(difftime(parse_date_one(tv), parse_date_one(rf), units = "days"))
    if (delta_days < 0) delta_days else delta_days + 1
  }, numeric(1))
  per_row_binding(day)
}

compute_operation <- function(op, study, current_domain, current_dataset) {
  domain <- if (!is.null(op$domain)) op$domain else current_domain
  ds <- study$datasets[[domain]]
  dt <- if (!is.null(ds)) ds$data else NULL

  switch(op$operator,
    distinct = {
      if (is.null(dt) || !(op$name %in% names(dt))) {
        return(NULL)
      }
      filtered <- apply_operation_filter(dt, op$filter)
      if (is.null(op$group)) {
        scalar_binding(distinct_values(filtered[[op$name]]))
      } else {
        agg <- compute_group_agg(filtered, op$group, op$name, distinct_values)
        if (is.null(agg)) NULL else grouped_binding(op$group, agg, ".value")
      }
    },
    record_count = {
      if (is.null(dt)) {
        return(NULL)
      }
      filtered <- apply_operation_filter(dt, op$filter)
      if (is.null(op$group)) {
        scalar_binding(nrow(filtered))
      } else {
        group_cols <- op$group[op$group %in% names(dt)]
        if (length(group_cols) == 0) {
          return(NULL)
        }
        # A filter can leave a group with zero matching rows - it must
        # still resolve to 0, not "no binding for this group." Build the
        # group set from the FULL (unfiltered) data, then left-join the
        # filtered counts onto it.
        all_groups <- unique(dt[, group_cols, with = FALSE])
        filtered_counts <- filtered[, list(.value = .N), by = group_cols]
        agg <- merge(all_groups, filtered_counts, by = group_cols, all.x = TRUE)
        agg$.value[is.na(agg$.value)] <- 0
        grouped_binding(group_cols, agg, ".value")
      }
    },
    max_date = ,
    max = {
      if (is.null(dt) || !(op$name %in% names(dt))) {
        return(NULL)
      }
      filtered <- apply_operation_filter(dt, op$filter)
      picker <- function(x) pick_date(x, want_max = TRUE)
      if (is.null(op$group)) {
        scalar_binding(picker(filtered[[op$name]]))
      } else {
        agg <- compute_group_agg(filtered, op$group, op$name, picker)
        if (is.null(agg)) NULL else grouped_binding(op$group, agg, ".value")
      }
    },
    min_date = {
      if (is.null(dt) || !(op$name %in% names(dt))) {
        return(NULL)
      }
      filtered <- apply_operation_filter(dt, op$filter)
      picker <- function(x) pick_date(x, want_max = FALSE)
      if (is.null(op$group)) {
        scalar_binding(picker(filtered[[op$name]]))
      } else {
        agg <- compute_group_agg(filtered, op$group, op$name, picker)
        if (is.null(agg)) NULL else grouped_binding(op$group, agg, ".value")
      }
    },
    get_column_order_from_dataset = if (is.null(dt)) NULL else scalar_binding(names(dt)),
    variable_exists = if (is.null(dt)) scalar_binding(FALSE) else scalar_binding(resolve_var_name(op$name, domain) %in% names(dt)),
    variable_count = {
      target <- op$name
      count <- sum(vapply(names(study$datasets), function(dn) {
        resolve_var_name(target, dn) %in% names(study$datasets[[dn]]$data)
      }, logical(1)))
      scalar_binding(count)
    },
    study_domains = scalar_binding(sort(names(study$datasets))),
    dataset_names = scalar_binding(sort(tolower(names(study$datasets)))),
    domain_is_custom = scalar_binding(!(toupper(current_domain) %in% .coreval_env$domain_classes$domain)),
    extract_metadata = if (identical(op$name, "dataset_name")) scalar_binding(tolower(current_domain)) else NULL,
    dy = compute_dy(op, study, current_dataset),
    NULL
  )
}

compute_operation_bindings <- function(rule, study, current_domain, current_dataset) {
  bindings <- list()
  for (op in rule$operations) {
    bindings[[op$id]] <- compute_operation(op, study, current_domain, current_dataset)
  }
  bindings
}

# Resolves a binding to a per-row value (length nrow(dataset)) for equality-
# style use, or leaves it as a set for %in%-style use - either way, the
# caller (resolve_condition_value / operators) decides how to use it; this
# just performs the grouped join when needed.
resolve_binding <- function(binding, dataset) {
  if (is.null(binding)) {
    return(NULL)
  }
  if (binding$kind == "scalar") {
    return(binding$value)
  }
  if (binding$kind == "per_row") {
    return(binding$value)
  }
  # grouped: join the aggregate table onto `dataset` by group_cols.
  group_cols <- binding$group_cols
  if (!all(group_cols %in% names(dataset$data))) {
    return(rep(NA, nrow(dataset$data)))
  }
  key_of <- function(dt) do.call(paste, c(lapply(group_cols, function(c) dt[[c]]), sep = ""))
  row_keys <- key_of(dataset$data)
  table_keys <- key_of(binding$table)
  idx <- match(row_keys, table_keys)
  values <- binding$table[[binding$value_col]]
  if (is.list(values)) values[idx] else values[idx]
}

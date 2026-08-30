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

#' Filter a data.table to rows matching an Operations `filter` spec
#' @param dt A data.table.
#' @param filter Named list of column/value equality constraints, or `NULL`.
#' @return The filtered data.table.
#' @noRd
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

#' Construct a scalar Operations binding (one value used for every row)
#' @param value The value, used identically for every row.
#' @return A binding list with `kind = "scalar"`.
#' @noRd
scalar_binding <- function(value) list(kind = "scalar", value = value)

#' Construct a grouped Operations binding (a per-group aggregate joined back by `group_cols`)
#' @param group_cols Column names to join on.
#' @param table A data.table with `group_cols` plus `value_col`.
#' @param value_col Name of the aggregate value column in `table`.
#' @return A binding list with `kind = "grouped"`.
#' @noRd
grouped_binding <- function(group_cols, table, value_col) {
  list(kind = "grouped", group_cols = group_cols, table = table, value_col = value_col)
}

#' Construct a per-row Operations binding (already one value per row of the current dataset)
#' @param value A vector already aligned to the current dataset's rows.
#' @return A binding list with `kind = "per_row"`.
#' @noRd
per_row_binding <- function(value) list(kind = "per_row", value = value)

#' Sorted, unique, non-blank values of a vector
#' @param x A vector.
#' @return A sorted vector of unique non-blank values.
#' @noRd
distinct_values <- function(x) {
  x <- x[!is.na(x) & x != ""]
  sort(unique(x))
}

# Picks the max/min of a set of (possibly partial) date strings, ignoring
# invalid ones, using the same partial-date comparison as the date
# operators (op_date.R).
#' Pick the max/min of a set of (possibly partial) date strings, ignoring invalid ones
#' @param x Character vector of date strings.
#' @param want_max If `TRUE`, pick the maximum; otherwise the minimum.
#' @return A single date string, or `NA_character_` if none are valid.
#' @noRd
pick_date <- function(x, want_max) {
  x <- x[is_valid_date_str(x)]
  if (length(x) == 0) {
    return(NA_character_)
  }
  precisions <- vapply(x, detect_precision_one, integer(1))
  values <- vapply(seq_along(x), function(i) as.numeric(parse_date_one(x[i], precisions[i])), numeric(1))
  x[if (want_max) which.max(values) else which.min(values)]
}

#' Compute a per-group aggregate for a grouped Operations binding
#' @param dt A data.table.
#' @param group_cols Grouping column names.
#' @param name Column to aggregate.
#' @param fn Aggregation function applied to each group's values.
#' @return A data.table with `group_cols` plus a `.value` column, or `NULL` if no valid group columns.
#' @noRd
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

#' Compute a `dy` Operations binding (study day relative to DM.RFSTDTC)
#' @param op One Operations spec entry.
#' @param study Full study object.
#' @param current_dataset The dataset being checked.
#' @return A `per_row_binding()` of numeric study-day values.
#' @noRd
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
    # `[[` on an atomic named vector errors ("subscript out of bounds") for
    # a name that isn't present - unlike list indexing, it never returns
    # NULL - so a USUBJID with no DM record (a real data-quality issue this
    # package exists to catch) would crash the whole operation instead of
    # yielding NA for just that row.
    rf <- if (!is.na(usubjid[i]) && usubjid[i] %in% names(rfstdtc_by_subject)) {
      rfstdtc_by_subject[[usubjid[i]]]
    } else {
      NA_character_
    }
    if (is.na(rf) || rf == "" || is.na(tv) || tv == "" ||
      !is_valid_date_str(tv) || !is_valid_date_str(rf)) {
      return(NA_real_)
    }
    delta_days <- as.numeric(difftime(parse_date_one(tv), parse_date_one(rf), units = "days"))
    if (delta_days < 0) delta_days else delta_days + 1
  }, numeric(1))
  per_row_binding(day)
}

#' Compute a max_date/max or min_date Operations binding
#' @param dt The domain's data.table (or `NULL`).
#' @param op One Operations spec entry.
#' @param want_max If `TRUE`, pick the maximum date per group/overall; otherwise the minimum.
#' @return A binding (see `scalar_binding()`/`grouped_binding()`), or `NULL` if it can't be computed.
#' @noRd
date_extreme_binding <- function(dt, op, want_max) {
  if (is.null(dt) || !(op$name %in% names(dt))) {
    return(NULL)
  }
  filtered <- apply_operation_filter(dt, op$filter)
  picker <- function(x) pick_date(x, want_max = want_max)
  if (is.null(op$group)) {
    scalar_binding(picker(filtered[[op$name]]))
  } else {
    agg <- compute_group_agg(filtered, op$group, op$name, picker)
    if (is.null(agg)) NULL else grouped_binding(op$group, agg, ".value")
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Look up a domain's variables at a given SDTMIG Core designation (Req/Exp), version-aware
#'
#' Returns `NULL` (unresolvable) rather than guessing when the study's own
#' declared standard (from `.env`, see `read_env_standard()`) is explicitly
#' something OTHER than SDTMIG - confirmed necessary against CORE-000355's
#' own EX fixture, whose `.env` declares `SENDIG 3.1`: using SDTMIG's
#' required-variable list there would silently produce a plausible-but-wrong
#' answer for a rule that looks SDTM-flavored but isn't, for THIS test case.
#' An undeclared standard (no `.env` - a real XPT-based study) still
#' defaults to the newest available SDTMIG version, matching
#' sdtm_domain_classes.rds's own superset simplification, since there is no
#' per-study version signal to go on there either.
#' @param study Full study object.
#' @param domain Domain code.
#' @param core_value One of `"Req"`, `"Exp"`.
#' @return A character vector of variable names in ordinal order, or `NULL` if unresolvable.
#' @noRd
sdtmig_variables_for <- function(study, domain, core_value) {
  product <- study$standard$product %||% NA_character_
  if (!is.na(product) && !identical(product, "SDTMIG")) {
    return(NULL)
  }
  # Every SUPPxx dataset (SUPPAE, SUPPDM, ...) follows the SUPPQUAL template
  # and is keyed as "SUPPQUAL" in the Library data, not by its own literal
  # domain name - the same fallback domain_class() already uses.
  lookup_domain <- if (startsWith(toupper(domain), "SUPP") && nchar(domain) > 4) "SUPPQUAL" else domain
  tbl <- .coreval_env$sdtmig_variables
  version <- gsub("-", ".", study$standard$version %||% NA_character_, fixed = TRUE)
  use_version <- if (!is.na(version) && version %in% tbl$version) version else max(tbl$version)
  rows <- tbl[tbl$version == use_version & toupper(tbl$domain) == toupper(lookup_domain) & tbl$core == core_value, ]
  if (nrow(rows) == 0) {
    return(NULL)
  }
  rows$variable[order(as.numeric(rows$ordinal))]
}

#' Compute one Operations spec entry into a binding
#' @param op One Operations spec entry.
#' @param study Full study object.
#' @param current_domain Domain code of the dataset being checked.
#' @param current_dataset The dataset being checked.
#' @return A binding (see `scalar_binding()`/`grouped_binding()`/`per_row_binding()`), or `NULL`
#'   if the operation can't be computed (unimplemented, or missing data/column).
#' @noRd
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
    max = date_extreme_binding(dt, op, want_max = TRUE),
    min_date = date_extreme_binding(dt, op, want_max = FALSE),
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
    domain_label = scalar_binding(if (is.null(ds)) NA_character_ else ds$label),
    required_variables = {
      vars <- sdtmig_variables_for(study, domain, "Req")
      if (is.null(vars)) NULL else scalar_binding(vars)
    },
    expected_variables = {
      vars <- sdtmig_variables_for(study, domain, "Exp")
      if (is.null(vars)) NULL else scalar_binding(vars)
    },
    get_model_column_order = {
      cls <- domain_class(current_domain)
      if (is.na(cls)) {
        NULL
      } else {
        # Normalize "-" vs " " (e.g. model class "Special-Purpose" vs
        # sdtm_domain_classes.rds's "SPECIAL PURPOSE") before comparing.
        normalize_class <- function(x) toupper(gsub("-", " ", x, fixed = TRUE))
        model_class <- normalize_class(.coreval_env$model_variables$class)
        allowed <- .coreval_env$model_variables$variable[model_class == normalize_class(cls)]
        # Some classes (Special-Purpose, Relationship, Trial Design, Study
        # Reference) have NO generic class-level variable list in the Model
        # at all - each domain in them (DM, RELREC, TA, TI, ...) defines its
        # own bespoke variables instead. An empty `allowed` set would make
        # "is_not_contained_by" trivially flag every single variable as
        # disallowed, which is wrong - NULL (unresolvable) is honest instead.
        if (length(allowed) == 0) NULL else scalar_binding(resolve_var_name(allowed, current_domain))
      }
    },
    # Confirmed against CORE-000538's real fixtures: extract_metadata's
    # "dataset_name" reports the domain code AS-IS (uppercase, e.g.
    # "SUPPAE"), unlike the plural dataset_names Operations type (used by
    # e.g. CORE-000539/540), which is separately confirmed lowercase.
    extract_metadata = if (identical(op$name, "dataset_name")) scalar_binding(current_domain) else NULL,
    dy = compute_dy(op, study, current_dataset),
    NULL
  )
}

#' Compute all Operations bindings for a rule, keyed by operation id
#' @param rule A rule record.
#' @param study Full study object.
#' @param current_domain Domain code of the dataset being checked.
#' @param current_dataset The dataset being checked.
#' @return A named list of bindings (or `NULL` entries), keyed by `op$id`.
#' @noRd
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
#' Resolve an Operations binding to a per-row value (or leave a scalar set as-is)
#' @param binding A binding from `compute_operation()`, or `NULL`.
#' @param dataset The dataset the binding is being applied to.
#' @return The scalar/set value, a per-row vector, or (for a grouped binding) the joined values.
#' @noRd
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
  # grouped: join the aggregate table onto `dataset` by group_cols. When the
  # CURRENT dataset doesn't even have the join column (e.g. a grouped-by-
  # USUBJID binding computed from SV, applied to TV - a domain with no
  # USUBJID at all), this is unresolvable, not merely "NA for every row" -
  # returning NULL lets guarded_op()'s existing `is.null(ctx$value)` guard
  # make the whole condition NA (unresolvable), rather than a real value
  # vector of literal NAs. Confirmed necessary against CORE-000168: with a
  # literal-NA vector, is_not_contained_by's `target %in% c(NA, NA, ...)` is
  # FALSE for every real target value (NA never matches via `%in%`), so
  # `!FALSE` wrongly flagged every row of a domain the binding can't even
  # apply to, instead of leaving the condition unresolvable.
  group_cols <- binding$group_cols
  if (!all(group_cols %in% names(dataset$data))) {
    return(NULL)
  }
  # Separator must be unlikely to appear in real data - concatenating
  # multi-column keys with no separator at all collides across column
  # boundaries (e.g. ("1","23") and ("12","3") would both key to "123").
  key_of <- function(dt) do.call(paste, c(lapply(group_cols, function(c) dt[[c]]), sep = "\x1f"))
  row_keys <- key_of(dataset$data)
  table_keys <- key_of(binding$table)
  idx <- match(row_keys, table_keys)
  values <- binding$table[[binding$value_col]]
  if (is.list(values)) values[idx] else values[idx]
}

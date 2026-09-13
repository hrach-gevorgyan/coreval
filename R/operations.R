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

# A filter value ending in "&" is a PREFIX WILDCARD, not a literal - per
# the reference engine's own `_is_wildcard_pattern()` /
# `_apply_wildcard_filter()` (base_operation.py): `value.endswith("&")`
# selects `series.str.startswith(value.rstrip("&"), na=False)`, and only
# a non-"&" value falls through to `filtered_df[variable] == value`.
# Confirmed against CORE-000846's real fixture, whose `QNAM: RACE&` must
# match RACE1/RACE2/RACE3/RACEOTH/RACEA; read literally it matches
# nothing, silently collapsing a `record_count` to 0 and inverting the
# rule's `less_than_or_equal_to 1` verdict.
#
# `na=False` on the Python side also means a blank/NA cell is a
# non-match rather than an unknown - so NAs are folded to FALSE for the
# equality path too, which otherwise propagates NA into the row index and
# silently drops those rows' membership decision.
#' Filter a data.table to rows matching an Operations `filter` spec
#' @param dt A data.table.
#' @param filter Named list of column/value constraints (a value ending in
#'   `"&"` is a prefix wildcard), or `NULL`.
#' @return The filtered data.table.
#' @noRd
apply_operation_filter <- function(dt, filter) {
  if (is.null(filter)) {
    return(dt)
  }
  keep <- rep(TRUE, nrow(dt))
  for (col in names(filter)) {
    if (col %in% names(dt)) {
      value <- filter[[col]]
      matched <- if (is.character(value) && length(value) == 1L && endsWith(value, "&")) {
        startsWith(as.character(dt[[col]]), sub("&+$", "", value))
      } else {
        dt[[col]] == value
      }
      matched[is.na(matched)] <- FALSE
      keep <- keep & matched
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
grouped_binding <- function(group_cols, table, value_col, regex = NULL) {
  list(
    kind = "grouped", group_cols = group_cols, table = table,
    value_col = value_col,
    # Carried so resolve_binding() can key each row the SAME way the table
    # was grouped. A regex-grouped table holds reduced values (a date, not a
    # full datetime), so keying rows off their raw values would match nothing.
    regex = regex
  )
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
  # One pass of the date regex, reused three times. Validating, detecting
  # precision and parsing each recomputed the components over the same vector.
  comp <- extract_date_components(ifelse(is.na(x), "", x))
  keep <- is_valid_date_str(x, comp)
  x <- x[keep]
  if (length(x) == 0) {
    return(NA_character_)
  }
  comp <- subset_date_components(comp, keep)
  # Vectorised, like compute_dy(): the scalar wrappers re-ran the date regex
  # once per element.
  values <- as.numeric(parse_date(x, detect_precision(x, comp), comp))
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
#' @param current_domain Domain code, used to resolve a `"--"`-templated `op$name` (e.g. `"--STDTC"`).
#' @return A `per_row_binding()` of numeric study-day values.
#' @noRd
compute_dy <- function(op, study, current_dataset, current_domain) {
  n <- nrow(current_dataset$data)
  dm <- study$datasets[["DM"]]
  if (is.null(dm) || !("RFSTDTC" %in% names(dm$data)) || !("USUBJID" %in% names(current_dataset$data))) {
    return(per_row_binding(rep(NA_character_, n)))
  }
  target_name <- resolve_var_name(op$name, dataset_wildcard(current_dataset, current_domain))
  if (!(target_name %in% names(current_dataset$data))) {
    return(per_row_binding(rep(NA_character_, n)))
  }
  target_vals <- as.character(current_dataset$data[[target_name]])
  usubjid <- current_dataset$data$USUBJID

  # Each subject's reference start date, looked up for every row at once.
  # match() on a name that is absent gives NA rather than erroring, so a
  # USUBJID with no DM record - a real data-quality problem this package
  # exists to catch - yields NA for that row instead of crashing the whole
  # operation, which is what `[[` on a named atomic vector would do.
  rf <- dm$data$RFSTDTC[match(usubjid, dm$data$USUBJID)]
  rf <- as.character(rf)

  # Vectorised for the same reason op_date.R is: this ran per row, calling the
  # SCALAR date wrappers, so the date regex was re-run twice for every row of
  # every domain for every rule needing --DY. It was 84% of a whole
  # check_study().
  # Study day is defined on the DATE portion of each timestamp, not the
  # instant: "--DY = (date portion of --DTC) - (date portion of RFSTDTC) + 1".
  # Keeping the time made difftime return fractions, so a row whose --DY was
  # perfectly correct compared unequal and got flagged. With an RFSTDTC of
  # 2012-11-30T20:00, a --DTC of 2012-11-23 gave -7.83 against a stored -7,
  # and same-day 2012-11-30T13:00 gave -0.29 against a stored 1. Any study
  # whose RFSTDTC carries a time would see nearly every --DY reported.
  target_dates <- sub("T.*$", "", target_vals)
  rf_dates <- sub("T.*$", "", rf)

  usable <- !is.na(rf) & nzchar(rf) & !is.na(target_vals) & nzchar(target_vals)
  day <- rep(NA_real_, n)
  if (any(usable)) {
    idx <- which(usable)
    # The date regex is the expensive part, so run it ONCE per vector and hand
    # the components to everything that needs them. Validating and then
    # parsing each side re-ran it, so the same two columns were scanned four
    # times instead of twice. `is_valid_date_str()` and `parse_date()` both
    # take a `comp` argument for exactly this.
    comp_t <- extract_date_components(ifelse(is.na(target_dates), "", target_dates))
    comp_r <- extract_date_components(ifelse(is.na(rf_dates), "", rf_dates))
    ok <- is_valid_date_str(target_dates[idx], subset_date_components(comp_t, idx)) &
      is_valid_date_str(rf_dates[idx], subset_date_components(comp_r, idx))
    idx <- idx[ok]
    if (length(idx) > 0) {
      delta <- as.numeric(difftime(
        parse_date(target_dates[idx], comp = subset_date_components(comp_t, idx)),
        parse_date(rf_dates[idx], comp = subset_date_components(comp_r, idx)),
        units = "days"
      ))
      # Study day has no zero: the day before the reference date is -1, the
      # reference date itself is day 1.
      day[idx] <- ifelse(delta < 0, delta, delta + 1)
    }
  }
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

#' The dataset columns an Operations entry needs by name
#'
#' Used only to decide whether the raw dataset can answer the operation at all,
#' so it lists the places a column name can appear rather than trying to be a
#' complete reading of the spec. A `$`-prefixed value is an earlier binding,
#' not a column, and is left out.
#'
#' @param op An Operations entry.
#' @return A character vector of column names, possibly empty.
#' @noRd
operation_columns_used <- function(op) {
  names_used <- c(
    as.character(unlist(op$group %||% character(0))),
    names(op$filter %||% list()),
    # `version`/`ct_version` and `term_code` name columns too, and for a rule
    # that joins another entity in they are columns of the JOINED data rather
    # than the raw dataset. Leaving them out meant the fallback below never
    # triggered for them and the operation refused a column that was there.
    as.character(op$version %||% character(0)),
    as.character(op$ct_version %||% character(0)),
    as.character(op$term_code %||% character(0)),
    as.character(op$term_value %||% character(0))
  )
  for (entry in op$map %||% list()) {
    names_used <- c(names_used, setdiff(names(entry), "output"))
  }
  names_used <- names_used[nzchar(names_used) & !startsWith(names_used, "$")]
  unique(names_used)
}

#' Which bundled CT family a package type or standard names
#' @param what A `ct_package_type` ("SDTM") or a standard product ("SENDIG").
#' @return One of `"adamct"`, `"sendct"`, `"sdtmct"`.
#' @noRd
ct_family_for <- function(what) {
  std <- toupper(what %||% "")
  if (grepl("ADAM", std, fixed = TRUE)) {
    "adamct"
  } else if (grepl("SEND", std, fixed = TRUE)) {
    "sendct"
  } else {
    "sdtmct"
  }
}

#' Resolve an Operations parameter that may name a column, a binding, or a literal
#'
#' A parameter like `codelist_code` can be `$codelist_code` (an earlier
#' Operations result), a column of the dataset, or a plain value. The reference
#' does not distinguish, because it writes every operation result into the
#' dataset as a column and then just looks for the name; bindings are kept
#' separate here, so the three cases are tried in that order.
#'
#' @param value The parameter, possibly `NULL`.
#' @param bindings Bindings resolved so far.
#' @param dt The dataset being checked.
#' @return A character vector (length 1, or one per row), or `NULL`.
#' @noRd
resolve_operation_reference <- function(value, bindings, dt) {
  if (is.null(value)) {
    return(NULL)
  }
  key <- as.character(value)[[1]]
  bound <- bindings[[key]]
  if (!is.null(bound)) {
    if (identical(bound$kind, "scalar") || identical(bound$kind, "per_row")) {
      return(as.character(bound$value))
    }
    return(NULL)
  }
  if (!is.null(dt) && key %in% names(dt)) {
    return(as.character(dt[[key]]))
  }
  # Not a binding and not a column, so the rule means the text itself. A
  # codelist C-code written out in full is a legitimate way to say it.
  key
}

#' Rename a grouped binding's group columns to their `group_aliases`
#'
#' An Operations entry can aggregate over one dataset and be used while
#' checking another: `record_count` with `domain: StudyIdentifier`,
#' `group: parent_id`, `group_aliases: id` counts StudyIdentifier rows per
#' `parent_id` and joins the answer onto StudyVersion's `id`. The group columns
#' are named as the SOURCE holds them, and the aliases name the same columns as
#' the dataset being checked holds them.
#'
#' Positional, per the reference's `_rename_grouping_columns`: alias `i`
#' replaces group column `i`, and a group column with no alias keeps its name.
#' Applied to whatever the operation produced rather than inside each type,
#' because the reference does it once for every grouped result too.
#'
#' Without this the join back onto each row matches on a column the dataset
#' being checked does not have, so every row resolves to nothing and the
#' condition reads as unresolvable. That is what left CORE-000401's
#' `$num_sponsor_ids` empty and stopped the rule reporting anything.
#'
#' @param binding A binding from `compute_operation()`, possibly `NULL`.
#' @param op The Operations entry.
#' @return The binding, with group columns renamed where an alias applies.
#' @noRd
apply_group_aliases <- function(binding, op) {
  aliases <- op$group_aliases
  if (is.null(binding) || is.null(aliases) || !identical(binding$kind, "grouped")) {
    return(binding)
  }
  aliases <- as.character(unlist(aliases))
  group <- as.character(unlist(op$group))
  # The binding's own group_cols, not op$group: a group column that was not a
  # column of the source data has already been dropped, so positions are taken
  # from what actually survived.
  for (i in seq_along(binding$group_cols)) {
    pos <- match(binding$group_cols[[i]], group)
    if (!is.na(pos) && pos <= length(aliases) && !identical(aliases[[pos]], binding$group_cols[[i]])) {
      data.table::setnames(binding$table, binding$group_cols[[i]], aliases[[pos]])
      binding$group_cols[[i]] <- aliases[[pos]]
    }
  }
  binding
}

#' The largest or smallest value of a column, whatever its type
#'
#' `max`/`min` and `max_date`/`min_date` are four different operations in the
#' reference, not two: `Maximum` is a plain aggregate over whatever the column
#' holds, while `MaxDate` parses ISO 8601 first. Both `max` and `max_date`
#' routed through the date picker here, which validates against a date regex
#' and yields NA for anything else, so `max` over a non-date column silently
#' produced no binding at all and the rule using it quietly found nothing.
#'
#' Only one bundled rule uses `max` today and its column is a date, so nothing
#' shipped was wrong. USDM's CORE-000808 takes `min` of an `id` column holding
#' values like `Code_16`, which is what made the gap visible.
#'
#' Blank strings are dropped before comparing. An empty character is not a
#' value, and keeping it would make it the minimum of every text column.
#'
#' @param dt A data.table, or `NULL`.
#' @param op The Operations entry.
#' @param want_max `TRUE` for the maximum.
#' @return A binding, or `NULL` when the column is absent.
#' @noRd
extreme_binding <- function(dt, op, want_max) {
  if (is.null(dt) || !(op$name %in% names(dt))) {
    return(NULL)
  }
  filtered <- apply_operation_filter(dt, op$filter)
  picker <- function(x) {
    if (is.character(x)) x <- x[!is.na(x) & nzchar(x)] else x <- x[!is.na(x)]
    if (length(x) == 0) {
      return(if (is.character(x)) NA_character_ else NA_real_)
    }
    if (want_max) max(x) else min(x)
  }
  if (is.null(op$group)) {
    scalar_binding(picker(filtered[[op$name]]))
  } else {
    agg <- compute_group_agg(filtered, op$group, op$name, picker)
    if (is.null(agg)) NULL else grouped_binding(op$group, agg, ".value")
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# The CDISC Library's own variable metadata, for whichever standard the
# study actually declares. Keyed by (standard, version, domain, variable),
# with Core designation, ordinal, label, role and data type.
#
# A CORE test case that LOOKS SDTM-flavoured is not necessarily SDTMIG - its
# `_env` can declare SENDIG or another standard entirely (CORE-000355's EX
# fixture is SENDIG 3.1). Using SDTMIG's list there would produce a
# plausible-but-wrong answer, so the standard is always resolved from the
# study rather than assumed.
# The newest ordinary version among a standard's cached versions.
#
# Not `max()`: alongside the numbered releases ("3-1-2", "3-4") the cache
# also holds APPENDIX variants keyed by name ("ap-1-0", "md-1-0", "md-1-1"),
# and a plain lexicographic max picks "md-1-1" over "3-4" - silently
# selecting an appendix's variable list as if it were the newest SDTMIG.
# Numbered versions are also compared component-wise, so "3-10" would sort
# above "3-4" rather than below it as string comparison would have it.
#' Pick the newest numbered version from a set of CDISC Library version strings
#' @param versions Character vector of dashed version strings.
#' @return A single version string.
#' @noRd
newest_library_version <- function(versions) {
  versions <- unique(versions)
  numbered <- versions[grepl("^[0-9]", versions)]
  if (length(numbered) == 0) {
    return(max(versions))
  }
  parts <- lapply(strsplit(numbered, "-", fixed = TRUE), as.numeric)
  width <- max(lengths(parts))
  padded <- vapply(parts, function(p) {
    paste(sprintf("%06d", c(p, rep(0, width - length(p)))), collapse = ".")
  }, character(1))
  numbered[order(padded)][length(numbered)]
}

#' Rows of CDISC Library variable metadata matching a study's standard and domain
#' @param study Full study object (its `$standard` selects standard/version).
#' @param domain Domain code.
#' @return A data.frame of matching rows (possibly zero-row).
#' @noRd
library_variables_for <- function(study, domain) {
  tbl <- .coreval_env$library_variables
  product <- study$standard$product %||% NA_character_
  standard <- if (is.na(product)) "sdtmig" else tolower(product)
  # TIG bundles per-substandard tables (tig-sdtm, tig-send, ...). Without a
  # substandard signal, SDTM is the sensible default for tabulation data.
  if (identical(standard, "tig")) {
    standard <- "tig-sdtm"
  }
  if (!(standard %in% tbl$standard)) {
    return(tbl[0, ])
  }
  rows <- tbl[tbl$standard == standard, ]

  # Version strings are dashed in both the `_env` file and the cache keys
  # ("3-4"), so they compare directly. An undeclared or unknown version
  # falls back to the newest available for that standard.
  version <- study$standard$version %||% NA_character_
  use_version <- if (!is.na(version) && version %in% rows$version) {
    version
  } else {
    newest_library_version(rows$version)
  }
  rows <- rows[rows$version == use_version, ]

  # Every SUPPxx dataset (SUPPAE, SUPPDM, ...) follows the SUPPQUAL template
  # and is keyed as "SUPPQUAL" in the Library data, not by its own literal
  # domain name - the same fallback domain_class() already uses.
  lookup_domain <- if (startsWith(toupper(domain), "SUPP") && nchar(domain) > 4) "SUPPQUAL" else domain
  rows[toupper(rows$domain) == toupper(lookup_domain), ]
}

#' The label the STANDARD gives a domain, for a study's declared standard
#'
#' Not the label the study's own metadata carries. The reference reads this from
#' the standard's dataset metadata (`operations/domain_label.py`), and the two
#' differ: SENDIG calls `LB` "Laboratory" where SDTMIG calls it
#' "Laboratory Test Results". CORE-000272 asks whether `--CAT` equals that
#' label, so answering with the study's own label answers a different question -
#' it missed the violation CDISC's engine reports on that rule's own fixture,
#' whose `.env` declares SENDIG 3-1.
#'
#' Falls back to the dataset's own label when the standard or domain is unknown,
#' which is better than returning nothing for a sponsor's custom domain.
#'
#' @param study Full study object (its `$standard` selects standard/version).
#' @param domain Domain code.
#' @param dataset The domain's dataset, for the fallback label.
#' @return A single label string, or `NA_character_`.
#' @noRd
standard_domain_label <- function(study, domain, dataset = NULL) {
  fallback <- if (is.null(dataset)) NA_character_ else (dataset$label %||% NA_character_)
  tbl <- .coreval_env$dataset_labels
  if (is.null(tbl)) {
    return(fallback)
  }
  product <- study$standard$product %||% NA_character_
  standard <- if (is.na(product)) "sdtmig" else tolower(product)
  if (identical(standard, "tig")) {
    standard <- "tig-sdtm"
  }
  rows <- tbl[tbl$standard == standard, ]
  if (nrow(rows) == 0) {
    return(fallback)
  }
  version <- study$standard$version %||% NA_character_
  use_version <- if (!is.na(version) && version %in% rows$version) {
    version
  } else {
    newest_library_version(rows$version)
  }
  rows <- rows[rows$version == use_version, ]
  hit <- rows$label[toupper(rows$domain) == toupper(domain)]
  if (length(hit) == 0) fallback else hit[1]
}

# Class names differ cosmetically between sources ("FINDINGS ABOUT" in a
# rule's Scope, "Findings About" in the Model cache), so compare them
# case- and hyphen-insensitively rather than literally.
#' Normalize an observation-class name for comparison
#' @param x Character vector of class names.
#' @return The normalized names.
#' @noRd
normalize_class <- function(x) toupper(gsub("-", " ", x, fixed = TRUE))

# An Operations spec can narrow a metadata lookup to rows whose `key_name`
# field equals `key_value` (e.g. role == "Timing"). Both keys are optional;
# without them every row is kept.
#' Apply an Operations spec's optional `key_name`/`key_value` filter
#' @param rows A data.frame of metadata rows.
#' @param op One Operations spec entry.
#' @return The filtered rows.
#' @noRd
filter_metadata_rows <- function(rows, op) {
  key <- op$key_name
  if (is.null(key) || nrow(rows) == 0 || !(key %in% names(rows))) {
    return(rows)
  }
  rows[!is.na(rows[[key]]) & rows[[key]] == op$key_value, ]
}

# The SDTM Model's own variables for a domain's observation class, with the
# generic "--" templates resolved against that domain (so "--CHENDY" becomes
# "LBCHENDY" for LB).
#
# This is the FALLBACK behind library_variables_for(): an Implementation
# Guide's per-domain list doesn't enumerate every variable a sponsor may
# legitimately use, but the Model's generic templates cover many of them.
# Without it a Model-defined variable looks entirely undefined, and rules
# comparing observed metadata against the Library's treat it as unknown
# rather than checking it against the type the Model actually specifies.
#' The SDTM Model's variables for a domain, with `"--"` templates resolved
#' @param domain Domain code.
#' @param dataset The dataset being checked, for `"--"` resolution.
#' @return A data.frame with `variable`, `label`, `role`, `type`.
#' @noRd
model_variables_for <- function(domain, dataset = NULL) {
  tbl <- .coreval_env$model_variables
  cls <- domain_class(domain)
  # Every class inherits the General Observations variables.
  rows <- tbl[normalize_class(tbl$class) %in% normalize_class(c("General Observations", cls)), ]
  if (nrow(rows) == 0) {
    return(rows)
  }
  rows$variable <- resolve_var_name(rows$variable, dataset_wildcard(dataset, domain))
  rows[!duplicated(rows$variable), ]
}

# The standard's full expected variable ORDER for a domain, which is NOT
# either source read alone: the reference merges the Implementation Guide's
# per-domain list INTO the SDTM Model's, positionally
# (`sdtm_utilities.get_variables_metadata_from_standard`).
#
# The Model supplies the skeleton, in three sections - General Observations
# identifiers, the class's own variables, then General Observations timing.
# Each IG variable then either REPLACES a Model variable of the same name,
# keeping the Model's position, or is INSERTED at its section's boundary:
# an Identifier after the identifiers, a Timing at the very end, anything
# else just before the timing section.
#
# Order is the entire point - the only rule using this asks whether a
# dataset's column order is an ordered subset of the standard's - so
# approximating it is worse than not answering. Appending the Model's
# extras at the end, for instance, puts CMDTC after CMSTDTC and reports a
# violation that isn't there.
#' The standard's expected variable order for a domain (IG merged into Model)
#' @param study Full study object (its `$standard` selects standard/version).
#' @param domain Domain code.
#' @param dataset The dataset being checked, for `"--"` resolution.
#' @return A character vector of variable names in the standard's order.
#' @noRd
standard_variable_order <- function(study, domain, dataset) {
  cls <- domain_class(domain)
  model <- .coreval_env$model_variables
  wildcard <- dataset_wildcard(dataset, domain)

  # Only the three general observation classes (plus Findings About) build
  # from the Model at all. Everything else - Special Purpose, Trial Design,
  # Relationship - takes the Implementation Guide's list verbatim, in its
  # own ordinal order. Giving those the Model's identifier/timing skeleton
  # too would pad the expected order with variables the standard doesn't
  # list for them, and an "is this an ordered subset" check would then
  # accept orders it should reject (caught on SE).
  detectable <- normalize_class(c("Findings", "Interventions", "Events", "Findings About"))
  if (!(normalize_class(cls) %in% detectable)) {
    ig_only <- library_variables_for(study, domain)
    if (nrow(ig_only) == 0) {
      return(character(0))
    }
    ig_only <- ig_only[order(ig_only$ordinal), , drop = FALSE]
    return(resolve_var_name(ig_only$variable, wildcard))
  }

  in_class <- normalize_class(model$class) == normalize_class(cls)
  if (!any(in_class)) {
    return(character(0))
  }
  rows <- model[in_class, ]
  ordered <- function(x) x[order(x$ordinal), , drop = FALSE]
  from_general <- normalize_class(rows$source_class) == normalize_class("General Observations")

  identifiers <- ordered(rows[from_general & rows$role == "Identifier", ])$variable
  timing <- ordered(rows[from_general & rows$role == "Timing", ])$variable
  class_own <- ordered(rows[!from_general, ])$variable

  # Findings About is a special case in the reference: it inherits the
  # FINDINGS class variables too, and its own variables are SPLICED INTO
  # them immediately after "--TEST" rather than appended. Getting this wrong
  # only shows up as a wrong ORDER, which is precisely what the rule using
  # this checks.
  if (identical(normalize_class(cls), normalize_class("Findings About"))) {
    findings <- model[
      normalize_class(model$class) == normalize_class("Findings") &
        normalize_class(model$source_class) != normalize_class("General Observations"),
    ]
    findings_own <- ordered(findings)$variable
    at <- match("--TEST", findings_own)
    if (!is.na(at)) {
      class_own <- c(findings_own[seq_len(at)], class_own, findings_own[-seq_len(at)])
    }
  }
  skeleton <- resolve_var_name(c(identifiers, class_own, timing), wildcard)
  n_identifiers <- length(identifiers)
  n_timing <- length(timing)

  ig <- library_variables_for(study, domain)
  if (nrow(ig) == 0) {
    return(skeleton)
  }
  ig <- ig[order(ig$ordinal), , drop = FALSE]
  ig_names <- resolve_var_name(ig$variable, wildcard)

  for (k in seq_along(ig_names)) {
    name <- ig_names[k]
    at <- match(name, skeleton)
    if (!is.na(at)) {
      next # already positioned by the Model
    }
    role <- ig$role[k]
    insert_at <- if (identical(role, "Identifier")) {
      n_identifiers
    } else if (identical(role, "Timing")) {
      length(skeleton)
    } else {
      length(skeleton) - n_timing
    }
    skeleton <- append(skeleton, name, after = insert_at)
    if (identical(role, "Identifier")) {
      n_identifiers <- n_identifiers + 1L
    } else if (identical(role, "Timing")) {
      n_timing <- n_timing + 1L
    }
  }
  skeleton
}

#' Look up a domain's variables at a given Core designation (Req/Exp), standard- and version-aware
#' @param study Full study object.
#' @param domain Domain code.
#' @param core_value One of `"Req"`, `"Exp"`.
#' @return A character vector of variable names in ordinal order, or `NULL` if unresolvable.
#' @noRd
sdtmig_variables_for <- function(study, domain, core_value) {
  rows <- library_variables_for(study, domain)
  rows <- rows[rows$core == core_value, ]
  if (nrow(rows) == 0) {
    return(NULL)
  }
  rows$variable[order(rows$ordinal)]
}

#' The bundled Controlled Terminology table, read on first use
#'
#' Not loaded in `.onLoad()` like the other bundled metadata. It is the largest
#' thing the package ships - 0.54 MB on disk, about 16 MB once expanded - and
#' only the handful of rules that ask about codelist membership need it, so a
#' session that never runs one pays nothing.
#'
#' @return A data.frame of codelists, or `NULL` if the file is not installed.
#' @noRd
ct_codelists <- function() {
  if (is.null(.coreval_env$ct_codelists)) {
    path <- system.file("extdata", "ct_codelists.rds", package = "coreval")
    if (!nzchar(path)) {
      return(NULL)
    }
    .coreval_env$ct_codelists <- readRDS(path)
  }
  .coreval_env$ct_codelists
}

#' Package names of the bundled Controlled Terminology
#' @return A character vector, e.g. `"sdtmct-2026-03-27"`.
#' @noRd
ct_package_names <- function() {
  tbl <- ct_codelists()
  if (is.null(tbl)) character(0) else sort(unique(tbl$package))
}

#' The terms (or codes) of the codelists an Operations entry names
#'
#' Mirrors the reference's `CodelistTerms._handle_single_version()`: look each
#' codelist up by SUBMISSION VALUE, case-insensitively, within one CT package,
#' and return either the codelist's own attribute or its terms', depending on
#' `level` and `returntype`.
#'
#' Which package is used is the caller's choice, exactly as it is for the
#' reference's `-ct` argument - terminology changes between releases, so
#' picking one on the user's behalf would judge a study against terms it never
#' declared. A codelist the package does not contain raises, because answering
#' "not in the codelist" from a codelist that was never found would report
#' every value in the column as a violation.
#'
#' @param op The Operations entry.
#' @param study The study, for its declared `ct_package`.
#' @return A character vector of values or codes.
#' @noRd
ct_terms_for <- function(op, study) {
  package <- study$ct_package
  tbl <- ct_codelists()
  if (is.null(tbl)) {
    stop("the bundled controlled terminology is not installed", call. = FALSE)
  }
  rows <- tbl[tbl$package == package, ]
  if (nrow(rows) == 0) {
    stop("no bundled controlled terminology package named '", package, "'",
         call. = FALSE)
  }
  wanted <- as.character(unlist(op$codelists, use.names = FALSE))
  level <- op$level %||% "term"
  returntype <- op$returntype %||% (if (identical(level, "codelist")) "value" else "code")

  out <- character(0)
  for (name in wanted) {
    i <- match(tolower(name), tolower(rows$codelist))
    if (is.na(i)) {
      stop("codelist '", name, "' is not in controlled terminology package '",
           package, "'", call. = FALSE)
    }
    out <- c(out, if (identical(level, "codelist")) {
      if (identical(returntype, "code")) rows$codelist_code[i] else rows$codelist[i]
    } else {
      field <- if (identical(returntype, "value")) rows$term_values[i] else rows$term_codes[i]
      if (nzchar(field)) strsplit(field, "", fixed = TRUE)[[1]] else character(0)
    })
  }
  out
}

# Every Operations type compute_operation() can actually compute. The single
# source of truth: the conformance harness reads THIS, rather than keeping its
# own copy that could drift from what the switch below handles.
#
# It exists because the switch used to fall through to NULL for anything it did
# not recognise, so a rule declaring an unimplemented Operations type produced
# no binding, and its condition then resolved to literal text - reporting
# nothing at all, or everything, with no indication either way. CORE-000934
# (`split_by`) did exactly that: CDISC's engine reports rows 4 and 5 for its
# own fixture and check_study() reported none.
implemented_operation_types <- c(
  "codelist_terms",
  "get_codelist_attributes",
  "split_by",
  "dataset_names",
  "distinct",
  "domain_is_custom",
  "domain_label",
  "dy",
  "expected_variables",
  "extract_metadata",
  "get_column_order_from_dataset",
  "get_column_order_from_library",
  "get_dataset_filtered_variables",
  "get_model_column_order",
  "get_model_filtered_variables",
  "get_parent_model_column_order",
  "codelist_extensible",
  "map",
  "max",
  "max_date",
  "min",
  "min_date",
  "record_count",
  "required_variables",
  "study_domains",
  "valid_codelist_dates",
  "variable_count",
  "variable_exists"
)

#' Compute one Operations spec entry into a binding
#' @param op One Operations spec entry.
#' @param study Full study object.
#' @param current_domain Domain code of the dataset being checked.
#' @param current_dataset The dataset being checked.
#' @return A binding (see `scalar_binding()`/`grouped_binding()`/`per_row_binding()`), or `NULL`
#'   if the operation can't be computed (unimplemented, or missing data/column).
#' @noRd
compute_operation <- function(op, study, current_domain, current_dataset, bindings = list()) {
  # A `group` entry can be a `$`-binding standing for a SET of column names
  # rather than a single column (CORE-001034 groups by "$TIMING_VARIABLES").
  # Left unexpanded it matches no column, is silently dropped, and the
  # grouping is quietly coarser than the rule asked for - which inflates
  # every count rather than failing visibly.
  if (!is.null(op$group)) {
    op$group <- unlist(lapply(op$group, function(g) {
      if (is.character(g) && length(g) == 1L && startsWith(g, "$")) {
        b <- bindings[[g]]
        if (is.null(b)) character(0) else as.character(b$value)
      } else {
        g
      }
    }), use.names = FALSE)
  }
  # An Operations `domain` can be a "--" template like "SUPP--" meaning
  # "this domain's supplemental dataset". Resolving "--" to the DOMAIN
  # column's value doesn't work for a SUPP dataset (it has no DOMAIN of its
  # own), so when the template's resolution isn't a real dataset but the
  # CURRENT dataset's own name fits the template, the rule is talking about
  # the dataset being checked - which is the case for every bundled rule
  # scoped to SUPP--/CO/RELREC.
  domain <- if (!is.null(op$domain)) op$domain else current_domain
  if (is.character(domain) && length(domain) == 1L && grepl("--", domain, fixed = TRUE)) {
    resolved <- sub("--", dataset_wildcard(current_dataset, current_domain), domain, fixed = TRUE)
    domain <- if (!is.null(study$datasets[[toupper(resolved)]])) {
      resolved
    } else if (grepl(paste0("^", sub("--", ".*", domain, fixed = TRUE), "$"), toupper(current_domain))) {
      current_domain
    } else {
      resolved
    }
  }
  # An operation that names no domain works on the dataset being CHECKED, which
  # by this point has had the rule's Match Datasets joins applied - the
  # reference runs its operations against the same merged evaluation_dataset.
  # Re-fetching the raw dataset from the study instead threw the join away, so
  # an operation keying on a joined column (USDM's `parent_rel.Code`) could not
  # see it.
  #
  # Dataset keys are upper-cased by every reader here, and an SDTM rule names
  # its domain that way already ("DM"), so the lookup below is a no-op for
  # them. USDM rules name entities in mixed case ("StudyIdentifier"), which
  # found nothing and left the binding unresolved.
  ds <- study$datasets[[toupper(domain)]]
  dt <- if (!is.null(ds)) ds$data else NULL
  # Only when the raw dataset cannot answer. Handing every operation the joined
  # dataset instead was tried and is wrong: it turned five passing rules
  # (CORE-000219, -000272, -000573, -000575, -000852) into failures and skips,
  # because a one-to-many Match Datasets join repeats left rows and so changes
  # every count and aggregate computed over them. The fallback widens only the
  # case the raw data genuinely does not cover, which is an operation keying on
  # a column the join produced.
  if (is.null(op$domain) && !is.null(current_dataset)) {
    wanted <- operation_columns_used(op)
    joined <- current_dataset$data
    if (length(wanted) > 0 && !all(wanted %in% names(dt)) && all(wanted %in% names(joined))) {
      dt <- joined
    }
  }

  # Refused, not answered with NULL. An unrecognised type used to leave the
  # binding missing, which resolve_condition_value() then treated as literal
  # text - the silent-failure shape this package keeps finding. Raising lets
  # check_study() record a skip with a reason.
  if (!(op$operator %in% implemented_operation_types)) {
    stop("unimplemented Operations type: ", op$operator, call. = FALSE)
  }
  binding <- switch(op$operator,
    distinct = {
      if (is.null(dt) || !(op$name %in% names(dt))) {
        return(NULL)
      }
      filtered <- apply_operation_filter(dt, op$filter)
      # `value_is_reference` makes each value a COLUMN NAME to be looked up
      # in the domain that row points at, rather than a value in its own
      # right. The reference's Distinct keeps only those names that really
      # are columns of the referenced dataset (`_check_column_exists_in_dataset`),
      # dropping the rest - so the resulting set is "the IDVARs that name a
      # real variable of their RDOMAIN", which is exactly what lets
      # `IDVAR is_not_contained_by $rdomain_variables` flag a typo like
      # LBSEK while leaving a valid LBSEQ alone.
      if (isTRUE(op$value_is_reference)) {
        ref_col <- op$referenced_domain_variable %||% "RDOMAIN"
        if (!(ref_col %in% names(filtered))) {
          return(NULL)
        }
        names_seen <- vapply(seq_len(nrow(filtered)), function(i) {
          referenced <- study$datasets[[toupper(as.character(filtered[[ref_col]][i]))]]
          candidate <- as.character(filtered[[op$name]][i])
          if (is.null(referenced) || is.na(candidate) || !(candidate %in% names(referenced$data))) {
            NA_character_
          } else {
            candidate
          }
        }, character(1))
        return(scalar_binding(distinct_values(names_seen)))
      }
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
        # An Operations `regex` means "group on this much of the value" -
        # see apply_grouping_regex(). It has to be applied to BOTH sides,
        # and to the data the binding is later resolved against, or the
        # join back onto each row finds no matching group.
        dt <- apply_grouping_regex(dt, group_cols, op$regex)
        filtered <- apply_grouping_regex(filtered, group_cols, op$regex)
        # A filter can leave a group with zero matching rows - it must
        # still resolve to 0, not "no binding for this group." Build the
        # group set from the FULL (unfiltered) data, then left-join the
        # filtered counts onto it.
        all_groups <- unique(dt[, group_cols, with = FALSE])
        filtered_counts <- filtered[, list(.value = .N), by = group_cols]
        agg <- merge(all_groups, filtered_counts, by = group_cols, all.x = TRUE)
        agg$.value[is.na(agg$.value)] <- 0
        grouped_binding(group_cols, agg, ".value", regex = op$regex)
      }
    },
    max_date = date_extreme_binding(dt, op, want_max = TRUE),
    min_date = date_extreme_binding(dt, op, want_max = FALSE),
    max = extreme_binding(dt, op, want_max = TRUE),
    min = extreme_binding(dt, op, want_max = FALSE),
    get_column_order_from_dataset = if (is.null(dt)) NULL else scalar_binding(names(dt)),
    # The standard's expected variable order - see standard_variable_order(),
    # which merges the IG's per-domain list into the Model's skeleton
    # positionally rather than reading either alone.
    get_column_order_from_library = {
      order_names <- standard_variable_order(study, current_domain, current_dataset)
      if (length(order_names) == 0) NULL else scalar_binding(order_names)
    },
    # The SDTM MODEL's variables for this domain's class, filtered by a
    # metadata key (e.g. role == "Timing"). Distinct from
    # get_column_order_from_library, which reads the Implementation Guide's
    # per-domain list rather than the abstract Model's per-class one.
    # Which CT package versions CDISC actually published, as the ISO dates
    # a study's own TSVCDVER would cite. Only the DATES are bundled, not the
    # terminology itself (see data-raw/ct_packages.R) - which is all this
    # operation needs, and is why the operations that need the terms
    # themselves stay unimplemented.
    # Membership of a CDISC Controlled Terminology codelist. `level` picks
    # the codelist itself or its terms; `returntype` picks submission values
    # or C-codes. The rules use the result as a set, with
    # `is_contained_by`/`is_not_contained_by`.
    # One column split on a delimiter, giving each row a LIST of parts rather
    # than one value - PPSPEC records several specimens as "LIVER;KIDNEY", and
    # the rule asks whether every part is a legal term. The reference is
    # `self.evaluation_dataset[target].str.split(delimiter)`.
    split_by = {
      target <- resolve_var_name(op$name %||% "", dataset_wildcard(current_dataset, current_domain))
      if (is.null(op$delimiter) || !nzchar(op$delimiter)) {
        stop("split_by needs a delimiter", call. = FALSE)
      }
      if (is.null(dt) || !(target %in% names(dt))) {
        NULL
      } else {
        per_row_binding(strsplit(as.character(dt[[target]]), op$delimiter, fixed = TRUE))
      }
    },
    codelist_terms = scalar_binding(ct_terms_for(op, study)),
    # Every value of one attribute across a whole CT package - "every term
    # C-code CDISC published in this version" - for the rows that cite a
    # bundled package. Refused rather than answered with an empty set when the
    # data cites none, or when rows cite DIFFERENT versions: an empty set makes
    # `is_not_contained_by` true for every row, and picking one of several
    # versions would judge the rest against terminology they did not name.
    get_codelist_attributes = {
      pkgs <- ct_packages_per_row(
        current_dataset$data, op$name %||% "", op$version %||% "",
        study$standard$product
      )
      bundled <- unique(pkgs[nzchar(pkgs) & pkgs %in% ct_package_names()])
      if (length(bundled) == 0) {
        stop(
          "no row names a bundled controlled terminology package in ",
          op$name %||% "?", "/", op$version %||% "?",
          call. = FALSE
        )
      }
      if (length(bundled) > 1) {
        stop(
          "rows cite more than one controlled terminology version (",
          paste(bundled, collapse = ", "), "), so there is no single set to ",
          "check against",
          call. = FALSE
        )
      }
      scalar_binding(ct_package_attribute(bundled, op$ct_attribute %||% "Term CCODE"))
    },
    # A lookup table written into the rule itself. Each entry is a record of
    # key columns plus `output`; the row's output is the one whose keys match.
    # An entry with no keys at all is the reference's direct-assignment branch
    # (`if not merge_columns and len(map) == 1`), which every bundled use of
    # this type takes: `map: [{output: C66797}]` binds that constant.
    map = {
      entries <- op$map
      if (is.null(entries) || length(entries) == 0) {
        stop("map operation declares no entries", call. = FALSE)
      }
      key_names <- setdiff(unique(unlist(lapply(entries, names))), "output")
      if (length(key_names) == 0) {
        if (length(entries) != 1L) {
          stop("map operation has several entries but no keys to choose between them",
               call. = FALSE)
        }
        scalar_binding(as.character(entries[[1]]$output))
      } else {
        if (is.null(dt)) {
          return(NULL)
        }
        missing_keys <- setdiff(key_names, names(dt))
        if (length(missing_keys) > 0) {
          stop("map operation keys on column(s) the dataset does not have: ",
               paste(missing_keys, collapse = ", "), call. = FALSE)
        }
        lookup <- data.table::rbindlist(lapply(entries, function(e) {
          as.list(vapply(c(key_names, "output"), function(k) {
            v <- e[[k]]
            if (is.null(v)) NA_character_ else as.character(v)[[1]]
          }, character(1)))
        }), fill = TRUE)
        keys <- do.call(paste, c(lapply(key_names, function(k) as.character(dt[[k]])), sep = "\r"))
        lookup_keys <- do.call(paste, c(lapply(key_names, function(k) lookup[[k]]), sep = "\r"))
        per_row_binding(lookup$output[match(keys, lookup_keys)])
      }
    },
    # Whether the codelist a row cites is extensible in the CT version that
    # same row cites. Both vary by row, so this is per-row rather than scalar:
    # `version` names a column holding the CT release date and `codelist_code`
    # is usually an earlier binding rather than a column.
    codelist_extensible = {
      if (is.null(dt)) {
        return(NULL)
      }
      version_col <- op$version %||% op$ct_version %||% ""
      if (!(version_col %in% names(dt))) {
        stop("codelist_extensible needs a column of CT versions; '",
             version_col, "' is not one", call. = FALSE)
      }
      codes <- resolve_operation_reference(op$codelist_code, bindings, dt)
      if (is.null(codes)) {
        stop("codelist_extensible cannot resolve its codelist code: ",
             as.character(op$codelist_code %||% "?"), call. = FALSE)
      }
      family <- ct_family_for(op$ct_package_type %||% study$standard$product)
      versions <- trimws(as.character(dt[[version_col]]))
      packages <- ifelse(is.na(versions) | !nzchar(versions), NA_character_,
                         paste0(family, "-", versions))
      tbl <- ct_codelists()
      if (is.null(tbl)) {
        stop("the bundled controlled terminology is not installed", call. = FALSE)
      }
      key <- paste(packages, codes, sep = "\r")
      ref <- paste(tbl$package, tbl$codelist_code, sep = "\r")
      # NA, not FALSE, where the pair is unknown. "This codelist is not
      # extensible" and "we have never heard of this codelist in that release"
      # are different answers, and collapsing them would let a rule report a
      # violation about terminology it could not look up.
      per_row_binding(tbl$extensible[match(key, ref)])
    },
    valid_codelist_dates = {
      tbl <- .coreval_env$ct_packages
      types <- toupper(op$ct_package_types %||% op$ct_package_type %||% character(0))
      if (length(types) > 0) {
        tbl <- tbl[tbl$package_type %in% types, ]
      }
      if (nrow(tbl) == 0) NULL else scalar_binding(sort(unique(tbl$package_date)))
    },
    # The variables of THIS dataset that carry a given metadata role,
    # taken from the standard rather than guessed from names. The reference
    # derives the standard's list then intersects it with the dataset's
    # actual columns; only that intersection is observable here, so the
    # IG/Model ordering problem that blocks get_column_order_from_library
    # doesn't arise - CORE-001034 uses the result as GROUPING columns,
    # which is set-based.
    get_dataset_filtered_variables = {
      standard_rows <- rbind(
        library_variables_for(study, current_domain)[, c("variable", "role", "type"), drop = FALSE],
        model_variables_for(current_domain, current_dataset)[, c("variable", "role", "type"), drop = FALSE]
      )
      standard_rows <- filter_metadata_rows(standard_rows, op)
      wanted <- resolve_var_name(
        unique(standard_rows$variable), dataset_wildcard(current_dataset, current_domain)
      )
      present <- intersect(wanted, names(current_dataset$data))
      if (length(present) == 0) NULL else scalar_binding(present)
    },
    # For a SUPP dataset, the MODEL variables of the parent domain each row
    # points at via RDOMAIN - which can differ row by row, since one SUPP
    # dataset may carry qualifiers for several parents. Used to check that a
    # supplemental qualifier's QNAM doesn't collide with a real variable
    # name of its parent domain.
    get_parent_model_column_order = {
      rdomain <- current_dataset$data[["RDOMAIN"]]
      if (is.null(rdomain)) {
        NULL
      } else {
        by_parent <- lapply(
          stats::setNames(nm = unique(toupper(rdomain))),
          function(p) model_variables_for(p, current_dataset)$variable
        )
        per_row_binding(unname(by_parent[toupper(rdomain)]))
      }
    },
    get_model_filtered_variables = {
      rows <- filter_metadata_rows(model_variables_for(current_domain, current_dataset), op)
      if (nrow(rows) == 0) NULL else scalar_binding(rows$variable)
    },
    variable_exists = if (is.null(dt)) scalar_binding(FALSE) else scalar_binding(resolve_var_name(op$name, dataset_wildcard(ds, domain)) %in% names(dt)),
    variable_count = {
      target <- op$name
      count <- sum(vapply(names(study$datasets), function(dn) {
        resolve_var_name(target, dataset_wildcard(study$datasets[[dn]], dn)) %in% names(study$datasets[[dn]]$data)
      }, logical(1)))
      scalar_binding(count)
    },
    # The DOMAIN VALUES a study actually contains, not its dataset NAMES.
    # The reference (operations/study_domains.py) is
    # `list({(dataset.domain or "") for dataset in get_datasets()})`, where
    # SDTMDatasetMetadata.domain is `(first_record or {}).get("DOMAIN", None)`
    # - the DOMAIN column of each dataset's FIRST RECORD, and `""` when the
    # dataset has no DOMAIN column at all (every SUPP--/SQ-- dataset, and any
    # file whose header is unreadable).
    #
    # The distinction decides CORE-000457 ("SUPP--.RDOMAIN must name a dataset
    # present in the study"): its positive fixture ships an `ec.csv` with a
    # blank header row, so the reference sees no EC domain and flags
    # SUPPEC.RDOMAIN="EC", while a name-based set contains "EC" and reports
    # nothing. The empty string is deliberately kept in the set, so a
    # domainless dataset makes an RDOMAIN of "" compare as present.
    study_domains = scalar_binding(sort(unique(vapply(
      study$datasets,
      function(d) {
        dom <- d$data[["DOMAIN"]]
        if (is.null(dom) || length(dom) == 0) {
          return("")
        }
        first <- trimws(as.character(dom[1]))
        if (is.na(first)) "" else first
      },
      character(1)
    )))),
    # Matches the reference engine's own derivation (csv_metadata_reader.py:
    # dataset_name = Filename.upper() when there's no separate "Dataset
    # Name" column) - confirmed directly against CORE-000539/CORE-000540's
    # real fixtures, whose own reported $list_dataset_names values are
    # UPPERCASE (e.g. "['QS1', 'QSAE']", "['FA', 'FA1', 'FACM']"). An
    # earlier version used tolower() here - an unverified assumption that
    # silently broke every use of this binding downstream (e.g.
    # prefix_is_not_contained_by comparing an uppercase dataset_name
    # against a lowercase list never matches).
    dataset_names = scalar_binding(sort(toupper(names(study$datasets)))),
    domain_is_custom = scalar_binding(!(toupper(current_domain) %in% .coreval_env$domain_classes$domain)),
    domain_label = scalar_binding(standard_domain_label(study, current_domain, ds)),
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
        model_class <- normalize_class(.coreval_env$model_variables$class)
        allowed <- .coreval_env$model_variables$variable[model_class == normalize_class(cls)]
        # Some classes (Special-Purpose, Relationship, Trial Design, Study
        # Reference) have NO generic class-level variable list in the Model
        # at all - each domain in them (DM, RELREC, TA, TI, ...) defines its
        # own bespoke variables instead. Ask the Model for THAT domain's own
        # variables, which is where the reference engine reads them from too.
        # Returning NULL here instead (as this did until
        # sdtm_model_dataset_variables.rds existed) made the rule unresolvable
        # and silently found nothing on DM - CORE-000550's invalid ARMCDXX
        # went unreported.
        if (length(allowed) == 0) {
          dsv <- .coreval_env$model_dataset_variables
          allowed <- dsv$variable[dsv$domain == current_domain]
        }
        # An Associated Persons dataset carries its observation class's
        # variables PLUS the ones that make it an AP dataset in the first
        # place (APID, RSUBJID, SREL), which the Model keeps in a class of
        # their own. Without them APEG's own defining variables look
        # disallowed - coreval flagged all three and missed the one variable
        # (XEGBEATNO) that really is not in the Model.
        if (startsWith(current_domain, "AP") && nchar(current_domain) > 2 &&
          !startsWith(current_domain, "APID")) {
          allowed <- c(allowed, .coreval_env$model_variables$variable[
            model_class == normalize_class("Associated Persons")
          ])
        }
        # Still nothing (a domain the Model does not describe at either
        # level): an empty `allowed` set would make "is_not_contained_by"
        # trivially flag every single variable as disallowed, which is wrong
        # - NULL (unresolvable) is honest instead.
        if (length(allowed) == 0) {
          NULL
        } else {
          scalar_binding(resolve_var_name(allowed, dataset_wildcard(current_dataset, current_domain)))
        }
      }
    },
    # Confirmed against CORE-000538's real fixtures: extract_metadata's
    # "dataset_name" reports the domain code AS-IS (uppercase, e.g.
    # "SUPPAE"), unlike the plural dataset_names Operations type (used by
    # e.g. CORE-000539/540), which is separately confirmed lowercase.
    extract_metadata = if (identical(op$name, "dataset_name")) scalar_binding(current_domain) else NULL,
    dy = compute_dy(op, study, current_dataset, current_domain),
    NULL
  )
  apply_group_aliases(binding, op)
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
    # Operations are computed in declaration order because a later one may
    # REFER to an earlier one - CORE-001034 groups by "$TIMING_VARIABLES",
    # a set of column names produced by the operation above it.
    bindings[[op$id]] <- compute_operation(
      op, study, current_domain, current_dataset,
      bindings = bindings
    )
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
  row_keys <- key_of(apply_grouping_regex(
    dataset$data[, group_cols, with = FALSE], group_cols, binding$regex
  ))
  table_keys <- key_of(binding$table)
  idx <- match(row_keys, table_keys)
  values <- binding$table[[binding$value_col]]
  if (is.list(values)) values[idx] else values[idx]
}

#' The controlled terminology version a study declares in TS
#'
#' Studies record it themselves: the Trial Summary dataset carries `TSVCDREF`
#' (the terminology's publisher, "CDISC") and `TSVCDVER` (its version, an ISO
#' date). Reading it is better than asking the caller, because it is what the
#' study says about itself - the same principle as taking the standard and
#' version from the data rather than assuming SDTMIG.
#'
#' Rows whose `TSVCDREF` is not CDISC are ignored: they cite someone else's
#' terminology, which is not what the bundled packages are. Where the remaining
#' rows disagree - real TS datasets do, usually a stale row or two - the
#' version most rows agree on wins, and a tie takes the newest.
#'
#' @param study A study object.
#' @return A bundled package name, or `NULL` if TS says nothing usable.
#' @noRd
ct_package_from_ts <- function(study) {
  ts <- study$datasets[["TS"]]$data
  if (is.null(ts) || !all(c("TSVCDREF", "TSVCDVER") %in% names(ts))) {
    return(NULL)
  }
  ref <- toupper(trimws(as.character(ts$TSVCDREF)))
  ver <- trimws(as.character(ts$TSVCDVER))
  keep <- !is.na(ver) & nzchar(ver) & !is.na(ref) & ref == "CDISC"
  if (!any(keep)) {
    return(NULL)
  }
  counts <- sort(table(ver[keep]), decreasing = TRUE)
  top <- names(counts)[counts == counts[[1]]]
  version <- top[order(top, decreasing = TRUE)][1]

  # SEND studies cite SEND terminology, SDTM studies SDTM's, and the two
  # genuinely differ - SENDIG's LB codelist is not SDTMIG's.
  product <- toupper(study$standard$product %||% NA_character_)
  family <- if (!is.na(product) && startsWith(product, "SEND")) "sendct" else "sdtmct"
  candidate <- paste0(family, "-", version)
  if (candidate %in% ct_package_names()) candidate else NULL
}

#' The CT package each row of a dataset cites, per `get_codelist_attributes`
#'
#' Trial Summary rows name their own terminology: a reference column (whose
#' value is "CDISC", "CDISC CT", or someone else entirely - ISO 8601, SNOMED,
#' UNII) and a version column. The reference builds a package name per row from
#' the two, prefixing CDISC's own with the standard family
#' (`get_codelist_attributes.py`).
#'
#' @param dt The dataset.
#' @param target Column naming the terminology's publisher.
#' @param version Column naming its version.
#' @param product The study's standard, e.g. `"SENDIG"`.
#' @return A character vector, `""` where the row cites nothing usable.
#' @noRd
ct_packages_per_row <- function(dt, target, version, product) {
  n <- nrow(dt)
  if (!(target %in% names(dt)) || !(version %in% names(dt))) {
    return(rep("", n))
  }
  ref <- trimws(as.character(dt[[target]]))
  ver <- trimws(as.character(dt[[version]]))
  std <- toupper(product %||% "")
  family <- if (grepl("ADAM", std, fixed = TRUE)) {
    "adamct"
  } else if (grepl("SEND", std, fixed = TRUE)) {
    "sendct"
  } else {
    "sdtmct"
  }
  out <- ifelse(
    is.na(ver) | !nzchar(ver), "",
    ifelse(!is.na(ref) & ref %in% c("CDISC", "CDISC CT"),
           paste0(family, "-", ver),
           paste0(ref, "-", ver))
  )
  out[is.na(out)] <- ""
  out
}

#' Every value of one attribute across a whole CT package
#'
#' `get_codelist_attributes` asks a package-wide question - "every term C-code
#' CDISC published in this version" - rather than about one codelist, so this
#' unions the attribute over all of the package's codelists. The attribute
#' names are the reference's own (`_extract_codes_by_attribute`).
#'
#' @param package A bundled CT package name.
#' @param attribute One of the `ct_attribute` values the reference accepts.
#' @return A character vector of values.
#' @noRd
ct_package_attribute <- function(package, attribute) {
  tbl <- ct_codelists()
  if (is.null(tbl)) {
    stop("the bundled controlled terminology is not installed", call. = FALSE)
  }
  rows <- tbl[tbl$package == package, ]
  if (nrow(rows) == 0) {
    return(character(0))
  }
  # Preferred terms are not bundled, so a rule asking for them is refused
  # rather than answered from data that is not here.
  values <- switch(
    attribute,
    "Codelist CCODE" = rows$codelist_code,
    "Codelist Value" = rows$codelist,
    "Term CCODE" = unlist(strsplit(rows$term_codes, "\x1f", fixed = TRUE), use.names = FALSE),
    "Term Value" = unlist(strsplit(rows$term_values, "\x1f", fixed = TRUE), use.names = FALSE),
    "Term Submission Value" = unlist(strsplit(rows$term_values, "\x1f", fixed = TRUE), use.names = FALSE),
    stop("unsupported ct_attribute: ", attribute, call. = FALSE)
  )
  unique(values[nzchar(values)])
}

# Operators only CORE 1.0's rules use, ported from verisianHQ/cdisc-rules-engine
# (check_operators/sql/, wired up in postgresql_operators.py). Each says which
# file it follows. Where 1.0 treats a blank target specially, so does the port.

#' Run an operator with target and value lower-cased
#'
#' The `_case_insensitive` variants in 1.0 lower-case both sides
#' (`LOWER(...)`, or `~*` for a pattern) and otherwise behave as the plain
#' operator does.
#'
#' @param op The plain operator's name.
#' @return An operator function of `ctx`.
#' @noRd
case_insensitive_op <- function(op) {
  function(ctx) {
    lower <- function(x) if (is.list(x)) lapply(x, lower) else if (is.character(x)) tolower(x) else x
    ctx$target <- lower(ctx$target)
    ctx$value <- lower(ctx$value)
    get_operator(op)(ctx)
  }
}

# matches_regex_operator.py with `~*`. The pattern itself is not lower-cased,
# so "^FA" still means FA in either case: "(?i)" asks for that instead.
register_operator("matches_regex_case_insensitive", function(ctx) {
  if (is.character(ctx$value)) ctx$value <- paste0("(?i)", ctx$value)
  get_operator("matches_regex")(ctx)
})
register_operator("not_matches_regex_case_insensitive", function(ctx) {
  if (is.character(ctx$value)) ctx$value <- paste0("(?i)", ctx$value)
  get_operator("not_matches_regex")(ctx)
})

#' The first or last N characters of a target, as 1.0's LEFT()/RIGHT() take them
#' @param ctx Operator context.
#' @param side `"prefix"` or `"suffix"`.
#' @return A character vector.
#' @noRd
core1_affix <- function(ctx, side) {
  x <- target_text(ctx$target)
  n <- as.integer(ctx$condition[[side]])
  if (side == "prefix") substr(x, 1, n) else substr(x, pmax(nchar(x) - n + 1, 1), nchar(x))
}

# prefix_ and suffix_matches_regex_operator.py with `~*`: a blank target is
# FALSE whichever way round the question is asked.
affix_regex_ci <- function(side, invert) {
  guarded_op(function(ctx) {
    hit <- grepl(paste0("(?i)", ctx$value), core1_affix(ctx, side), perl = TRUE)
    !is_blank(ctx$target) & (if (invert) !hit else hit)
  })
}
register_operator("prefix_matches_regex_case_insensitive", affix_regex_ci("prefix", FALSE))
register_operator("not_prefix_matches_regex_case_insensitive", affix_regex_ci("prefix", TRUE))
register_operator("suffix_matches_regex_case_insensitive", affix_regex_ci("suffix", FALSE))
register_operator("not_suffix_matches_regex_case_insensitive", affix_regex_ci("suffix", TRUE))

# postgresql_operators.py: IsContainedByOperator(case_insensitive = TRUE) on the
# prefix or suffix, and its NotOperator.
register_operator("prefix_is_contained_by_case_insensitive", case_insensitive_op("prefix_is_contained_by"))
register_operator("prefix_is_not_contained_by_case_insensitive", case_insensitive_op("prefix_is_not_contained_by"))
register_operator("suffix_is_contained_by_case_insensitive", case_insensitive_op("suffix_is_contained_by"))
register_operator("suffix_is_not_contained_by_case_insensitive", case_insensitive_op("suffix_is_not_contained_by"))

# string_length_comparison_operator.py: a blank target is FALSE, a number is a
# length, and anything else is compared by its own length.
length_compare <- function(cmp) {
  guarded_op(function(ctx) {
    against <- ctx$value
    if (!is.numeric(against)) {
      num <- suppressWarnings(as.numeric(against))
      against <- if (!anyNA(num)) num else nchar(as.character(against))
    }
    out <- cmp(nchar(target_text(ctx$target)), against)
    out[is_blank(ctx$target)] <- FALSE
    out
  })
}
register_operator("shorter_than_or_equal_to", length_compare(`<=`))
register_operator("longer_than_or_equal_to", length_compare(`>=`))

# prefix_suffix_equal_to_operator.py for the suffix: compared lower-cased on
# both sides, any of a list matching, and a blank target never equal.
register_operator("suffix_equal_to", guarded_op(function(ctx) {
  part <- tolower(core1_affix(ctx, "suffix"))
  values <- tolower(as.character(unlist(ctx$value)))
  hit <- if (length(values) == length(part) && !is.list(ctx$value)) part == values else part %in% values
  !is_blank(ctx$target) & hit
}))
register_operator("suffix_not_equal_to", function(ctx) {
  !get_operator("suffix_equal_to")(ctx)
})

# is_substring_of_operator.py, for a column target: the value is found inside
# the comparator, or inside any member of a comparator set. Blank on either
# side is not a substring of anything.
register_operator("is_substring_of", guarded_op(function(ctx) {
  target <- as.character(ctx$target)
  inside <- function(needle, haystack) {
    haystack <- haystack[!is.na(haystack) & nzchar(haystack)]
    length(haystack) > 0 && any(vapply(haystack, function(h) grepl(needle, h, fixed = TRUE), logical(1)))
  }
  per_row <- is.list(ctx$value) && length(ctx$value) == ctx$n
  vapply(seq_along(target), function(i) {
    if (is_blank(target[i])) {
      return(FALSE)
    }
    hay <- if (per_row) ctx$value[[i]] else if (length(ctx$value) == ctx$n) ctx$value[i] else ctx$value
    inside(target[i], as.character(unlist(hay)))
  }, logical(1))
}))
register_operator("is_not_substring_of", function(ctx) {
  !get_operator("is_substring_of")(ctx)
})

# in_enumerated_columns_operator.py: does the value appear in the target
# variable or in any of its numbered siblings (RACE, RACE1, RACE2, ...)?
# A blank on either side never matches.
register_operator("in_enumerated_columns", function(ctx) {
  base <- resolve_var_name(ctx$condition$name, ctx$wildcard)
  pattern <- ctx$condition$regex %||% paste0("^", base, "[0-9]*$")
  cols <- grep(pattern, names(ctx$dataset$data), value = TRUE, ignore.case = TRUE, perl = TRUE)
  if (length(cols) == 0 || is.null(ctx$value)) {
    return(rep(FALSE, ctx$n))
  }
  value <- rep_len(as.character(ctx$value), ctx$n)
  ci <- isTRUE(ctx$condition$case_insensitive)
  hit <- rep(FALSE, ctx$n)
  for (col in cols) {
    x <- as.character(ctx$dataset$data[[col]])
    same <- if (ci) tolower(x) == tolower(value) else x == value
    hit <- hit | (!is_blank(x) & !is_blank(value) & same %in% TRUE)
  }
  hit
})
register_operator("not_in_enumerated_columns", function(ctx) {
  !get_operator("in_enumerated_columns")(ctx)
})

# is_ordered_set_operator.py: within each group of the `value` columns, are
# the target's values in ascending order down the rows as they stand? Numbers
# compare as numbers, anything else as text. A group with any step down is
# out of order on every row; a blank target is never reported.
register_operator("is_not_ordered_set", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  groups <- vapply(as.character(unlist(ctx$condition$value)), function(v) resolve_var_name(v, ctx$wildcard),
                   character(1), USE.NAMES = FALSE)
  dt <- ctx$dataset$data
  if (!all(groups %in% names(dt))) {
    stop("is_not_ordered_set groups by ", paste(setdiff(groups, names(dt)), collapse = ", "),
         ", which is not a column of this dataset", call. = FALSE)
  }
  key <- if (length(groups)) do.call(paste, c(lapply(groups, function(g) as.character(dt[[g]])), sep = "\x1f"))
         else rep("", ctx$n)
  x <- as.character(ctx$target)
  blank <- is_blank(ctx$target)
  bad <- character(0)
  for (g in unique(key)) {
    idx <- which(key == g)
    if (length(idx) < 2) next
    prev <- x[idx[-length(idx)]]
    curr <- x[idx[-1]]
    ok <- !is.na(prev) & !is.na(curr)
    numeric_pair <- ok & grepl("^[0-9]+(\\.[0-9]+)?$", prev) & grepl("^[0-9]+(\\.[0-9]+)?$", curr)
    down <- ifelse(numeric_pair, suppressWarnings(as.numeric(prev) > as.numeric(curr)), prev > curr)
    if (any(ok & down %in% TRUE)) bad <- c(bad, g)
  }
  !blank & key %in% bad
})
register_operator("is_ordered_set", function(ctx) {
  !is_blank(ctx$target) & !get_operator("is_not_ordered_set")(ctx)
})

# invalid_date_interval_operator.py: one solidus with something on each side,
# and the parts a date and a date, a date and a duration, or a duration and a
# date. A duration here may not be negative. A blank is invalid.
register_operator("invalid_date_interval", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  x <- as.character(ctx$target)
  x[is.na(x)] <- ""
  shaped <- grepl("^[^/]+/[^/]+$", x)
  start <- sub("/.*$", "", x)
  end <- sub("^[^/]*/", "", x)
  date_ok <- function(p) !core1_invalid_date(p)
  dur_ok <- function(p) is_valid_duration(p, duration_regex_positive)
  valid <- shaped & ((date_ok(start) & date_ok(end)) | (date_ok(start) & dur_ok(end)) |
                       (dur_ok(start) & date_ok(end)))
  !valid
})

# The external-dictionary checks: MedDRA, WHODrug, UNII, LOINC, SNOMED CT and
# MED-RT. CORE 1.0 reads them from dictionaries the user supplies and reports
# "Not applicable" without one. coreval has no way to be given one yet, so
# each refuses with the dictionary it needs, and the rule is skipped with that
# reason rather than as an unknown operator.
dictionary_refusal <- function(dictionary) {
  force(dictionary)
  function(ctx) {
    stop("needs ", dictionary, ", which is not supplied: ",
         "coreval does not read external dictionaries yet", call. = FALSE)
  }
}
local({
  dictionaries <- c(meddra = "MedDRA", whodrug = "WHODrug", unii = "UNII", loinc = "LOINC",
                    snomed = "SNOMED CT", medrt = "MED-RT")
  for (key in names(dictionaries)) {
    for (kind in c("code", "term")) {
      for (prefix in c("is_valid_", "is_not_valid_")) {
        register_operator(paste0(prefix, key, "_", kind, "_reference"),
                          dictionary_refusal(paste("the", dictionaries[[key]], "dictionary")))
      }
    }
  }
  register_operator("is_valid_whodrug_level_reference", dictionary_refusal("the WHODrug dictionary"))
  register_operator("is_not_valid_whodrug_level_reference", dictionary_refusal("the WHODrug dictionary"))
})

# is_latest_available_exdict_version.py: the dictionary release that was
# current on the target date (the newest released on or before it) is the
# version given. 1.0 knows MedDRA's release dates and no other dictionary's,
# and refuses the rest; a date before the earliest release it knows has no
# current release, so it is never the latest.
meddra_release_dates <- c(
  "29.0" = "2026-03-01", "28.1" = "2025-09-01", "28.0" = "2025-03-01", "27.1" = "2024-09-01",
  "27.0" = "2024-03-01", "26.1" = "2023-09-01", "26.0" = "2023-03-01", "25.1" = "2022-09-01",
  "25.0" = "2022-03-01", "24.1" = "2021-09-01", "24.0" = "2021-03-01", "23.1" = "2020-09-01"
)
latest_exdict <- function(ctx) {
  if (!identical(tolower(ctx$condition$external_dictionary_type %||% ""), "meddra")) {
    stop("no release dates are known for the ", ctx$condition$external_dictionary_type,
         " dictionary", call. = FALSE)
  }
  ref <- ctx$condition$version
  version <- if (is.character(ref) && startsWith(ref, "$")) {
    b <- ctx$bindings[[ref]]
    if (is.null(b)) stop("cannot resolve ", ref, call. = FALSE)
    as.character(b$value)
  } else if (is.character(ref) && ref %in% names(ctx$dataset$data)) {
    as.character(ctx$dataset$data[[ref]])
  } else {
    as.character(ref)
  }
  when <- suppressWarnings(as.Date(substr(as.character(ctx$target), 1, 10)))
  dates <- as.Date(meddra_release_dates)
  current <- vapply(when, function(d) {
    if (is.na(d)) return(NA_character_)
    ok <- names(meddra_release_dates)[dates <= d]
    if (length(ok)) ok[which.max(dates[dates <= d])] else NA_character_
  }, character(1))
  current == rep_len(version, length(current))
}
register_operator("is_latest_available_external_dictionary_version", function(ctx) {
  if (!ctx$exists) return(rep(FALSE, ctx$n))
  latest_exdict(ctx) %in% TRUE
})
register_operator("is_not_latest_available_external_dictionary_version", function(ctx) {
  if (!ctx$exists) return(rep(FALSE, ctx$n))
  !(latest_exdict(ctx) %in% TRUE)
})

#' Is each value an invalid date, by CORE 1.0's test?
#'
#' A port of `InvalidDateOperator.invalid_date_sql()`
#' (invalid_date_operator.py), case by case and in its order. It is stricter
#' than CDISC's in places: a time needs minutes, so "2012-11-23T00" is
#' invalid, and a range must be two months or two dates. Empty is invalid.
#'
#' @param x A character vector.
#' @return A logical vector.
#' @noRd
core1_invalid_date <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  has <- function(p) grepl(p, x, perl = TRUE)
  out <- rep(TRUE, length(x))
  decided <- !nzchar(x)
  decide <- function(when, value) {
    idx <- !decided & when
    out[idx] <<- value[idx]
    decided[idx] <<- TRUE
  }
  num <- function(from, to) suppressWarnings(as.integer(substr(x, from, to)))
  always <- function(v) rep(v, length(x))
  decide(has("^-?[0-9]{4}-$") | has("^-?[0-9]{4}-[0-9]{2}-$"), always(TRUE))
  decide(has("-:"), always(TRUE))
  range_ok <- has("^[0-9]{4}-[0-9]{2}/[0-9]{4}-[0-9]{2}$") |
    has("^[0-9]{4}-[0-9]{2}-[0-9]{2}/[0-9]{4}-[0-9]{2}-[0-9]{2}")
  decide(has("/"), !range_ok)
  decide(has("^-?[0-9]{4}$"), always(FALSE))
  month <- suppressWarnings(as.integer(substring(x, nchar(x) - 1)))
  decide(has("^-?[0-9]{4}-[0-9]{2}$") & month %in% 1:12, always(FALSE))
  decide(has("^-?[0-9]{4}--$") | has("^-?[0-9]{4}-[0-9]{2}--$"), always(FALSE))
  iso <- has(paste0("^-?[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?([.][0-9]+)?",
                    "([+-][0-9]{2}:?[0-9]{2}|Z)?)?$"))
  bad_time <- has("T(2[4-9]|[3-9][0-9]):") | has(":([6-9][0-9])([^0-9]|$)")
  mo <- num(6, 7)
  dy <- num(9, 10)
  yr <- num(1, 4)
  bad_basic <- (mo > 12 | mo < 1 | dy > 31 | dy < 1) %in% TRUE
  md <- substr(x, 6, 10)
  leap <- (yr %% 4 == 0 & yr %% 100 != 0) | yr %% 400 == 0
  calendar <- ((md == "02-29" & !leap) %in% TRUE) |
    md %in% c("04-31", "06-31", "09-31", "11-31", "02-30", "02-31") | substr(x, 9, 10) == "00"
  decide(iso, bad_time | bad_basic | calendar)
  out
}

#' The study-wide variable length summary CORE 1.0's length rules read
#'
#' A port of `variable_length_summary()` (compiler/sources/lengths.py): one row
#' per variable of every dataset that has records, in dataset order, with the
#' declared length and the length of the variable's longest value as text. A
#' dataset whose declared lengths are not known (a transport file read through
#' haven) cannot take part, and the rule is refused rather than answered
#' without it.
#'
#' @param study The study.
#' @return A data.table: dataset_name, variable_name, variable_label,
#'   variable_data_type, variable_length, variable_order_number,
#'   variable_max_value_length.
#' @noRd
global_length_summary <- function(study) {
  # The same for every rule and dataset of a run, and it reads every value of
  # the study, so it is built once per run (cached_build()).
  cached_build("core1-global-lengths", function() {
    list(data = build_global_length_summary(study), meta = NULL)
  })$data
}

#' @rdname global_length_summary
#' @noRd
build_global_length_summary <- function(study) {
  pieces <- list()
  for (key in names(study$datasets)) {
    ds <- study$datasets[[key]]
    if (is.null(ds$data) || nrow(ds$data) == 0 || ncol(ds$data) == 0) next
    meta <- ds$meta
    if (is.null(meta) || !"length" %in% names(meta) || anyNA(meta$length)) {
      stop("needs every dataset's declared variable lengths, and ", key, " does not record them",
           call. = FALSE)
    }
    vars <- names(ds$data)[!startsWith(names(ds$data), ".")]
    at <- match(vars, meta$variable)
    longest <- vapply(vars, function(v) {
      x <- ds$data[[v]]
      len <- nchar(if (is.numeric(x)) target_text(x) else as.character(x))
      len <- len[!is.na(x)]
      if (length(len)) max(len) else NA_real_
    }, numeric(1))
    pieces[[length(pieces) + 1]] <- data.table::data.table(
      dataset_name = key, variable_name = toupper(vars),
      variable_label = ifelse(is.na(at), "", meta$label[at]),
      variable_data_type = ifelse(is.na(at), "", meta$type[at]),
      variable_length = ifelse(is.na(at), 0, meta$length[at]),
      variable_order_number = ifelse(is.na(at), 0, at),
      variable_max_value_length = unname(longest)
    )
  }
  if (!length(pieces)) {
    return(data.table::data.table(dataset_name = character(0), variable_name = character(0),
                                  variable_length = numeric(0), variable_max_value_length = numeric(0)))
  }
  data.table::rbindlist(pieces)
}

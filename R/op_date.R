# Partial-ISO-8601 date handling, ported from cdisc-org/cdisc-rules-engine's
# check_operators/helpers.py, since SDTM dates are legitimately partial
# (e.g. "2024-03", "2024---15" - the "-" is a literal placeholder for a
# missing component) and as.Date() cannot parse them.
#
# Precision levels, low to high: year(0) < month(1) < day(2) < hour(3) <
# minute(4) < second(5) < microsecond(6).

date_regex <- paste0(
  "(?x)^(",
  "(?<year>-?[0-9]{4}|-)(-{1,2}(?<month>1[0-2]|0[1-9]|-))?",
  "(-{1,2}(?<day>3[01]|0[1-9]|[12][0-9]|-))?",
  "(T(?<hour>2[0-3]|[01][0-9]|-)(:((?<minute>[0-5][0-9]|-))",
  "(:((?<second>[0-5][0-9]|-))?(\\.(?<microsecond>[0-9]+))?)?)?",
  "(?<timezone>Z|[+-](2[0-3]|[01][0-9]):[0-5][0-9])?)?",
  "(/",
  "(?<iyear>-?[0-9]{4}|-)(-{1,2}(?<imonth>1[0-2]|0[1-9]|-))?",
  "(-{1,2}(?<iday>3[01]|0[1-9]|[12][0-9]|-))?",
  "(T(?<ihour>2[0-3]|[01][0-9]|-)(:((?<iminute>[0-5][0-9]|-))",
  "(:((?<isecond>[0-5][0-9]|-))?(\\.(?<imicrosecond>[0-9]+))?)?)?",
  "(?<itimezone>Z|[+-](2[0-3]|[01][0-9]):[0-5][0-9])?)?",
  ")?",
  ")$|",
  "^-{4,8}T(?<tohour>2[0-3]|[01][0-9]|-)(:((?<tominute>[0-5][0-9]|-))",
  "(:((?<tosecond>[0-5][0-9]|-))?(\\.(?<tomicrosecond>[0-9]+))?)?)?",
  "(?<totimezone>Z|[+-](2[0-3]|[01][0-9]):[0-5][0-9])?$"
)

#' Does a date string contain partial/interval uncertainty markers?
#' @param x Character vector of date strings.
#' @return A logical vector.
#' @noRd
has_date_uncertainty <- function(x) {
  grepl("/", x, fixed = TRUE) | grepl("--", x, fixed = TRUE) | grepl("-:", x, fixed = TRUE)
}

# Days in `month` of `year` (Gregorian, leap-year aware).
#' Number of days in a given month (leap-year aware)
#' @param year,month Integer vectors.
#' @return An integer vector.
#' @noRd
days_in_month <- function(year, month) {
  leap <- (year %% 4 == 0 & year %% 100 != 0) | (year %% 400 == 0)
  c(31, ifelse(leap, 29, 28), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]
}

# The regex only checks shape (e.g. "2023-02-30" matches the day pattern
# 3[01]|0[1-9]|[12][0-9] fine). For fully-specified, non-"uncertain" dates,
# the reference engine additionally runs Python's `isoparse`, which DOES
# validate the real calendar (rejects Feb 30) - matched here explicitly,
# since R has no equivalent one-line "does this exist" datetime parser.
# Partial/uncertain dates skip this (there's no fixed calendar to validate
# against a placeholder component).
#' Validate (partial) ISO 8601 date strings, including a real calendar check for full dates
#' @param x Character vector of date strings.
#' @return A logical vector.
#' @noRd
is_valid_date_str <- function(x) {
  valid <- ifelse(is.na(x) | x == "", FALSE, grepl(date_regex, x, perl = TRUE))
  needs_calendar_check <- valid & !has_date_uncertainty(ifelse(is.na(x), "", x))
  if (any(needs_calendar_check)) {
    idx <- which(needs_calendar_check)
    calendar_ok <- vapply(idx, function(i) {
      components <- extract_date_components_one(x[i])
      y <- suppressWarnings(as.integer(components[["year"]]))
      m <- suppressWarnings(as.integer(components[["month"]]))
      d <- suppressWarnings(as.integer(components[["day"]]))
      if (is.na(y) || is.na(m) || is.na(d)) {
        return(TRUE) # nothing to validate at this precision
      }
      d <= days_in_month(y, m)
    }, logical(1))
    valid[idx] <- calendar_ok
  }
  valid
}

date_group_names <- c("year", "month", "day", "hour", "minute", "second", "microsecond", "timezone")

# Extracts the 7 precision components plus a timezone offset for one date
# string. The primary group (year..microsecond) is always used as-is - a
# component missing from the PRIMARY date must stay missing, never borrowed
# from the "/"-interval second date (e.g. "2024-01/2024-06" has month
# precision from its own "01", not day/whatever the second date "06" happens
# to specify; falling back per-component mixed fields from two different
# dates into one). The interval/time-only groups are only used as a whole
# when the primary date didn't match anything at all (a bare interval like
# "/2024-06" with no first date, or a time-only string).
#' Extract the 7 precision components (year..microsecond) plus timezone from one date string
#' @param x A single date string.
#' @return A named character vector, `NA` for missing components.
#' @noRd
extract_date_components_one <- function(x) {
  empty <- stats::setNames(rep(NA_character_, 8), date_group_names)
  if (is.na(x) || x == "" || !grepl(date_regex, x, perl = TRUE)) {
    return(empty)
  }
  m <- regexpr(date_regex, x, perl = TRUE)
  starts <- attr(m, "capture.start")
  lens <- attr(m, "capture.length")
  names_ <- colnames(starts)
  get_group <- function(name) {
    idx <- match(name, names_)
    if (is.na(idx) || starts[1, idx] < 0 || lens[1, idx] == 0) {
      return(NA_character_)
    }
    substr(x, starts[1, idx], starts[1, idx] + lens[1, idx] - 1)
  }
  primary <- c(
    year = get_group("year"), month = get_group("month"), day = get_group("day"),
    hour = get_group("hour"), minute = get_group("minute"), second = get_group("second"),
    microsecond = get_group("microsecond"), timezone = get_group("timezone")
  )
  if (all(is.na(primary))) {
    interval <- c(
      year = get_group("iyear"), month = get_group("imonth"), day = get_group("iday"),
      hour = get_group("ihour"), minute = get_group("iminute"), second = get_group("isecond"),
      microsecond = get_group("imicrosecond"), timezone = get_group("itimezone")
    )
    if (!all(is.na(interval))) {
      primary <- interval
    } else {
      primary <- c(
        year = NA_character_, month = NA_character_, day = NA_character_,
        hour = get_group("tohour"), minute = get_group("tominute"), second = get_group("tosecond"),
        microsecond = get_group("tomicrosecond"), timezone = get_group("totimezone")
      )
    }
  }
  primary[primary %in% c("-", "")] <- NA_character_
  primary
}

# Offset in minutes to SUBTRACT from a timezone-qualified local wall-clock
# time to get true UTC (e.g. "+02:00" means local time is 2 hours ahead of
# UTC, so UTC = local - 120 minutes). `NA`/`"Z"` both mean no adjustment.
#' Parse a date string's timezone component into a UTC offset in minutes
#' @param tz A single timezone string (`NA`, `"Z"`, or `"+HH:MM"`/`"-HH:MM"`), or `NA`.
#' @return A single numeric offset in minutes (0 if absent or `"Z"`).
#' @noRd
tz_offset_minutes <- function(tz) {
  if (is.na(tz) || tz == "" || tz == "Z") {
    return(0)
  }
  sign <- if (startsWith(tz, "-")) -1 else 1
  parts <- strsplit(substring(tz, 2), ":", fixed = TRUE)[[1]]
  sign * (as.numeric(parts[1]) * 60 + as.numeric(parts[2]))
}

date_precision_defaults <- c(year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0, microsecond = 0)

# Precision index (0 = year, ..., 6 = microsecond) of the finest component
# actually present, or NA if the string is invalid or entirely missing.
# Mirrors _date_and_time_precision(): the first missing component (in
# year->microsecond order) caps the precision at the level just before it.
#' Determine the finest precision level actually specified by one date string
#' @param x A single date string.
#' @return An integer precision index (0 = year, ..., 6 = microsecond), or `NA`.
#' @noRd
detect_precision_one <- function(x) {
  if (!is_valid_date_str(x)) {
    return(NA_integer_)
  }
  components <- extract_date_components_one(x)
  if (all(is.na(components))) {
    return(NA_integer_)
  }
  for (i in seq_along(date_group_names)) {
    if (is.na(components[[date_group_names[i]]])) {
      return(i - 2L) # one level before this (0-indexed); i=1 (year missing) -> -1 (no precision at all)
    }
  }
  6L # all 7 components present -> microsecond precision
}

# Parses one date string into a POSIXct, filling missing components with
# their defaults (year 1970, month/day 1, hour/minute/second 0), then - if
# `precision` is given - truncating everything finer than it back to those
# same defaults. This is "truncate to common precision," not "this is the
# real date" - two dates truncated to the same precision are only being
# compared at the resolution both actually specify.
#' Parse one date string to POSIXct, filling/truncating to a given precision
#' @param x A single date string.
#' @param precision Optional precision index to truncate to (see `detect_precision_one()`).
#' @return A `POSIXct` value.
#' @noRd
parse_date_one <- function(x, precision = NA_integer_) {
  components <- extract_date_components_one(x)
  date_fields <- date_group_names[date_group_names != "timezone"]
  values <- vapply(seq_along(date_fields), function(i) {
    nm <- date_fields[i]
    keep <- is.na(precision) || (i - 1L) <= precision
    if (keep && !is.na(components[[nm]])) as.numeric(components[[nm]]) else date_precision_defaults[[nm]]
  }, numeric(1))
  names(values) <- date_fields
  dt <- tryCatch(
    ISOdatetime(
      values[["year"]], values[["month"]], values[["day"]],
      values[["hour"]], values[["minute"]], values[["second"]] + values[["microsecond"]] / 1e6,
      tz = "UTC"
    ),
    error = function(e) as.POSIXct(NA)
  )
  # A timezone offset (e.g. "+02:00") describes the wall-clock time just
  # parsed as LOCAL to that offset, not UTC - without this adjustment, two
  # otherwise-identical instants recorded in different zones would compare
  # as unequal (or in the wrong order) purely because of the offset text.
  # Only applied when hour-or-finer precision is actually being compared -
  # a bare offset with no time component to anchor it is meaningless.
  if (!is.na(dt) && !is.na(components[["timezone"]]) && (is.na(precision) || precision >= 3L)) {
    dt <- dt - tz_offset_minutes(components[["timezone"]]) * 60
  }
  dt
}

# Precision-aware comparison of two (possibly partial) date strings, per the
# reference engine's compare_dates(): both dates are truncated to their
# common (coarser) precision before comparing. equal_to/not_equal_to also
# require matching precision - "2024" and "2024-01-01" are never equal, even
# though truncating both to year-precision gives the same value.
#' Precision-aware comparison of two (possibly partial) date strings
#' @param target,comparator Single date strings.
#' @param op One of `"eq"`, `"ne"`, `"gt"`, `"lt"`, `"ge"`, `"le"`.
#' @return A single logical.
#' @noRd
compare_dates_one <- function(target, comparator, op) {
  if (is.na(target) || is.na(comparator) || target == "" || comparator == "") {
    return(FALSE)
  }
  if (!is_valid_date_str(target) || !is_valid_date_str(comparator)) {
    return(FALSE)
  }
  p1 <- detect_precision_one(target)
  p2 <- detect_precision_one(comparator)
  if (is.na(p1) || is.na(p2) || p1 < 0 || p2 < 0) {
    return(FALSE)
  }
  common <- min(p1, p2)
  t1 <- parse_date_one(target, common)
  t2 <- parse_date_one(comparator, common)

  if (identical(op, "eq")) {
    if (p1 != p2) {
      return(FALSE)
    }
    return(t1 == t2)
  }
  if (identical(op, "ne")) {
    if (p1 != p2) {
      return(TRUE)
    }
    return(t1 != t2)
  }
  switch(op,
    gt = t1 > t2,
    lt = t1 < t2,
    ge = t1 >= t2,
    le = t1 <= t2,
    stop("unknown date comparison op: ", op)
  )
}

#' Build a date-comparison operator from a `compare_dates_one()` op code
#' @param op One of `"eq"`, `"ne"`, `"gt"`, `"lt"`, `"ge"`, `"le"`.
#' @return An operator function of `ctx`.
#' @noRd
date_compare_op <- function(op) {
  guarded_op(function(ctx) {
    vapply(seq_len(ctx$n), function(i) {
      compare_dates_one(ctx$target[i], ctx$value[i], op)
    }, logical(1))
  })
}

# Operators: partial-date-aware comparisons (date_equal_to, date_not_equal_to,
# date_greater_than, date_less_than, date_greater_than_or_equal_to,
# date_less_than_or_equal_to)
register_operator("date_equal_to", date_compare_op("eq"))
register_operator("date_not_equal_to", date_compare_op("ne"))
register_operator("date_greater_than", date_compare_op("gt"))
register_operator("date_less_than", date_compare_op("lt"))
register_operator("date_greater_than_or_equal_to", date_compare_op("ge"))
register_operator("date_less_than_or_equal_to", date_compare_op("le"))

# Operator: is_complete_date - target has at least day-level precision
register_operator("is_complete_date", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  # USE.NAMES = FALSE matters: vapply()'s default names a character-vector
  # input by its OWN VALUES, so without this the result (and everything
  # downstream that combines it via `evaluate_check()`'s `&`/`|`/`!`) would
  # carry the date strings themselves as names on a plain logical vector -
  # cosmetic, but `identical()` (used by the conformance harness and by
  # strict equality tests) treats a named vs. unnamed vector as unequal even
  # when every value matches.
  vapply(ctx$target, function(x) {
    if (is.na(x) || x == "") {
      return(FALSE)
    }
    precision <- detect_precision_one(x)
    !is.na(precision) && precision >= 2L
  }, logical(1), USE.NAMES = FALSE)
})

# Operator: is_incomplete_date - negation of is_complete_date
register_operator("is_incomplete_date", function(ctx) {
  !get_operator("is_complete_date")(ctx)
})

# Operator: invalid_date - target is not a valid (partial) ISO 8601 date
register_operator("invalid_date", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  !is_valid_date_str(ctx$target)
})

# ISO 8601 duration: P[n]Y[n]M[n]D[T[n]H[n]M[n]S] or P[n]W, optionally
# negative when the condition allows it (`negative: true`/absent means only
# a bare "-" prefix variant is accepted too). A comma is only legal INSIDE a
# single component as a decimal separator (e.g. "P1,5Y") - it never separates
# components ("P1Y,2M" is not valid ISO 8601), so there is no `[,]?` between
# the component groups themselves.
duration_regex_positive <- paste0(
  "^P(?!$)(?:(?:(\\d+(?:[.,]\\d*)?Y)?(\\d+(?:[.,]\\d*)?M)?",
  "(\\d+(?:[.,]\\d*)?D)?(T(?=\\d)(?:(\\d+(?:[.,]\\d*)?H)?",
  "(\\d+(?:[.,]\\d*)?M)?(\\d+(?:[.,]\\d*)?S)?)?)?)|(\\d+(?:[.,]\\d*)?W))$"
)
duration_regex_negative <- paste0("^[-]?", substring(duration_regex_positive, 2))

# Operator: invalid_duration - target is not a valid ISO 8601 duration.
# `negative` here is a parameter to THIS operator (may the duration carry a
# leading "-"?), not a generic result-negation flag - see evaluate_condition().
# The upstream engine's own default (when absent) is to ALLOW a negative
# sign; only an EXPLICIT `negative: false` requires a positive-only duration.
register_operator("invalid_duration", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  allow_negative <- !identical(ctx$condition$negative, FALSE)
  pattern <- if (allow_negative) duration_regex_negative else duration_regex_positive
  x <- as.character(ctx$target)
  !grepl(pattern, x, perl = TRUE) | is.na(x) | x == ""
})

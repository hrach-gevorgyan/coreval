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
#
# The obvious one-liner is wrong for vector input, and was wrong here until
# the date operators were vectorised and started passing vectors:
#
#   c(31, ifelse(leap, 29, 28), 31, 30, ...)[month]
#
# `ifelse(leap, 29, 28)` returns ONE ELEMENT PER YEAR, so for n years the
# lookup vector is 11 + n long instead of 12, and every month from March
# onwards indexes the wrong slot. With scalar input it is 12 long and
# correct, which is why per-row calling hid it: "2003-11-31" was rejected
# when checked alone and accepted when checked in a column.
#' Number of days in a given month (leap-year aware)
#' @param year,month Integer vectors.
#' @return An integer vector.
#' @noRd
days_in_month <- function(year, month) {
  leap <- (year %% 4 == 0 & year %% 100 != 0) | (year %% 400 == 0)
  base <- c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)[month]
  ifelse(!is.na(month) & month == 2L & leap, 29L, base)
}

# The regex only checks SHAPE, not real validity - and its shape is looser
# than intended in two ways for a non-"uncertain" string (one with no "/",
# "--", or "-:"): it accepts a calendar-impossible date like "2023-02-30"
# (day pattern 3[01]|0[1-9]|[12][0-9] doesn't know which months have 30
# days), and - because the month and day groups are independently optional -
# it also accepts a component being silently SKIPPED with only a single
# dash (e.g. "2003-20" matches as year="2003" + day="20" with month simply
# absent, since "20" fits the day pattern `[12][0-9]` fine). The reference
# engine avoids both: for a non-uncertain string it runs Python's
# `isoparse` first, which validates the real calendar AND refuses to skip a
# component without an explicit uncertainty marker; only when isoparse
# fails AND the string genuinely contains one of those markers does it fall
# back to the regex-only shape check (confirmed against CORE-000505's real
# fixture: "2003-20" - single dash, no uncertainty marker - is invalid,
# while "2024---15" - the "-" is a literal placeholder for a missing
# month - is valid). Both real-calendar and no-skip-without-uncertainty are
# checked here explicitly, since R has no one-line `isoparse` equivalent.
#' Validate (partial) ISO 8601 date strings, including a real calendar check for full dates
#' @param x Character vector of date strings.
#' @return A logical vector.
#' @noRd
is_valid_date_str <- function(x, comp = NULL) {
  if (length(x) == 0) {
    return(logical(0))
  }
  xx <- ifelse(is.na(x), "", x)
  # Reuse the caller's components when it already has them. The date regex is
  # expensive and was being run up to four times over the same column - once
  # here, once to extract, once to detect precision (which re-validated), and
  # once to parse.
  if (is.null(comp)) {
    comp <- extract_date_components(xx)
  }
  valid <- attr(comp, "matched")
  needs_calendar_check <- valid & !has_date_uncertainty(xx)
  if (any(needs_calendar_check)) {
    idx <- which(needs_calendar_check)
    y <- suppressWarnings(as.integer(comp[idx, "year"]))
    m <- suppressWarnings(as.integer(comp[idx, "month"]))
    d <- suppressWarnings(as.integer(comp[idx, "day"]))

    # Nothing to validate at this precision unless all three are present.
    ok <- rep(TRUE, length(idx))
    # A day without a month is only legal via an explicit uncertainty marker,
    # which this branch has already excluded.
    ok[!is.na(d) & is.na(m)] <- FALSE
    full <- !is.na(y) & !is.na(m) & !is.na(d)
    ok[full] <- d[full] <= days_in_month(y[full], m[full])
    valid[idx] <- ok
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
extract_date_components <- function(x) {
  n <- length(x)
  out <- matrix(
    NA_character_, nrow = n, ncol = 8,
    dimnames = list(NULL, date_group_names)
  )
  if (n == 0) {
    return(out)
  }
  xx <- ifelse(is.na(x), "", x)

  # ONE regexpr call for the whole column, not one per row. regexpr(perl =
  # TRUE) already returns capture.start/capture.length as matrices with a row
  # per element - the per-row version was re-running the regex engine N times
  # to read a matrix it could have got once. This was 52% of a check's total
  # runtime.
  m <- regexpr(date_regex, xx, perl = TRUE)
  starts <- attr(m, "capture.start")
  lens <- attr(m, "capture.length")
  if (is.null(starts)) {
    return(out)
  }
  known <- colnames(starts)

  grab <- function(name) {
    idx <- match(name, known)
    res <- rep(NA_character_, n)
    if (is.na(idx)) {
      return(res)
    }
    st <- starts[, idx]
    ln <- lens[, idx]
    ok <- m != -1L & st > 0L & ln > 0L
    res[ok] <- substr(xx[ok], st[ok], st[ok] + ln[ok] - 1L)
    res
  }
  cols <- function(prefix) {
    vapply(
      c("year", "month", "day", "hour", "minute", "second", "microsecond", "timezone"),
      function(nm) grab(paste0(prefix, nm)),
      character(n)
    )
  }
  as_matrix <- function(v) {
    if (n == 1) matrix(v, nrow = 1, dimnames = list(NULL, date_group_names)) else v
  }

  primary <- as_matrix(cols(""))
  empty_row <- rowSums(!is.na(primary)) == 0

  if (any(empty_row)) {
    interval <- as_matrix(cols("i"))
    has_interval <- empty_row & rowSums(!is.na(interval)) > 0
    primary[has_interval, ] <- interval[has_interval, ]

    # Time-only: year/month/day stay missing by definition.
    time_only <- empty_row & !has_interval
    if (any(time_only)) {
      tm <- as_matrix(cols("to"))
      tm[, c("year", "month", "day")] <- NA_character_
      primary[time_only, ] <- tm[time_only, ]
    }
  }

  primary[primary %in% c("-", "")] <- NA_character_
  colnames(primary) <- date_group_names
  # Whether the regex matched at all, carried along so callers can get
  # validity without running the same regex a second time.
  attr(primary, "matched") <- m != -1L & nzchar(xx)
  primary
}

#' Extract the 7 precision components plus timezone from ONE date string
#' @param x A single date string.
#' @return A named character vector, `NA` for missing components.
#' @noRd
extract_date_components_one <- function(x) {
  stats::setNames(as.vector(extract_date_components(x)[1, ]), date_group_names)
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
detect_precision <- function(x, comp = NULL) {
  n <- length(x)
  out <- rep(NA_integer_, n)
  if (n == 0) {
    return(out)
  }
  if (is.null(comp)) {
    comp <- extract_date_components(ifelse(is.na(x), "", x))
  }
  valid <- is_valid_date_str(x, comp)
  if (!any(valid)) {
    return(out)
  }
  idx <- which(valid)
  missing <- is.na(comp)[idx, , drop = FALSE]

  # The first missing component (in year->microsecond order) caps precision at
  # the level just before it; max.col finds that first TRUE per row in one
  # pass. All eight present, or only the timezone missing, both mean
  # microsecond precision - which is what the original loop arrived at too.
  any_missing <- rowSums(missing) > 0
  first_missing <- max.col(missing, ties.method = "first")
  prec <- ifelse(any_missing, first_missing - 2L, 6L)
  prec[rowSums(!missing) == 0] <- NA_integer_
  out[idx] <- as.integer(prec)
  out
}

#' Precision of ONE date string
#' @param x A single date string.
#' @return An integer precision index (0 = year, ..., 6 = microsecond), or `NA`.
#' @noRd
detect_precision_one <- function(x) {
  detect_precision(x)[1]
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
parse_date <- function(x, precision = NA_integer_, comp = NULL) {
  n <- length(x)
  if (n == 0) {
    return(as.POSIXct(character(0), tz = "UTC"))
  }
  if (is.null(comp)) {
    comp <- extract_date_components(x)
  }
  precision <- rep_len(precision, n)
  date_fields <- date_group_names[date_group_names != "timezone"]

  values <- matrix(0, nrow = n, ncol = length(date_fields), dimnames = list(NULL, date_fields))
  for (i in seq_along(date_fields)) {
    nm <- date_fields[i]
    v <- suppressWarnings(as.numeric(comp[, nm]))
    keep <- (is.na(precision) | (i - 1L) <= precision) & !is.na(v)
    values[, i] <- ifelse(keep, v, date_precision_defaults[[nm]])
  }

  dt <- tryCatch(
    ISOdatetime(
      values[, "year"], values[, "month"], values[, "day"],
      values[, "hour"], values[, "minute"],
      values[, "second"] + values[, "microsecond"] / 1e6,
      tz = "UTC"
    ),
    error = function(e) rep(as.POSIXct(NA, tz = "UTC"), n)
  )

  # A timezone offset (e.g. "+02:00") describes the wall-clock time just
  # parsed as LOCAL to that offset, not UTC - without this adjustment, two
  # otherwise-identical instants recorded in different zones would compare
  # as unequal (or in the wrong order) purely because of the offset text.
  # Only applied when hour-or-finer precision is actually being compared -
  # a bare offset with no time component to anchor it is meaningless.
  tz <- comp[, "timezone"]
  adjust <- !is.na(dt) & !is.na(tz) & (is.na(precision) | precision >= 3L)
  if (any(adjust)) {
    # Timezone-qualified values are rare, so the scalar parser is kept and
    # applied only to the rows that carry one - identical semantics, and no
    # measurable cost at this frequency.
    offsets <- vapply(tz[adjust], tz_offset_minutes, numeric(1), USE.NAMES = FALSE)
    dt[adjust] <- dt[adjust] - offsets * 60
  }
  dt
}

#' Parse ONE date string to POSIXct
#' @param x A single date string.
#' @param precision Optional precision index to truncate to.
#' @return A `POSIXct` value.
#' @noRd
parse_date_one <- function(x, precision = NA_integer_) {
  parse_date(x, precision)[1]
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
compare_dates <- function(target, comparator, op) {
  n <- max(length(target), length(comparator))
  if (n == 0) {
    return(logical(0))
  }
  target <- rep_len(as.character(target), n)
  comparator <- rep_len(as.character(comparator), n)

  # Anything not comparable stays FALSE, matching each early return of the
  # per-row original.
  out <- rep(FALSE, n)
  ok <- !is.na(target) & !is.na(comparator) & nzchar(target) & nzchar(comparator)
  if (!any(ok)) {
    return(out)
  }

  # Parse each side ONCE. Validity, precision and the parsed instant all read
  # from the same components, instead of each re-running the date regex over
  # the whole column.
  ct <- extract_date_components(target)
  cc <- extract_date_components(comparator)

  ok <- ok & is_valid_date_str(target, ct) & is_valid_date_str(comparator, cc)
  if (!any(ok)) {
    return(out)
  }

  p1 <- detect_precision(target, ct)
  p2 <- detect_precision(comparator, cc)
  ok <- ok & !is.na(p1) & !is.na(p2) & p1 >= 0L & p2 >= 0L
  if (!any(ok)) {
    return(out)
  }

  # Both sides truncated to their common (coarser) precision before
  # comparing - two dates are only compared at the resolution both specify.
  common <- pmin(p1, p2)
  t1 <- parse_date(target, common, ct)
  t2 <- parse_date(comparator, common, cc)

  # equal_to/not_equal_to also require matching precision: "2024" and
  # "2024-01-01" are never equal, even though truncating both to year
  # precision gives the same instant.
  res <- switch(op,
    eq = (p1 == p2) & (t1 == t2),
    ne = ifelse(p1 != p2, TRUE, t1 != t2),
    gt = t1 > t2,
    lt = t1 < t2,
    ge = t1 >= t2,
    le = t1 <= t2,
    stop("unknown date comparison op: ", op)
  )
  out[ok] <- res[ok]
  out
}

#' Compare ONE pair of date strings
#' @param target,comparator Single date strings.
#' @param op One of `"eq"`, `"ne"`, `"gt"`, `"lt"`, `"ge"`, `"le"`.
#' @return A single logical.
#' @noRd
compare_dates_one <- function(target, comparator, op) {
  compare_dates(target, comparator, op)[1]
}

#' Build a date-comparison operator from a `compare_dates()` op code
#' @param op One of `"eq"`, `"ne"`, `"gt"`, `"lt"`, `"ge"`, `"le"`.
#' @return An operator function of `ctx`.
#' @noRd
date_compare_op <- function(op) {
  guarded_op(function(ctx) {
    compare_dates(ctx$target, ctx$value, op)
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
  # The result must stay UNNAMED. vapply()'s default named a character-vector
  # input by its own values, so the logical vector carried the date strings as
  # names - cosmetic, but `identical()` (used by the conformance harness and
  # by strict equality tests) treats a named and an unnamed vector as unequal
  # even when every value matches. Vectorised arithmetic keeps it unnamed.
  x <- as.character(ctx$target)
  precision <- detect_precision(x)
  present <- !is.na(x) & nzchar(x)
  unname(present & !is.na(precision) & precision >= 2L)
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

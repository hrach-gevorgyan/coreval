#' Write conformance findings to a file
#'
#' Saves the result of [check_study()] to CSV or Excel, so findings can be
#' shared with people who don't use R, tracked in a spreadsheet, or attached
#' to a data-review document.
#'
#' Both tables are always written, never just the findings. A short findings
#' table can mean clean data, or it can mean many rules were skipped, and
#' those two situations look identical if the skipped table is dropped:
#'
#' * **Excel** (`.xlsx`) - four sheets laid out for a person to read:
#'   - `Problems`: one row per problem, definite errors first, then the ones
#'     touching most records. What is wrong and the rule's number, the
#'     variables it names (or the missing ones), and how many records it
#'     affects, or `whole dataset`.
#'   - `Records`: one row per affected record and problem, in the order of
#'     `Problems`, with `USUBJID`, `SEQ` and the values, such as
#'     `AESTDTC = "2024-02-30"`. A dataset with no subject gives the row
#'     instead.
#'   - `Not checked`: the checks that could not run, grouped by reason, with
#'     what to do about each, then when and how the check was run.
#'   - `Rules`: every rule, and whether it found problems, found none or could
#'     not run. A rule that found nothing appears nowhere else.
#' * **CSV** (`.csv`) - the tables as they are in R, for reading back into a
#'   program. Findings go to `path`; the others go to sibling files with a
#'   suffix before the extension, so `issues.csv` gives
#'   `issues_skipped.csv`, `issues_about.csv` and `issues_summary.csv` (one
#'   row per problem).
#'
#' An existing file at `path`, or at a sibling path, is replaced.
#'
#' In CSV files, a text value that begins with `=`, `+`, `-` or `@` and is not
#' a plain number is written with a leading `'`. Findings quote the submission
#' data, and a spreadsheet program opening the CSV would otherwise run such a
#' value as a formula. Excel files store every value as text and need no such
#' change. CSV files are written as UTF-8 with a byte order mark, which Excel
#' needs to show non-English text correctly.
#'
#' Excel output needs the `writexl` package. It is a `Suggests`, so if it
#' isn't installed you get a clear message telling you to install it or use
#' `.csv` instead, rather than a failure part-way through writing.
#'
#' @section Columns for tracking:
#' Empty columns are added for you to fill in by hand once the file is open:
#' `Status` and `Notes` on `Problems` and `Notes` on `Records` in Excel,
#' `Status`, `Owner` and `Notes` in CSV. They exist so a
#' finding you have looked at and decided not to act on ("expected, see
#' protocol deviation log") can be recorded next to the finding itself, rather
#' than in a separate document nobody reads.
#'
#' @param result A result from [check_dataset()] or [check_study()].
#' @param path Output file path. The extension decides the format: `.xlsx`
#'   for Excel, `.csv` (or anything else) for CSV.
#' @param tracking Add the empty tracking columns. `TRUE` by
#'   default; set `FALSE` for a file you intend to read back into R.
#' @return The paths actually written, invisibly. One element for Excel (a
#'   single workbook). For CSV, one path per file written: the findings, plus
#'   siblings for `skipped`, `about` and `summary`, plus one for `truncated` when any rule
#'   flagged more records than were kept.
#' @examples
#' dir <- tempfile("coreval_study_")
#' dir.create(dir)
#' haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
#' study <- read_study(dir)
#' result <- check_study(study, standard = "SDTMIG")
#'
#' out <- file.path(dir, "findings.csv")
#' written <- write_findings(result, out)
#' basename(written)
#'
#' unlink(dir, recursive = TRUE)
#' @export
write_findings <- function(result, path, tracking = TRUE) {
  # Any list with a `findings` element was taken: an empty one was written up
  # as a complete result with nothing skipped.
  assert_coreval_result(result, "result")
  if (!isTRUE(tracking) && !isFALSE(tracking)) {
    stop("`tracking` must be TRUE or FALSE.", call. = FALSE)
  }
  # Checked here rather than left to fwrite: a non-string reached it and came
  # back as "is.character(file) && length(file) == 1L is not TRUE", and a
  # length-2 path failed even earlier, inside the `if` picking the format.
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be a single file path, ending in '.xlsx' or '.csv'.", call. = FALSE)
  }
  # fwrite's own messages for these ask about permissions and disk space.
  if (dir.exists(path)) {
    stop("`path` is a folder. Give a file name inside it, e.g. ",
         "file.path(\"", path, "\", \"findings.xlsx\").", call. = FALSE)
  }
  if (!dir.exists(dirname(path))) {
    stop("the folder ", dirname(path), " does not exist. Create it first.",
         call. = FALSE)
  }
  findings <- data.table::as.data.table(result$findings)
  skipped <- if (is.null(result$skipped)) {
    data.table::data.table(rule_id = character(0), domain = character(0), reason = character(0))
  } else {
    data.table::as.data.table(result$skipped)
  }

  truncated <- if (is.null(result$truncated)) {
    data.table::data.table()
  } else {
    data.table::as.data.table(result$truncated)
  }
  summary_sheet <- problem_summary(findings, truncated, attr(result, "standard"))

  # Provenance travels WITH the file. A shared spreadsheet outlives the console
  # session that made it: whoever opens it cannot see that a rule matched a
  # million records and only a thousand were kept, or that the result was
  # filtered to one triage level before export. Without this the file reads as
  # the complete picture, which is the same trap `skipped` exists to prevent.
  version_used <- attr(result, "version")
  if (is.null(version_used) || is.na(version_used) || !nzchar(version_used)) {
    version_used <- "none given"
  }
  about <- data.table::data.table(
    item = c(
      "checked on", "checked with", "rules", "standard", "version", "terminology",
      "checks that ran", "checks that could not run",
      "problems", "records affected",
      "is this the whole result?",
      "problems with more records than listed"
    ),
    value = as.character(c(
      format(Sys.time(), "%Y-%m-%d %H:%M"),
      paste("coreval", utils::packageVersion("coreval")),
      rules_version(),
      attr(result, "standard") %||% "not declared",
      attr(result, "version_note") %||% version_used,
      attr(result, "ct_package") %||% "none named",
      attr(result, "checks_run") %||% NA_integer_,
      nrow(skipped),
      nrow(summary_sheet),
      count_records(complete_findings(findings)),
      if (isTRUE(attr(result, "filtered"))) {
        "No: it was filtered before it was saved"
      } else if (nrow(truncated) > 0) {
        "No: some problems have more records than are listed"
      } else {
        "Yes"
      },
      nrow(truncated)
    ))
  )

  if (isTRUE(tracking)) {
    for (col in c("Status", "Owner", "Notes")) {
      findings[[col]] <- rep("", nrow(findings))
      skipped[[col]] <- rep("", nrow(skipped))
      summary_sheet[[col]] <- rep("", nrow(summary_sheet))
    }
  }

  if (grepl("\\.xlsx$", path, ignore.case = TRUE)) {
    if (!writexl_available()) {
      stop(
        "Writing Excel files needs the 'writexl' package.\n",
        "  install.packages(\"writexl\")\n",
        "Or write CSV instead by using a '.csv' path.",
        call. = FALSE
      )
    }
    raw_skipped <- data.table::as.data.table(result$skipped %||% list())
    for (col in c("rule_id", "domain", "reason")) {
      if (!col %in% names(raw_skipped)) {
        data.table::set(raw_skipped, j = col, value = rep(NA_character_, nrow(raw_skipped)))
      }
    }
    raw_skipped$reason[is.na(raw_skipped$reason)] <- ""
    sheets <- workbook_sheets(result, raw_skipped, truncated, about, tracking)
    # Excel holds at most 32,767 characters in a cell, and writexl dies on a
    # longer one with a message about libxlsxwriter. Said plainly instead.
    for (sheet in names(sheets)) {
      too_long <- vapply(sheets[[sheet]], function(col) is.character(col) &&
                           any(nchar(col, "chars") > 32767, na.rm = TRUE), logical(1))
      if (any(too_long)) {
        stop("the ", sheet, " sheet's ", paste(names(sheets[[sheet]])[too_long], collapse = ", "),
             " holds more than 32,767 characters, which Excel cannot store in a cell. ",
             "Write CSV instead by using a '.csv' path.", call. = FALSE)
      }
    }
    writexl::write_xlsx(sheets, path = path)
    return(invisible(path))
  }

  # The suffix goes before the extension of the FILE name only. Matched on the
  # whole path, "john.smith/issues" put the siblings in a folder called
  # "john_skipped.smith".
  sibling <- function(suffix) {
    file <- basename(path)
    p <- sub("(\\.[^.]+)$", paste0("_", suffix, "\\1"), file)
    # No extension to insert before, so append rather than silently
    # overwriting the findings file with another table.
    if (identical(p, file)) p <- paste0(file, "_", suffix)
    file.path(dirname(path), p)
  }
  summary_path <- sibling("summary")
  skipped_path <- sibling("skipped")
  about_path <- sibling("about")

  write_csv <- function(x, file) {
    data.table::fwrite(csv_safe(x), file, bom = TRUE)
  }
  write_csv(findings, path)
  write_csv(summary_sheet, summary_path)
  write_csv(skipped, skipped_path)
  write_csv(about, about_path)
  written <- c(path, skipped_path, about_path, summary_path)

  truncated_path <- sibling("truncated")
  if (nrow(truncated) > 0) {
    write_csv(truncated, truncated_path)
    written <- c(written, truncated_path)
  } else if (file.exists(truncated_path)) {
    # Left from an earlier export to the same path, it would report caps that
    # do not apply to the findings beside it.
    unlink(truncated_path)
  }
  invisible(written)
}

# Findings quote submission data verbatim, so a value like `=HYPERLINK(...)`
# reached the CSV as it stood and a spreadsheet program ran it on opening. A
# leading apostrophe makes it text. Plain numbers are left alone: "-5" is a
# study day, not a formula, and cannot be one.
csv_safe <- function(x) {
  x <- data.table::copy(x)
  number <- "^[-+]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][-+]?[0-9]+)?$"
  for (col in names(x)) {
    v <- x[[col]]
    if (!is.character(v)) next
    risky <- !is.na(v) & grepl("^[-=+@\t\r]", v) & !grepl(number, v)
    if (any(risky)) {
      v[risky] <- paste0("'", v[risky])
      data.table::set(x, j = col, value = v)
    }
  }
  x
}

#' Is writexl installed?
#'
#' Its own function so the test for the message a user without it gets can
#' run everywhere, not only on a machine that lacks the package.
#'
#' @return A single logical.
#' @noRd
writexl_available <- function() {
  requireNamespace("writexl", quietly = TRUE)
}

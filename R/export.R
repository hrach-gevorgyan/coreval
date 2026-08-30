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
#' * **Excel** (`.xlsx`) — one workbook, two sheets: `findings` and `skipped`.
#' * **CSV** (`.csv`) — two files, since CSV has no notion of sheets. Findings
#'   go to `path`; skipped rules go to a sibling file with `_skipped` before
#'   the extension (`issues.csv` gives `issues_skipped.csv`).
#'
#' Excel output needs the `writexl` package. It is a `Suggests`, so if it
#' isn't installed you get a clear message telling you to install it or use
#' `.csv` instead, rather than a failure part-way through writing.
#'
#' @param result A list from [check_study()], with `findings` and `skipped`
#'   elements.
#' @param path Output file path. The extension decides the format: `.xlsx`
#'   for Excel, `.csv` (or anything else) for CSV.
#' @return The paths actually written, invisibly — one element for Excel, two
#'   for CSV.
#' @examples
#' \donttest{
#' dir <- tempfile("coreval_study_")
#' dir.create(dir)
#' haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
#' study <- read_study(dir)
#' result <- check_study(study)
#'
#' out <- file.path(tempdir(), "findings.csv")
#' write_findings(result, out)
#'
#' unlink(dir, recursive = TRUE)
#' }
#' @export
write_findings <- function(result, path) {
  if (!is.list(result) || is.null(result$findings)) {
    stop(
      "`result` must be the list returned by check_study(), ",
      "with a `findings` element.",
      call. = FALSE
    )
  }
  findings <- result$findings
  skipped <- if (is.null(result$skipped)) {
    data.table::data.table(rule_id = character(0), domain = character(0), reason = character(0))
  } else {
    result$skipped
  }

  if (grepl("\\.xlsx$", path, ignore.case = TRUE)) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      stop(
        "Writing Excel files needs the 'writexl' package.\n",
        "  install.packages(\"writexl\")\n",
        "Or write CSV instead by using a '.csv' path.",
        call. = FALSE
      )
    }
    writexl::write_xlsx(
      list(findings = as.data.frame(findings), skipped = as.data.frame(skipped)),
      path = path
    )
    return(invisible(path))
  }

  skipped_path <- sub("(\\.[^.]+)$", "_skipped\\1", path)
  if (identical(skipped_path, path)) {
    # No extension to insert before, so append rather than silently
    # overwriting the findings file with the skipped table.
    skipped_path <- paste0(path, "_skipped")
  }
  data.table::fwrite(findings, path)
  data.table::fwrite(skipped, skipped_path)
  invisible(c(path, skipped_path))
}

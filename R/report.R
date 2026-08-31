# The console report. This is what someone actually reads after running a
# check, so it has to answer their questions in their order: is anything
# wrong, what is it, where is it, and what do I do next.
#
# A row of "CORE-000547 | AE | 2 | AESTDTC | 2024-02-30" answers none of
# those without a rule catalogue open in another window.

#' A rule's one-line statement of what is wrong
#' @param rule A rule record.
#' @return A single string.
#' @noRd
rule_message <- function(rule) {
  msg <- rule$outcome[["Message"]]
  if (is.null(msg) || !nzchar(msg[1])) {
    # Every bundled rule has a Message today; fall back to the fuller rule
    # text rather than printing nothing if that ever stops being true.
    msg <- rule$description
  }
  if (is.null(msg) || length(msg) == 0) "(no description available)" else as.character(msg[1])
}

#' Wrap text to a width, indenting continuation lines
#' @param x A single string.
#' @param width Total line width.
#' @param indent Spaces to put before continuation lines.
#' @return A character vector of lines.
#' @noRd
wrap_lines <- function(x, width, indent) {
  strwrap(x, width = width, prefix = strrep(" ", indent), initial = "")
}

#' Characters used to lay out the report
#'
#' The box-drawing characters have to be escapes: R CMD check refuses
#' non-ASCII bytes in R source. They also degrade to plain ASCII when the
#' console cannot render UTF-8, which beats printing mojibake at someone who
#' just wanted to know what was wrong with their data.
#'
#' @return A list of single-character strings.
#' @noRd
report_glyphs <- function() {
  if (isTRUE(l10n_info()[["UTF-8"]]) || .Platform$OS.type == "windows") {
    list(bar = "\u2500", dot = "\u00b7", arrow = "\u2192", dash = "\u2014")
  } else {
    list(bar = "-", dot = "|", arrow = "->", dash = "-")
  }
}

#' Print a coreval check result as a readable report
#'
#' Shows what is wrong, grouped by problem rather than by row, with the rule's
#' own description of the issue, where it happens, and what to do next.
#'
#' @param x A result from [check_dataset()] or [check_study()].
#' @param n Maximum number of distinct problems to describe (default 10).
#'   The rest are counted, not listed.
#' @param rows Maximum example rows to show per problem (default 3).
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @examples
#' ae <- data.frame(
#'   STUDYID = "S1", DOMAIN = "AE", USUBJID = c("01", "01"),
#'   AESEQ = c(1, 2), AETERM = c("Headache", "Rash"),
#'   AESTDTC = c("2024-01-10", "2024-02-30")
#' )
#' check_dataset(ae)
#' @export
print.coreval_result <- function(x, n = 10, rows = 3, ...) {
  g <- report_glyphs()
  width <- max(60, min(getOption("width", 80), 100))
  f <- x$findings
  skipped <- x$skipped
  ran <- attr(x, "checks_run")
  if (is.null(ran)) ran <- NA_integer_
  doms <- attr(x, "domains")

  rule_line <- function(label, value) {
    cat(label, value, "\n", sep = "")
  }

  # ---- header -------------------------------------------------------------
  title <- if (length(doms) == 1) paste0("coreval ", g$dash, " ", doms) else "coreval"
  bar <- strrep(g$bar, max(0, width - nchar(title) - 4))
  cat("\n", g$bar, g$bar, " ", title, " ", bar, "\n", sep = "")

  n_problems <- length(unique(paste(f$Dataset, f$rule_id)))
  n_records <- if (nrow(f) == 0) 0L else nrow(unique(f[, c("Dataset", "Record")]))

  if (nrow(f) == 0) {
    cat("\nNothing to fix in the ", ran, " checks that ran.\n", sep = "")
  } else {
    cat(
      "\n", n_problems, if (n_problems == 1) " problem" else " problems",
      " across ", n_records, if (n_records == 1) " record" else " records",
      "  (", ran, " checks ran)\n",
      sep = ""
    )
  }

  # ---- the problems -------------------------------------------------------
  if (nrow(f) > 0) {
    key <- paste(f$Dataset, f$rule_id)
    groups <- unique(key)
    # Worst first: the problem touching the most records is the one to look at.
    sizes <- vapply(groups, function(grp) {
      nrow(unique(f[key == grp, c("Dataset", "Record")]))
    }, integer(1))
    groups <- groups[order(-sizes)]

    for (grp in utils::head(groups, n)) {
      sub <- f[key == grp, ]
      dataset <- sub$Dataset[1]
      n_rec <- nrow(unique(sub[, c("Dataset", "Record")]))

      cat("\n")
      for (ln in wrap_lines(sub$issue[1], width - 2, 2)) cat(ln, "\n", sep = "")

      # `$`-prefixed names are coreval's own internal Operations bindings, not
      # columns of the reader's data. Printing "$dataset_variables = STUDYID"
      # is noise; the rule's message already said what was wrong.
      real <- sub[!startsWith(sub$Variable, "$"), ]

      # Name the variables that actually carry a value. A rule often declares
      # several output variables, most of which this dataset simply does not
      # have, and listing those first buries the one that matters.
      present <- unique(real$Variable[real$Value != "Not in dataset"])
      vars <- if (length(present)) present else unique(real$Variable)

      where <- if (length(doms) > 1) paste0(dataset, " ", g$dot, " ") else ""
      cat(
        "  ", where, n_rec, if (n_rec == 1) " record" else " records",
        if (length(vars)) paste0(" ", g$dot, " ", paste(utils::head(vars, 4), collapse = ", ")) else "",
        "\n",
        sep = ""
      )

      if (nrow(real) == 0) {
        # Nothing but internal bindings - the message is the whole finding.
      } else if (all(real$Value == "Not in dataset")) {
        # Listing "row 1 SUBJID = Not in dataset, row 2 SUBJID = Not in
        # dataset..." says the same thing N times. The variable is absent
        # from the dataset; say that once.
        cat("    not in the dataset: ", paste(unique(real$Variable), collapse = ", "), "\n", sep = "")
      } else {
        recs <- unique(real$Record[!is.na(real$Record)])
        shown <- utils::head(recs, rows)
        for (r in shown) {
          cell <- real[!is.na(real$Record) & real$Record == r, ]
          # Prefer a variable holding an actual value: "AESTDTC = 2024-02-30"
          # is worth more than "AGE = Not in dataset" on the same row.
          pick <- which(cell$Value != "Not in dataset")
          cell <- if (length(pick)) cell[pick[1], ] else cell[1, ]
          value <- if (nzchar(cell$Value)) dQuote(cell$Value, FALSE) else "(empty)"
          cat(sprintf("    row %-6s %s = %s\n", r, cell$Variable, value))
        }
        if (length(recs) > length(shown)) {
          cat("    ", length(recs) - length(shown), " more\n", sep = "")
        }
        if (length(recs) == 0) {
          # A dataset-level finding: no row number, just the value.
          v <- real[real$Value != "Not in dataset", ][1, ]
          if (!is.na(v$Variable)) {
            value <- if (nzchar(v$Value)) dQuote(v$Value, FALSE) else "(empty)"
            cat(sprintf("    %s = %s\n", v$Variable, value))
          }
        }
      }
      cat("    ", sub$rule_id[1], "\n", sep = "")
    }

    if (length(groups) > n) {
      cat("\n  ... and ", length(groups) - n, " more problems. ",
        "See result$findings for all of them.\n",
        sep = ""
      )
    }
  }

  # ---- what could not be checked ------------------------------------------
  if (nrow(skipped) > 0) {
    cat("\n", strrep(g$bar, width), "\n", sep = "")
    cat(nrow(skipped), " checks could not run.\n", sep = "")

    need_data <- grepl("was not supplied", skipped$reason)
    if (any(need_data)) {
      wanted <- unique(unlist(regmatches(
        skipped$reason[need_data],
        regexpr("(?<=needs )[A-Z0-9, ]+", skipped$reason[need_data], perl = TRUE)
      )))
      wanted <- unique(trimws(unlist(strsplit(wanted, ","))))
      wanted <- wanted[nzchar(wanted)]
      cat("  ", sum(need_data), " need other datasets (",
        paste(utils::head(sort(wanted), 6), collapse = ", "),
        if (length(wanted) > 6) ", ..." else "", ")\n",
        sep = ""
      )
      cat("     ", g$arrow, " run check_study() on the whole folder to cover these\n", sep = "")
    }
    need_define <- grepl("define.xml", skipped$reason, fixed = TRUE)
    if (any(need_define)) {
      cat("  ", sum(need_define), " need a define.xml\n", sep = "")
    }
    other <- !need_data & !need_define
    if (any(other)) {
      cat("  ", sum(other), " for other reasons, see result$skipped\n", sep = "")
    }
  }

  # ---- what to do next ----------------------------------------------------
  cat("\n")
  if (nrow(f) > 0) {
    cat("Fix what you can, then run this again.\n")
    cat("To track the rest:  write_findings(result, \"issues.xlsx\")\n")
  } else if (nrow(skipped) > 0) {
    cat("Run check_study() on the full folder for the checks that could not run here.\n")
  }
  invisible(x)
}

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

#' Turn a reported set value back into its elements
#'
#' `assemble_findings()` renders a set-valued Operations binding the way the
#' reference engine does, as `['A', 'B']`. That format is kept for fidelity, so
#' the report parses it rather than changing it.
#'
#' @param x A single reported value.
#' @return A character vector of elements; a plain value comes back as itself.
#' @noRd
parse_set_value <- function(x) {
  if (length(x) != 1 || is.na(x) || !grepl("^\\[.*\\]$", x)) {
    return(x)
  }
  inner <- substr(x, 2, nchar(x) - 1)
  if (!nzchar(inner)) {
    return(character(0))
  }
  gsub("^'|'$", "", trimws(strsplit(inner, ",\\s*")[[1]]))
}

#' Make an Operations binding name readable
#' @param x A binding name such as `"$expected_variables"`.
#' @return `"expected variables"`.
#' @noRd
binding_label <- function(x) {
  gsub("_", " ", sub("^\\$", "", x))
}

#' Name the elements a rule wanted that the dataset does not have
#'
#' Several rules compare two sets and then report only "at least one expected
#' variable is missing from dataset", which does not say WHICH. Both sets are
#' right there in the finding, so the difference between them can be shown.
#'
#' This is arithmetic on the two sets the rule itself compared - no per-rule
#' knowledge, and nothing invented. When a finding is not that shape it returns
#' `NULL` and the report simply omits the line.
#'
#' @param sets A named list of parsed set values, keyed by binding name.
#' @return A list with `label` and `missing`, or `NULL`.
#' @noRd
binding_gap <- function(sets) {
  if (length(sets) < 2) {
    return(NULL)
  }
  # Which set says what the dataset HAS is not guessed from rule wording: it
  # is the binding coreval itself populates from the data.
  have_name <- grep("dataset", names(sets), value = TRUE)
  if (length(have_name) != 1) {
    return(NULL)
  }
  want_name <- setdiff(names(sets), have_name)
  if (length(want_name) != 1) {
    return(NULL)
  }
  have <- sets[[have_name]]
  want <- sets[[want_name]]
  if (!is.character(have) || !is.character(want)) {
    return(NULL)
  }
  gap <- setdiff(want, have)
  if (length(gap) == 0) {
    return(NULL)
  }
  list(label = binding_label(want_name), missing = gap)
}

#' Triage levels, most worth your attention first
#'
#' CDISC Open Rules carry NO severity field - checked against the pinned
#' upstream source, where the only `level:` key is an Operations setting for
#' codelist lookups. Pinnacle 21's Notes/Minor/Major/Critical is P21's own
#' layer, not CDISC's, so coreval cannot report a CDISC severity and will not
#' invent one.
#'
#' What it can do is separate the findings that are unambiguously wrong from
#' the ones that may be perfectly fine, which is the distinction that actually
#' governs what you look at first:
#'
#' * `"wrong value"` - the data contains something that breaks the rule: a
#'   month of 13, a value outside its codelist, two variables that contradict
#'   each other. Nothing about your study explains these away.
#' * `"missing required"` - something CDISC marks Required is absent.
#' * `"missing optional"` - something Expected or Permissible is absent, or a
#'   value is simply blank. Often legitimate: a screen-failure subject with no
#'   reference dates, a variable your raw data does not carry yet.
#'
#' This is coreval's own ordering, derived from the findings themselves. It is
#' not a regulatory judgement and does not map onto anyone's severity scale.
#'
#' @format A character vector, highest priority first.
#' @noRd
TRIAGE_LEVELS <- c("wrong value", "missing required", "missing optional")

#' Work out which triage level a rule's findings belong to
#'
#' @param sub Findings for one rule in one dataset.
#' @param rule The rule record, used only to tell Required from Expected when
#'   the finding is about a set of variables rather than a value.
#' @return One of `TRIAGE_LEVELS`.
#' @noRd
finding_triage <- function(sub, rule = NULL) {
  real <- sub[!startsWith(sub$Variable, "$"), ]

  # Something is present and breaks the rule. This is the only class where
  # the data itself is the evidence, so it comes first.
  if (nrow(real) > 0 && any(real$Value != "Not in dataset" & nzchar(real$Value))) {
    return("wrong value")
  }

  # Nothing is present. Whether that matters depends on whether the standard
  # calls it Required - and for the rules that compare variable sets, the
  # binding the rule itself used says so outright.
  binds <- sub$Variable[startsWith(sub$Variable, "$")]
  if (any(grepl("required", binds, ignore.case = TRUE))) {
    return("missing required")
  }
  if (any(grepl("expected|permissible", binds, ignore.case = TRUE))) {
    return("missing optional")
  }
  msg <- if (is.null(rule)) sub$issue[1] else rule_message(rule)
  if (isTRUE(grepl("required", msg, ignore.case = TRUE))) {
    return("missing required")
  }
  "missing optional"
}

#' The conformance-rule ids a CORE rule descends from
#'
#' `CG0665`, `SEND66`, `TIG0699`, `FB0801` - the ids Pinnacle 21 and the
#' published Conformance Rules spreadsheets use. They are how a finding here is
#' matched to a finding there, including to a severity CDISC itself does not
#' publish.
#'
#' @param id A rule id.
#' @return A character vector, possibly empty.
#' @noRd
rule_legacy_ids <- function(id) {
  r <- .coreval_env$data$rules[[id]]
  if (is.null(r) || is.null(r$legacy_ids)) character(0) else r$legacy_ids
}

#' The Implementation Guide sentence a rule enforces
#' @param id A rule id.
#' @return A character vector of citations, possibly empty.
#' @noRd
rule_guidance <- function(id) {
  r <- .coreval_env$data$rules[[id]]
  if (is.null(r) || is.null(r$citations)) character(0) else r$citations
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

#' Print a banner line
#' @param label Text shown in the banner.
#' @param width Total width.
#' @param g Glyph list.
#' @return `invisible(NULL)`.
#' @noRd
report_banner <- function(label, width, g) {
  bar <- strrep(g$bar, max(0, width - nchar(label) - 4))
  cat("\n", g$bar, g$bar, " ", label, " ", bar, "\n", sep = "")
}

#' Render the variables and values of one finding's record
#' @param cell Findings rows for a single record.
#' @return A single string such as `AGE = "47", AGEU = (empty)`.
#' @noRd
describe_cells <- function(cell) {
  # Show every variable on the row that holds a real value, not just the
  # first. Several rules report a COMPARISON - a variable's label against the
  # label the IG expects - and showing one side of it tells the reader
  # nothing. Variables reported as absent are dropped: when
  # `AESTDTC = 2024-02-30` is the finding, `AGE = Not in dataset` beside it is
  # noise.
  # Real values first, then blanks, then absent variables. The value that
  # actually breaks the rule is the one worth showing, and a valid-looking
  # neighbour shown in its place is what makes a report untrustworthy.
  weight <- ifelse(
    cell$Value == "Not in dataset", 3L,
    ifelse(nzchar(cell$Value), 1L, 2L)
  )
  cell <- cell[order(weight), ]
  pick <- which(cell$Value != "Not in dataset")
  if (length(pick) == 0) pick <- 1L
  cell <- cell[utils::head(pick, 3), ]
  paste(
    sprintf(
      "%s = %s", cell$Variable,
      ifelse(nzchar(cell$Value), dQuote(cell$Value, FALSE), "(empty)")
    ),
    collapse = ", "
  )
}

#' Describe each distinct problem in a set of findings
#'
#' Split out of [print.coreval_result()] so a whole-study report can call it
#' once per dataset and a single-dataset report once overall, without the two
#' drifting into describing the same finding differently.
#'
#' @param f Findings to describe.
#' @param n Maximum problems to describe.
#' @param rows Maximum example records per problem.
#' @param width Line width.
#' @param g Glyph list.
#' @param truncated The result's `truncated` table, so a capped count can be
#'   reported as the true one.
#' @param guidance Print the Implementation Guide sentence each rule enforces.
#' @return `invisible(NULL)`.
#' @noRd
describe_problems <- function(f, n, rows, width, g, truncated = NULL,
                              guidance = FALSE) {
  key <- paste(f$Dataset, f$rule_id)
  groups <- unique(key)
  # Triage first, record count second. Ordering purely by "how many records"
  # puts a variable that is simply absent - which may be entirely legitimate
  # for this study - above a date with a month of 13, which never is.
  rank <- vapply(groups, function(grp) {
    as.integer(match(f$triage[key == grp][1], TRIAGE_LEVELS))
  }, integer(1))
  rank[is.na(rank)] <- length(TRIAGE_LEVELS) + 1L
  sizes <- vapply(groups, function(grp) {
    nrow(unique(f[key == grp, c("Dataset", "Record")]))
  }, integer(1))
  groups <- groups[order(rank, -sizes)]

  for (grp in utils::head(groups, n)) {
    sub <- f[key == grp, ]
    n_rec <- nrow(unique(sub[, c("Dataset", "Record")]))

    cat("\n[", sub$triage[1], "]\n", sep = "")
    for (ln in wrap_lines(sub$issue[1], width - 2, 2)) cat(ln, "\n", sep = "")

    # `$`-prefixed names are coreval's own internal Operations bindings, not
    # columns of anyone's data.
    real <- sub[!startsWith(sub$Variable, "$"), ]

    # Name the variables that actually carry a value. A rule often declares
    # several output variables, most of which this dataset simply does not
    # have, and listing those first buries the one that matters.
    present <- unique(real$Variable[real$Value != "Not in dataset"])
    vars <- if (length(present)) present else unique(real$Variable)

    # When a rule flagged more records than were kept, say the TRUE number.
    # Printing the kept count alone would under-report a problem affecting
    # every row of the dataset as though it affected a thousand.
    total_rec <- n_rec
    if (!is.null(truncated) && nrow(truncated) > 0) {
      hit <- truncated$rule_id == sub$rule_id[1] & truncated$domain == sub$Dataset[1]
      if (any(hit)) total_rec <- truncated$records_found[which(hit)[1]]
    }
    cat(
      "  ", total_rec, if (total_rec == 1) " record" else " records",
      if (total_rec > n_rec) paste0(" (first ", n_rec, " kept)") else "",
      if (length(vars)) paste0(" ", g$dot, " ", paste(utils::head(vars, 4), collapse = ", ")) else "",
      "\n",
      sep = ""
    )

    if (nrow(real) == 0) {
      # Only internal bindings. The rule compared two sets and its message
      # says one of them is short without saying which - so name the gap.
      binds <- sub[startsWith(sub$Variable, "$"), ]
      sets <- lapply(binds$Value, parse_set_value)
      names(sets) <- binds$Variable
      gap <- binding_gap(sets)
      if (!is.null(gap)) {
        cat("    missing ", gap$label, ": ",
          paste(utils::head(gap$missing, 8), collapse = ", "),
          if (length(gap$missing) > 8) ", ..." else "", "\n",
          sep = ""
        )
      }
    } else if (all(real$Value == "Not in dataset")) {
      # Repeating "row 1 SUBJID = Not in dataset, row 2 SUBJID = Not in
      # dataset..." says the same thing N times. The variable is absent from
      # the dataset; say that once.
      cat("    not in the dataset: ", paste(unique(real$Variable), collapse = ", "), "\n", sep = "")
    } else {
      recs <- unique(real$Record[!is.na(real$Record)])
      if (length(recs) == 0) {
        # A dataset-level finding: no row number to point at, just values.
        cat("    ", describe_cells(real), "\n", sep = "")
      } else {
        # Records holding an actual offending value first. Showing "row 3
        # RFSTDTC = (empty)" above "row 4 RFSTDTC = 2024-13-01" leads with the
        # one that might be perfectly legitimate and buries the one that
        # certainly is not.
        rec_weight <- vapply(recs, function(r) {
          vals <- real$Value[!is.na(real$Record) & real$Record == r]
          if (any(nzchar(vals) & vals != "Not in dataset")) 1L else 2L
        }, integer(1))
        recs <- recs[order(rec_weight, recs)]
        shown <- utils::head(recs, rows)
        for (r in shown) {
          text <- describe_cells(real[!is.na(real$Record) & real$Record == r, ])
          prefix <- sprintf("    row %-5s ", r)
          for (ln in wrap_lines(text, width - nchar(prefix), nchar(prefix))) {
            cat(prefix, ln, "\n", sep = "")
            prefix <- strrep(" ", nchar(prefix)) # continuations line up
          }
        }
        if (length(recs) > length(shown)) {
          cat("    ", length(recs) - length(shown), " more\n", sep = "")
        }
      }
    }
    # The legacy conformance-rule ids alongside the CORE id: CG0665, SEND66,
    # TIG0699. Those are what Pinnacle 21 and the published Conformance Rules
    # spreadsheets use, so they are how a finding here is matched to a finding
    # there - including to a severity CDISC itself does not publish.
    rid <- sub$rule_id[1]
    legacy <- rule_legacy_ids(rid)
    cat("    ", rid,
      if (length(legacy)) {
        paste0(
          "  ", g$dot, " also ", paste(utils::head(legacy, 3), collapse = ", "),
          if (length(legacy) > 3) ", ..." else ""
        )
      },
      "\n",
      sep = ""
    )
    if (isTRUE(guidance)) {
      cited <- rule_guidance(rid)
      if (length(cited)) {
        for (ln in wrap_lines(cited[1], width - 6, 6)) cat("    ", ln, "\n", sep = "")
      }
    }
  }

  if (length(groups) > n) {
    cat("\n  ... and ", length(groups) - n, " more here. ",
      "See result$findings for all of them.\n",
      sep = ""
    )
  }
  invisible(NULL)
}

#' Summarise what could not be checked, grouped by why
#' @param skipped The skipped table.
#' @param width Line width.
#' @param g Glyph list.
#' @return `invisible(NULL)`.
#' @noRd
describe_skipped <- function(skipped, width, g) {
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
  invisible(NULL)
}

#' Print a coreval check result as a readable report
#'
#' Describes each problem in the rule's own words, worst first, with the rows
#' and values that caused it. A whole-study result is grouped by dataset, with
#' a summary first, so you can see where the trouble is before reading detail.
#'
#' @param x A result from [check_dataset()] or [check_study()].
#' @param n Maximum problems to describe - per dataset, for a study result.
#'   The rest are counted, not listed. Default 10.
#' @param rows Maximum example records to show per problem. Default 3.
#' @param guidance Also print the sentence from the Implementation Guide that
#'   each rule enforces - the "why" behind it. Off by default: it roughly
#'   doubles the length of the report.
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
print.coreval_result <- function(x, n = 10, rows = 3, guidance = FALSE, ...) {
  g <- report_glyphs()
  width <- max(60, min(getOption("width", 80), 100))
  f <- x$findings
  skipped <- x$skipped
  ran <- attr(x, "checks_run")
  if (is.null(ran)) ran <- NA_integer_
  doms <- attr(x, "domains")
  one_dataset <- length(doms) == 1

  report_banner(
    if (one_dataset) paste0("coreval ", g$dash, " ", doms) else "coreval",
    width, g
  )

  if (isTRUE(attr(x, "filtered"))) {
    cat("
(filtered - this is a subset of the full result)
")
  }

  n_problems <- length(unique(paste(f$Dataset, f$rule_id)))
  n_records <- if (nrow(f) == 0) 0L else nrow(unique(f[, c("Dataset", "Record")]))

  if (nrow(f) == 0 && isTRUE(attr(x, "filtered"))) {
    # "Nothing to fix" would be a lie here: findings were filtered away, not
    # absent. The data is no cleaner than it was before the filter.
    cat("\nNo findings match this filter.\n")
  } else if (nrow(f) == 0) {
    cat("\nNothing to fix in the ", ran, " checks that ran.\n", sep = "")
  } else {
    cat(
      "\n", n_problems, if (n_problems == 1) " problem" else " problems",
      " across ", n_records, if (n_records == 1) " record" else " records",
      if (one_dataset) "" else paste0(" in ", length(unique(f$Dataset)), " datasets"),
      "  (", ran, " checks ran)\n",
      sep = ""
    )

    # What kind of problems, before any detail. CDISC ships no severity, so
    # this is coreval's own split - and the note says as much, because a
    # reader who mistakes it for a regulatory grading would draw the wrong
    # conclusion from "missing optional".
    per_problem <- unique(f[, c("Dataset", "rule_id", "triage")])
    counts <- table(factor(per_problem$triage, levels = TRIAGE_LEVELS))
    cat("\n")
    for (lvl in TRIAGE_LEVELS) {
      if (counts[[lvl]] == 0) next
      hint <- switch(lvl,
        "wrong value" = "the data breaks the rule - start here",
        "missing required" = "the standard requires it",
        "missing optional" = "often legitimate: not collected, screen failure, ..."
      )
      cat(sprintf("  %-17s %3d   %s\n", lvl, counts[[lvl]], hint))
    }
  }

  if (nrow(f) > 0 && one_dataset) {
    describe_problems(f, n, rows, width, g, x$truncated, guidance)
  } else if (nrow(f) > 0) {
    # A study produces far too many findings to read as one flat list, and
    # "which dataset is worst" is the first thing anyone wants to know. So:
    # summarise, then take each dataset in turn, worst first.
    by_dataset <- unique(f$Dataset)
    counts <- vapply(by_dataset, function(d) {
      length(unique(f$rule_id[f$Dataset == d]))
    }, integer(1))
    recs <- vapply(by_dataset, function(d) {
      nrow(unique(f[f$Dataset == d, c("Dataset", "Record")]))
    }, integer(1))
    ord <- order(-counts)
    by_dataset <- by_dataset[ord]
    counts <- counts[ord]
    recs <- recs[ord]

    cat("\n")
    for (i in seq_along(by_dataset)) {
      cat(sprintf(
        "  %-10s %3d %-9s %3d %s\n",
        by_dataset[i], counts[i],
        if (counts[i] == 1) "problem" else "problems",
        recs[i], if (recs[i] == 1) "record" else "records"
      ))
    }

    for (d in by_dataset) {
      report_banner(d, width, g)
      describe_problems(f[f$Dataset == d, ], n, rows, width, g, x$truncated, guidance)
    }
  }

  if (nrow(skipped) > 0) {
    describe_skipped(skipped, width, g)
  }

  # Without a declared standard every standard's rules ran, so an SDTM study
  # was also measured against SENDIG rules. Say so: the alternative is
  # silently reporting SEND findings on SDTM data, which is how one defect
  # came to be reported twice.
  if (is.null(attr(x, "standard"))) {
    cat("\nNo standard declared, so rules from every standard ran.\n")
    cat("  Narrow with  standard = \"SDTMIG\"  (or \"SENDIG\", \"TIG\", ...)\n")
  } else {
    # Never silent about what scoping cost. CDISC's own coverage is uneven -
    # the general "--DTC must be valid ISO 8601" rule is published for SENDIG
    # and TIG but NOT for SDTMIG, whose only equivalents are TSVAL-specific or
    # deprecated - so narrowing can genuinely stop a real defect being
    # reported. The reader has to be able to see that happened.
    dropped <- attr(x, "excluded_by_standard")
    if (!is.null(dropped) && dropped > 0) {
      cat("\nScoped to ", attr(x, "standard"), ": ", dropped,
        " rules belonging to other standards were not run.\n",
        sep = ""
      )
    }
  }

  cat("\n")
  if (nrow(f) > 0) {
    cat("Fix what you can, then run this again.\n")
    cat("To track the rest:  write_findings(result, \"issues.xlsx\")\n")
  } else if (nrow(skipped) > 0) {
    cat("Run check_study() on the full folder for the checks that could not run here.\n")
  }
  invisible(x)
}

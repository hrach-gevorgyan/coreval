# The Excel workbook write_findings() writes, laid out for the person who opens
# it. That is often a reviewer who never saw the console report, so four short
# sheets say what the report says: the problems, the records behind them, what
# could not be checked, and what happened to every rule. The CSV files keep the
# raw tables, for reading back into a program.

# Groups of findings and the order they are shown in: (Dataset, rule), definite
# errors first, then the problem touching most records. Problems and Records
# both follow it, so a problem's records sit together in the order Problems
# lists them.
#' One row per problem
#' @param findings The findings table.
#' @param truncated The result's `truncated` table, for the true record count
#'   of a capped rule.
#' @param standard The declared standard, so only its rule numbers are named.
#' @return A data.table, one row per (Dataset, rule), in the order shown:
#'   `triage`, `Dataset`, `rule_id`, `issue`, `details`, `records` (`NA` when
#'   the problem is not about records), `affects` (the same in words) and
#'   `also`.
#' @noRd
problem_summary <- function(findings, truncated = NULL, standard = NULL) {
  out <- data.table::data.table(
    triage = character(0), Dataset = character(0), rule_id = character(0),
    issue = character(0), details = character(0), records = integer(0),
    affects = character(0), also = character(0)
  )
  findings <- complete_findings(findings)
  if (nrow(findings) == 0) {
    return(out)
  }
  key <- paste(findings$Dataset, findings$rule_id)
  rows <- lapply(unique(key), function(grp) {
    sub <- findings[key == grp, ]
    id <- sub$rule_id[1]
    n_rec <- count_records(sub)
    kept <- n_rec
    if (!is.null(truncated) && nrow(truncated) > 0) {
      hit <- truncated$rule_id == id & truncated$domain %in% c(sub$Dataset[1], "STUDY")
      if (any(hit)) n_rec <- max(n_rec, truncated$records_found[which(hit)[1]])
    }
    n_vars <- if (n_rec == 0 && rule_rows_are_variables(id)) {
      length(unique(sub$Record[!is.na(sub$Record)]))
    } else {
      0L
    }
    affects <- if (n_rec > 0) {
      paste0(n_rec, if (n_rec > kept) paste0(" (first ", kept, " listed)") else "")
    } else if (n_vars > 0) {
      paste(n_vars, if (n_vars == 1) "variable" else "variables")
    } else if (identical(sub$Dataset[1], "STUDY")) {
      "whole study"
    } else {
      "whole dataset"
    }
    data.table::data.table(
      triage = sub$triage[1], Dataset = sub$Dataset[1], rule_id = id,
      issue = sub$issue[1], details = problem_details(sub),
      records = if (n_rec > 0) as.integer(n_rec) else NA_integer_,
      affects = affects,
      also = paste(rule_legacy_ids(id, standard), collapse = ", ")
    )
  })
  out <- data.table::rbindlist(rows)
  rank <- match(out$triage, TRIAGE_LEVELS)
  rank[is.na(rank)] <- length(TRIAGE_LEVELS) + 1L
  ord <- order(rank, -data.table::fcoalesce(out$records, 0L))
  out[ord]
}

#' A findings table with every column the workbook reads
#'
#' A narrowed or hand-made table may lack one; it reads as blank.
#'
#' @param findings A findings table.
#' @return A copy with `Record`, `USUBJID`, `SEQ`, `Variable`, `Value`,
#'   `issue` and `triage`.
#' @noRd
complete_findings <- function(findings) {
  findings <- data.table::as.data.table(findings)
  if (nrow(findings) == 0 || !all(c("Dataset", "rule_id") %in% names(findings))) {
    return(findings[0])
  }
  findings <- data.table::copy(findings)
  fill <- list(Record = NA_integer_, USUBJID = NA_character_, SEQ = NA_real_,
               Variable = "", Value = "", issue = NA_character_, triage = NA_character_)
  for (col in names(fill)) {
    if (!col %in% names(findings)) data.table::set(findings, j = col, value = fill[[col]])
  }
  findings$Variable[is.na(findings$Variable)] <- ""
  findings$Value[is.na(findings$Value)] <- ""
  findings
}

#' What a problem is about, in a few words
#'
#' The names a rule's message leaves out: which required variables are
#' missing, which variable is absent, or the variables whose values break it.
#'
#' @param sub One problem's findings.
#' @return A single string.
#' @noRd
problem_details <- function(sub) {
  # A rule over variable metadata reports the variable as a value of its own
  # table, under that table's column name, which means nothing to a reader.
  named <- sub$Value[sub$Variable %in% c("variable_name", "define_variable_name") &
                       nzchar(sub$Value) & sub$Value != "Not in dataset"]
  binds <- sub[startsWith(sub$Variable, "$"), ]
  if (nrow(binds) > 0) {
    first <- binds[is.na(binds$Record) | binds$Record == binds$Record[1], ]
    gap <- binding_gap_of(first)
    if (!is.null(gap)) {
      return(paste(gap$missing, collapse = ", "))
    }
    # One variable's numbers would read as the whole problem's.
    if (length(named) == 0) {
      return(binding_text(first))
    }
  }
  if (length(named) > 0) {
    return(paste(unique(named), collapse = ", "))
  }
  real <- sub[!startsWith(sub$Variable, "$"), ]
  absent <- real$Value == "Not in dataset"
  if (nrow(real) > 0 && all(absent)) {
    return(paste(unique(real$Variable), collapse = ", "))
  }
  paste(unique(real$Variable[!absent]), collapse = ", ")
}

#' The difference between a rule's own sets of names
#' @param binds Findings rows whose `Variable` is a `$` binding.
#' @return See [binding_gap()].
#' @noRd
binding_gap_of <- function(binds) {
  sets <- lapply(binds$Value, parse_set_value)
  names(sets) <- binds$Variable
  binding_gap(sets)
}

#' A rule's own sets of names, in words
#' @param binds Findings rows whose `Variable` is a `$` binding.
#' @return `"missing required variables: SITEID, COUNTRY"`, or each set named
#'   in turn when they are not a want-and-have pair.
#' @noRd
binding_text <- function(binds) {
  gap <- binding_gap_of(binds)
  if (!is.null(gap)) {
    return(paste0("missing ", gap$label, ": ", paste(gap$missing, collapse = ", ")))
  }
  sets <- lapply(binds$Value, parse_set_value)
  paste(paste0(binding_label(binds$Variable), ": ",
               vapply(sets, paste, character(1), collapse = ", ")),
        collapse = "; ")
}

#' A variable's name as a reader sees it
#'
#' Columns of the data are upper case and stay as they are. Lower-case names
#' are coreval's own metadata columns, such as `variable_length`.
#'
#' @param x Variable names.
#' @return `x`, with those names in words.
#' @noRd
variable_words <- function(x) {
  own <- grepl("^[a-z]", x)
  x[own] <- gsub("_", " ", x[own], fixed = TRUE)
  x
}

#' One record's values, as a person reads them
#' @param cells One record's findings rows for one problem.
#' @param where `"dataset"` or `"study"`, for a finding naming only what is
#'   absent.
#' @return `AESTDTC = "2024-02-30"; AETRTEM = (not in dataset)`: values that
#'   are there first, then blanks, then variables the dataset lacks. A finding
#'   that only names what is absent reads `not in the dataset: EPOCH`.
#' @noRd
cells_text <- function(cells, where = "dataset") {
  binds <- cells[startsWith(cells$Variable, "$"), ]
  real <- cells[!startsWith(cells$Variable, "$"), ]
  if (nrow(binds) == 0 && nrow(real) > 0 && all(real$Value == "Not in dataset")) {
    return(paste0("not in the ", where, ": ", paste(unique(real$Variable), collapse = ", ")))
  }
  parts <- character(0)
  if (nrow(real) > 0) {
    weight <- ifelse(real$Value == "Not in dataset", 3L, ifelse(nzchar(real$Value), 1L, 2L))
    real <- real[order(weight), ]
    shown <- ifelse(real$Value == "Not in dataset", "(not in dataset)",
                    ifelse(nzchar(real$Value), paste0("\"", real$Value, "\""), "(empty)"))
    parts <- paste(variable_words(real$Variable), "=", shown)
  }
  if (nrow(binds) > 0) {
    parts <- c(parts, binding_text(binds))
  }
  paste(parts, collapse = "; ")
}

#' One row per affected record and problem, in the order of Problems
#'
#' Only findings that point at a record of the data. A problem about a dataset
#' as a whole, or about its variables, has no record to name and is on Problems
#' alone.
#'
#' @param findings The findings table.
#' @param problems [problem_summary()] of the same findings.
#' @return A data.table.
#' @noRd
record_rows <- function(findings, problems) {
  findings <- complete_findings(findings)
  if (nrow(findings) > 0) {
    findings <- findings[!is.na(findings$Record) & !rule_rows_are_metadata(findings$rule_id)]
  }
  if (nrow(findings) == 0) {
    return(data.table::data.table(
      Dataset = character(0), Record = integer(0), USUBJID = character(0),
      SEQ = numeric(0), issue = character(0), values = character(0), rule_id = character(0)
    ))
  }
  key <- paste(findings$Dataset, findings$rule_id, findings$Record, sep = "\x1f")
  grp <- match(key, unique(key))
  first <- match(seq_len(max(grp)), grp)
  out <- findings[first, c("Dataset", "Record", "USUBJID", "SEQ", "issue", "rule_id")]
  # cells_text() for every row at once. Called once per record it took as long
  # as the check itself on CDISC's pilot study (24 000 records).
  var <- findings$Variable
  val <- findings$Value
  absent <- val == "Not in dataset"
  weight <- ifelse(absent, 3L, ifelse(nzchar(val), 1L, 2L))
  piece <- paste(variable_words(var), "=", ifelse(absent, "(not in dataset)",
                                  ifelse(nzchar(val), paste0("\"", val, "\""), "(empty)")))
  o <- order(grp, weight, seq_along(grp))
  out$values <- vapply(split(piece[o], grp[o]), paste, character(1), collapse = "; ", USE.NAMES = FALSE)
  where <- ifelse(out$Dataset == "STUDY", "study", "dataset")
  only_absent <- vapply(split(absent, grp), all, logical(1), USE.NAMES = FALSE)
  if (any(only_absent)) {
    names_absent <- vapply(split(var, grp), function(v) paste(unique(v), collapse = ", "),
                           character(1), USE.NAMES = FALSE)
    out$values[only_absent] <- paste0("not in the ", where[only_absent], ": ", names_absent[only_absent])
  }
  # A rule's own sets of names are few and need binding_gap(); those records
  # take the slow path.
  with_sets <- unique(grp[startsWith(var, "$")])
  for (k in with_sets) {
    out$values[k] <- cells_text(findings[grp == k, c("Variable", "Value")], where[k])
  }
  # The sheet has no row-number column, because subject and sequence find a
  # record. A dataset with no subject (TS, TA) has nothing else to find it by.
  nobody <- is.na(out$USUBJID) | !nzchar(out$USUBJID)
  out$values[nobody] <- paste0("row ", out$Record[nobody], ": ", out$values[nobody])
  problem <- match(paste(out$Dataset, out$rule_id), paste(problems$Dataset, problems$rule_id))
  out <- out[order(problem, out$Record, first)]
  out[, c("Dataset", "Record", "USUBJID", "SEQ", "issue", "values", "rule_id")]
}

#' What could not be checked, then how the check was run
#' @param skipped The result's `skipped` table.
#' @param about The provenance table.
#' @return A data frame of text: one row per kind of reason, a blank row, then
#'   the facts about the run.
#' @noRd
not_checked_sheet <- function(skipped, about) {
  top <- data.table::data.table(a = character(0), b = character(0), c = character(0))
  if (nrow(skipped) > 0) {
    group <- skip_group(skipped$reason)
    text <- skip_group_text()
    text$what[text$group == "other"] <- "other reasons"
    # `group` is also a column of `text`, so it is subset with a plain vector.
    present <- text$group %in% unique(group)
    text <- text[present]
    n <- vapply(text$group, function(k) sum(group == k), integer(1))
    named <- vapply(text$group, function(k) {
      if (k %in% c("supplied", "absent")) skip_datasets_named(skipped$reason[group == k], Inf, " (", ")") else ""
    }, character(1))
    top <- data.table::data.table(a = paste0(text$what, named), b = as.character(n), c = text$todo)
    top <- top[order(-n)]
  }
  shown <- c("checked on", "checked with", "rules", "standard", "version", "terminology",
             "checks that ran", "is this the whole result?",
             "problems with more records than listed")
  facts <- about[about$item %in% shown]
  facts <- data.table::data.table(
    a = paste0(toupper(substr(facts$item, 1, 1)), substring(facts$item, 2)),
    b = facts$value, c = ""
  )
  blank <- data.table::data.table(a = "", b = "", c = "")
  out <- as.data.frame(data.table::rbindlist(list(top, blank, facts)))
  names(out) <- c("Why these checks could not run", "Checks", "What to do")
  out
}

#' What happened to every rule, one row each
#'
#' The only place a rule that ran and found nothing is listed, which is what
#' tells "clean" from "never checked".
#'
#' @param findings The findings table.
#' @param skipped The result's `skipped` table.
#' @param ran The result's `ran` attribute: a `rule_id`, `domain` pair per
#'   check that ran, or `NULL`.
#' @param filtered Was the result filtered? A rule whose findings were filtered
#'   out did not find nothing, and must not read as if it did.
#' @return A data frame.
#' @noRd
rules_sheet <- function(findings, skipped, ran, filtered) {
  ran <- ran %||% data.table::data.table(rule_id = character(0), domain = character(0))
  found <- if (nrow(findings) > 0 && "rule_id" %in% names(findings)) unique(findings$rule_id) else character(0)
  ids <- sort(unique(c(ran$rule_id, skipped$rule_id, found)))
  ran_on <- split(ran$domain, ran$rule_id)
  skip_rows <- split(seq_len(nrow(skipped)), skipped$rule_id)
  rows <- lapply(ids, function(id) {
    sets <- ran_on[[id]]
    skips <- skipped[skip_rows[[id]] %||% integer(0)]
    reason <- sub("^evaluation failed: ", "", skips$reason)
    result <- if (id %in% found) {
      "problems found"
    } else if (length(sets) > 0) {
      if (isTRUE(filtered)) "ran, filtered out of this file" else "no problems"
    } else {
      "could not run"
    }
    datasets <- if (length(sets) > 0) sets else skips$domain
    if (length(datasets) == 0 && id %in% found) {
      datasets <- findings$Dataset[findings$rule_id == id]
    }
    # Where it ran on some datasets only, say which the reason belongs to.
    why <- if (length(sets) > 0 && nrow(skips) > 0) {
      paste(vapply(unique(reason), function(r) {
        paste0(paste(sort(unique(skips$domain[reason == r])), collapse = ", "), ": ", r)
      }, character(1)), collapse = "; ")
    } else {
      paste(unique(reason), collapse = "; ")
    }
    list(id, rule_sentence(id), result, paste(sort(unique(datasets)), collapse = ", "), why)
  })
  out <- data.table::rbindlist(rows)
  if (nrow(out) == 0) {
    out <- data.table::data.table(a = character(0), b = character(0), c = character(0),
                                  d = character(0), e = character(0))
  }
  out <- as.data.frame(out)
  names(out) <- c("Rule", "What it checks", "Result", "Datasets", "Why not run")
  out
}

#' A rule's sentence, from the rule set in force or the other
#' @param id A rule id.
#' @return A single string.
#' @noRd
rule_sentence <- function(id) {
  sets <- .coreval_env$rule_sets
  rule_message(.coreval_env$data$rules[[id]] %||% sets$sdtm[[id]] %||% sets$cdisc[[id]])
}

#' The sheets of the Excel workbook
#' @param result The check result.
#' @param skipped Its `skipped` table, with `rule_id`, `domain` and `reason`.
#' @param truncated Its `truncated` table.
#' @param about The provenance table.
#' @param tracking Add the empty Status and Notes columns.
#' @return A named list of data frames, one per sheet, in order.
#' @noRd
workbook_sheets <- function(result, skipped, truncated, about, tracking) {
  standard <- attr(result, "standard")
  findings <- complete_findings(result$findings)
  # The numbers and sentences of the rule set this result was checked with.
  with_rule_family(rule_family(standard), {
    problems <- problem_summary(findings, truncated, standard)
    records <- record_rows(findings, problems)
    rules <- rules_sheet(findings, skipped, attr(result, "ran"), attr(result, "filtered"))
  })
  add <- function(x, cols) {
    if (isTRUE(tracking)) {
      for (col in cols) x[[col]] <- rep("", nrow(x))
    }
    as.data.frame(x)
  }
  list(
    Problems = add(data.table::data.table(
      Priority = problems$triage, Dataset = problems$Dataset,
      Problem = paste0(problems$issue, " (", problems$rule_id, ")"),
      Details = problems$details, Records = problems$affects
    ), c("Status", "Notes")),
    Records = add(data.table::data.table(
      Dataset = records$Dataset, USUBJID = records$USUBJID, SEQ = records$SEQ,
      Problem = records$issue, Values = records$values
    ), "Notes"),
    `Not checked` = not_checked_sheet(skipped, about),
    Rules = rules
  )
}

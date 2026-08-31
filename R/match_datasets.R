# Match Datasets: joins another domain's columns onto the dataset being
# checked, before the Check runs. Only the standard case is implemented -
# a plain equi-join on `Keys` against a regular SDTM domain. RELREC-based
# relationship joins, SUPPxx/SQxx pivot merges, and `Child` (parent-
# hierarchy) joins use genuinely different merge logic in the reference
# engine and are not implemented; attempting one raises an error (caught by
# callers as "can't evaluate this rule," not silently producing wrong
# answers).
#
# Column collisions: per the schema's own convention (seen directly in rule
# conditions, e.g. `SE.EPOCH`), a column present in both the current
# dataset and the matched dataset keeps its bare name on the current
# dataset's side; the matched dataset's version is exposed as
# "{MatchedDomainName}.{Column}". Non-colliding matched columns join in
# under their own bare name.
#
# Uses a left join (every row of the current dataset survives; unmatched
# rows get NA/blank for the joined-in columns) rather than the reference
# engine's default inner join, since dropping rows would break this
# package's row-per-record output contract - a real production study
# should have a DM record for every USUBJID anyway, so this rarely
# matters in practice.
#
# A one-to-many match (e.g. multiple time-windowed SE records per USUBJID)
# is kept as a full cartesian expansion, NOT deduplicated to "first match" -
# confirmed against the reference engine (a plain pd.merge with no row
# selection at all) and against a real rule: CORE-000097 matches SV to SE
# on USUBJID alone, and relies on its OWN Check conditions
# (SESTDTC <= SVSTDTC <= SEENDTC) to filter down to the one SE record whose
# time window actually contains the visit date. Deduplicating here to the
# first SE match would grab the wrong record. `.coreval_row_id` tracks each
# exploded row's original row, so downstream code (evaluate_rule(),
# assemble_findings()) can collapse back to one result per original record.
#' Collect every `name`/`value` string a Check tree references, plus Output Variables
#' @param rule A rule record.
#' @return A character vector of referenced target strings.
#' @noRd
collect_rule_targets <- function(rule) {
  walk <- function(node, acc) {
    if (is.null(node)) {
      return(acc)
    }
    for (field in c("name", "value")) {
      v <- node[[field]]
      if (is.character(v)) {
        acc <- c(acc, v)
      }
    }
    for (key in c("all", "any", "not")) {
      sub <- node[[key]]
      if (!is.null(sub)) {
        if (is.list(sub) && is.null(names(sub))) {
          for (item in sub) acc <- walk(item, acc)
        } else {
          acc <- walk(sub, acc)
        }
      }
    }
    acc
  }
  declared <- rule$outcome[["Output Variables"]]
  unique(c(walk(rule$check, character(0)), if (is.character(declared)) declared))
}

#' Rename a matched dataset's columns that the rule explicitly references as `<Name>.<col>`
#'
#' The reference engine prefixes the columns a rule NAMES as
#' `"<MatchName>.<column>"` before merging, whether or not they collide -
#' `dataset_preprocessor.py` builds `referenced_targets` from the rule's own
#' targets that start with `"<domain_name>."`, strips that prefix, and
#' renames exactly those columns; pandas' `suffixes=("", f".{domain}")`
#' then handles only the remaining true collisions.
#' @param right The matched dataset's data (mutated by reference).
#' @param rule A rule record (or `NULL` to skip).
#' @param match_name The Match Datasets `Name`.
#' @param keys Join keys, never renamed.
#' @return `invisible(NULL)`; `right` is modified in place.
#' @noRd
rename_referenced_match_columns <- function(right, rule, match_name, keys) {
  if (is.null(rule)) {
    return(invisible(NULL))
  }
  targets <- collect_rule_targets(rule)
  prefix <- paste0(match_name, ".")
  referenced <- sub(prefix, "", targets[startsWith(targets, prefix)], fixed = TRUE)
  referenced <- setdiff(intersect(referenced, names(right)), keys)
  if (length(referenced) > 0) {
    data.table::setnames(right, referenced, paste0(prefix, referenced))
  }
  invisible(NULL)
}

# Pivots a SUPPxx/SQxx supplemental-qualifier dataset from its long
# QNAM/QVAL shape into one column per QNAM, then left-joins it onto the
# parent domain - the reference engine's `process_supp()` +
# `merge_pivot_supp_dataset()` (data_processor.py).
#
# The join key is not the rule's declared `Keys`: the reference ignores
# those here and joins on the static identifier columns present in BOTH
# datasets (STUDYID/USUBJID/APID/POOLID/SPDEVID) plus, when the SUPP's own
# IDVAR names one, that record-level key. SUPP's IDVARVAL is renamed to the
# IDVAR column's name so it lines up with the parent's own column - and
# when the parent's key is numeric both sides are string-converted first,
# since IDVARVAL is always character (`1` must match `"1"`).
#' Pivot a SUPP/SQ dataset's QNAM/QVAL pairs into one column per QNAM
#' @param supp The supplemental dataset's data.
#' @return A data.table with one row per parent record and one column per QNAM.
#' @noRd
pivot_supp_dataset <- function(supp) {
  qnams <- unique(supp$QNAM[!is_blank(supp$QNAM)])
  drop_cols <- intersect(c("QNAM", "QVAL", "QLABEL"), names(supp))
  group_cols <- setdiff(names(supp), c(qnams, drop_cols))

  out <- unique(supp[, group_cols, with = FALSE])
  key <- function(dt) {
    do.call(paste, c(lapply(group_cols, function(c) as.character(dt[[c]])), sep = "\x1f"))
  }
  out_key <- key(out)
  supp_key <- key(supp)
  for (qnam in qnams) {
    rows <- which(supp$QNAM == qnam)
    out[[qnam]] <- supp$QVAL[rows][match(out_key, supp_key[rows])]
  }
  out
}

#' Left-join a pivoted SUPP/SQ dataset onto its parent domain
#' @param dataset The parent dataset being checked (`list(data, meta)`).
#' @param supp_dataset The supplemental dataset (`list(data, meta)`).
#' @return `dataset` with one joined-in column per QNAM.
#' @noRd
apply_supp_match <- function(dataset, supp_dataset) {
  supp <- supp_dataset$data
  if (!all(c("QNAM", "QVAL") %in% names(supp)) || nrow(supp) == 0) {
    return(dataset)
  }
  idvars <- unique(supp$IDVAR)
  if (length(idvars) > 1) {
    stop(
      "Match Datasets: SUPP dataset uses multiple IDVAR values, which is not implemented",
      call. = FALSE
    )
  }

  pivoted <- pivot_supp_dataset(supp)
  left <- data.table::copy(dataset$data)
  static_keys <- c("STUDYID", "USUBJID", "APID", "POOLID", "SPDEVID")
  keys <- intersect(intersect(static_keys, names(left)), names(pivoted))

  idvar <- if (length(idvars) == 1) idvars[[1]] else NA_character_
  if (!is_blank(idvar) && idvar %in% names(left) && "IDVARVAL" %in% names(pivoted)) {
    # IDVARVAL holds the parent record's key VALUE; rename it to the key's
    # own name so the join lines up, and compare as text on both sides
    # (IDVARVAL is character even when the parent's key is numeric).
    data.table::setnames(pivoted, "IDVARVAL", idvar)
    left[[idvar]] <- as.character(left[[idvar]])
    pivoted[[idvar]] <- as.character(pivoted[[idvar]])
    keys <- c(keys, idvar)
  }
  for (col in intersect(c("IDVAR", "IDVARVAL", "RDOMAIN"), names(pivoted))) {
    pivoted[[col]] <- NULL
  }
  if (length(keys) == 0) {
    return(dataset)
  }

  if (!(".coreval_row_id" %in% names(left))) {
    left$.coreval_row_id <- seq_len(nrow(left))
  }
  merged <- merge(left, pivoted, by = keys, all.x = TRUE, sort = FALSE)
  merged <- merged[order(merged$.coreval_row_id)]
  list(data = merged, meta = dataset$meta)
}

# A "Child" join runs the OTHER way round from the ordinary one: the dataset
# being checked is the CHILD (a SUPPxx, CO or RELREC record), and the join
# pulls in the PARENT record that child points at. The parent isn't named by
# the rule - each child row names it itself, in RDOMAIN - so different rows
# of one dataset can join to entirely different domains.
#
# Per the reference's `_merge_rdomain_dataset` / `_merge_standard_then_filter_idvar`
# (dataset_preprocessor.py), each child row is resolved individually:
#   1. narrow the parent to rows matching the standard keys (USUBJID, ...);
#   2. among those, pick the one whose IDVAR-named column equals IDVARVAL
#      (e.g. IDVAR="AESEQ", IDVARVAL="3" -> the parent row with AESEQ == 3);
#   3. with no usable IDVAR/IDVARVAL, take the first candidate;
#   4. with no candidate at all, keep the child row and leave the parent's
#      columns missing.
# The parent's values win on a name collision, matching the reference's own
# `{**child_row, **final_match}` ordering.
#' Join each child record to the parent record it names via RDOMAIN/IDVAR
#' @param dataset The child dataset being checked (`list(data, meta)`).
#' @param study Full study object.
#' @param keys The spec's `Keys` (IDVAR/IDVARVAL are handled specially).
#' @return `dataset` with the matched parent columns joined in.
#' @noRd
apply_child_match <- function(dataset, study, keys) {
  child <- data.table::copy(dataset$data)
  if (nrow(child) == 0) {
    return(dataset)
  }
  standard_keys <- setdiff(keys, c("IDVAR", "IDVARVAL"))
  rdomain <- child[["RDOMAIN"]]
  if (is.null(rdomain)) {
    return(dataset)
  }

  scalar_or_na <- function(row, col) {
    if (!(col %in% names(row))) NA_character_ else as.character(row[[col]])[1]
  }

  merged <- lapply(seq_len(nrow(child)), function(i) {
    row <- child[i, ]
    parent <- study$datasets[[toupper(rdomain[i])]]
    if (is.null(parent) || nrow(parent$data) == 0) {
      return(row)
    }
    candidates <- parent$data
    for (k in standard_keys) {
      if (k %in% names(candidates) && k %in% names(row)) {
        candidates <- candidates[as.character(candidates[[k]]) == as.character(row[[k]]), ]
      }
    }
    idvar <- scalar_or_na(row, "IDVAR")
    idvarval <- scalar_or_na(row, "IDVARVAL")
    pick <- if (nrow(candidates) == 0) {
      NULL
    } else if (!is_blank(idvar) && !is_blank(idvarval) && idvar %in% names(candidates)) {
      hit <- which(as.character(candidates[[idvar]]) == idvarval)
      if (length(hit) == 0) NULL else candidates[hit[1], ]
    } else {
      candidates[1, ]
    }
    # With NO match the parent's columns are still added, as missing values.
    # That is not a cosmetic detail: a rule asking "is IDVARVAL really the
    # value of the parent variable IDVAR names" needs that column to EXIST
    # and be empty in order to report the mismatch. Returning the child row
    # untouched instead makes the column absent, the comparison
    # unresolvable, and the violation silently disappear.
    if (is.null(pick)) {
      pick <- parent$data[0, ][NA_integer_, ]
    }
    keep <- setdiff(names(row), names(pick))
    cbind(row[, keep, with = FALSE], pick)
  })

  list(
    data = data.table::rbindlist(merged, use.names = TRUE, fill = TRUE),
    meta = dataset$meta
  )
}

#' Left-join one Match Datasets spec's columns onto a dataset
#' @param dataset The dataset being checked (`list(data, meta)`).
#' @param spec One Match Datasets spec (`Name`, `Keys`, optional `Child`).
#' @param study Full study object.
#' @param current_domain Domain code of `dataset`, used to resolve `"--"` key names.
#' @param rule The rule being evaluated, used to prefix the matched columns it
#'   references as `"<Name>.<col>"`; `NULL` applies collision-renaming only.
#' @return `dataset` with the matched columns joined in.
#' @noRd
apply_match_dataset <- function(dataset, spec, study, current_domain, rule = NULL) {
  match_name <- spec$Name
  if (identical(match_name, "RELREC") && is.null(spec$Child)) {
    return(apply_relrec_match(dataset, study, current_domain))
  }
  # A "SUPP--"/"SQ--" name is a template for THIS domain's supplemental
  # dataset (SUPP-- against LB means SUPPLB), resolved off the DOMAIN
  # column's value like any other "--" template.
  #
  # Only when the dataset being checked is the PARENT, though. A rule can
  # also be scoped to the SUPP dataset itself, to check its referential
  # integrity (CORE-000206/CORE-000712 read IDVAR/IDVARVAL/RDOMAIN
  # directly) - that is the reference's `_child_merge_datasets` parent
  # join, a genuinely different merge this package doesn't implement.
  # Pivoting there would join a SUPP dataset to itself and quietly answer
  # the wrong question, so fall through to the error and let the rule be
  # reported as unevaluable instead.
  if (grepl("^(SUPP|SQ)", match_name) && !isTRUE(spec$Child) &&
      !grepl("^(SUPP|SQ)", toupper(current_domain))) {
    supp_name <- sub("--$", dataset_wildcard(dataset, current_domain), match_name)
    supp_dataset <- study$datasets[[toupper(supp_name)]]
    if (is.null(supp_dataset)) {
      return(dataset)
    }
    return(apply_supp_match(dataset, supp_dataset))
  }
  # A Child spec names the CHILD dataset - which, for every bundled rule
  # using one, is the dataset being checked. So this joins each row to the
  # parent it names in RDOMAIN rather than to some other named domain.
  if (isTRUE(spec$Child)) {
    return(apply_child_match(dataset, study, spec$Keys))
  }
  if (identical(match_name, "RELREC")) {
    stop("Match Datasets: unsupported join type for '", match_name, "'", call. = FALSE)
  }

  match_dataset <- study$datasets[[match_name]]
  if (is.null(match_dataset)) {
    return(dataset)
  }

  # A Match Datasets `Keys` list is a COMPLETE composite key (e.g.
  # USUBJID+VISITNUM identifies one specific SV record per subject-visit) -
  # dropping just the keys missing from one side and joining on whatever's
  # left turns "one matching record per row" into an uncontrolled cartesian
  # join (e.g. every SV visit for that subject, if the current domain has
  # no VISITNUM of its own at all). Confirmed against CORE-000270: AE has
  # no native VISITNUM, so joining on USUBJID alone attached SV's VISITNUM
  # from EVERY visit to each AE row, fabricating "VISITNUM not in TV"
  # violations for a domain this rule can't actually evaluate that way. If
  # any key is missing from either side, the whole join is unresolvable for
  # this domain - skip it entirely rather than degrading to a looser one.
  keys <- resolve_var_name(spec$Keys, dataset_wildcard(dataset, current_domain))
  if (!all(keys %in% names(dataset$data)) || !all(keys %in% names(match_dataset$data))) {
    return(dataset)
  }

  left <- data.table::copy(dataset$data)
  right <- data.table::copy(match_dataset$data)

  # Prefix the columns the RULE ITSELF references as "<Name>.<col>" first -
  # regardless of whether they collide - then let the collision rule below
  # handle whatever is left, exactly as the reference engine does
  # (dataset_preprocessor.py renames referenced targets, then pandas'
  # suffixes=("", f".{domain}") catches the rest). Doing only the collision
  # half means a referenced column that happens NOT to collide joins in
  # under its bare name, so the rule's own "DM.RFPENDTC" reference finds no
  # such column and resolve_condition_value() degrades it to a literal
  # string comparison - silently always-false (CORE-000952 found nothing)
  # or always-true (CORE-000249 flagged all 4452 LB rows). This is also the
  # principled fix for CLAUDE.md's open question 17: it makes the joined
  # column visible ONLY under its prefixed name, so a bare "--VISITDY
  # exists" correctly stays FALSE for a domain with no native VISITDY,
  # without touching exists/not_exists semantics at all.
  rename_referenced_match_columns(right, rule, match_name, keys)

  collide <- intersect(setdiff(names(right), keys), names(left))
  if (length(collide) > 0) {
    data.table::setnames(right, collide, paste0(match_name, ".", collide))
  }

  # Only stamp row ids on the first join in a chain - a second Match
  # Datasets entry must keep pointing back to the ORIGINAL row, not to the
  # first join's already-exploded rows.
  if (!(".coreval_row_id" %in% names(left))) {
    left$.coreval_row_id <- seq_len(nrow(left))
  }

  # A blank/missing key must never match another blank/missing key - unlike
  # base R/data.table merge, which treats NA (and "" as an ordinary string)
  # as an otherwise-matchable value. A blank USUBJID is a data defect, not
  # a legitimate join target; merging it against another row's blank
  # USUBJID would fabricate a match. Rows with a blank key are excluded
  # from the merge and get NA for every joined-in column instead, matching
  # what a left join against a genuinely missing key should produce.
  is_key_blank <- Reduce(`|`, lapply(keys, function(k) is_blank(left[[k]])))
  left_valid <- left[!is_key_blank]
  left_blank <- left[is_key_blank]

  merged_valid <- merge(left_valid, right, by = keys, all.x = TRUE, allow.cartesian = TRUE)

  if (nrow(left_blank) > 0) {
    right_only_cols <- setdiff(names(right), keys)
    for (col in right_only_cols) {
      left_blank[[col]] <- right[[col]][NA_integer_]
    }
  }

  merged <- data.table::rbindlist(list(merged_valid, left_blank), use.names = TRUE, fill = TRUE)
  merged <- merged[order(merged$.coreval_row_id)]

  list(data = merged, meta = dataset$meta)
}

#' Left-join a rule's Match Datasets "RELREC" relationship onto a dataset
#'
#' RELREC declares relationships between records in DIFFERENT domains via a
#' shared `RELID` (each side's own row in RELREC gives `RDOMAIN`/`IDVAR`/
#' `IDVARVAL` identifying which record(s) sit on that side). Two sub-patterns
#' coexist in the same table and are handled by one algorithm:
#'   - record-level (`IDVARVAL` populated): pins one exact record per side.
#'   - group-level (`IDVARVAL` blank): pairs rows by IDVAR column VALUE
#'     EQUALITY between the two domains (e.g. `CM.CMGRPID == FA.FAGRPID`).
#' Confirmed against CORE-000757's real fixtures: for a current-domain row
#' `r` and a RELREC row `m` where `RDOMAIN == current_domain`, `r` qualifies
#' when `m$IDVARVAL` is blank (unconstrained) or `r[[m$IDVAR]] == m$IDVARVAL`
#' (record-level pin). For each partner RELREC row `p` sharing `m$RELID`
#' (`RDOMAIN != current_domain`), the match key is `p$IDVARVAL` when
#' populated (a literal, independent of `r`), else `r[[m$IDVAR]]` (group-level
#' value join). Joined columns are always exposed under a literal
#' `"RELREC.<column>"` prefix (never the partner's actual domain name), since
#' which domain ends up on the other side of a RELID varies per rule - unlike
#' the generic join's collision-only renaming.
#' @param dataset The dataset being checked (`list(data, meta)`).
#' @param study Full study object (needs `$datasets$RELREC` and the partner domain).
#' @param current_domain Domain code of `dataset`.
#' @return `dataset` with any matched RELREC-linked columns joined in.
#' @noRd
apply_relrec_match <- function(dataset, study, current_domain) {
  relrec <- study$datasets[["RELREC"]]
  if (is.null(relrec)) {
    return(dataset)
  }
  rr <- relrec$data
  my_side <- rr[toupper(rr$RDOMAIN) == toupper(current_domain), ]
  if (nrow(my_side) == 0) {
    return(dataset)
  }

  left <- data.table::copy(dataset$data)
  if (!(".coreval_row_id" %in% names(left))) {
    left$.coreval_row_id <- seq_len(nrow(left))
  }

  matched <- list()
  for (i in seq_len(nrow(my_side))) {
    m <- my_side[i, ]
    if (!(m$IDVAR %in% names(left))) {
      next
    }
    left_qualifies <- if (!is_blank(m$IDVARVAL)) {
      as.character(left[[m$IDVAR]]) == m$IDVARVAL
    } else {
      rep(TRUE, nrow(left))
    }
    if (!is_blank(m$USUBJID) && "USUBJID" %in% names(left)) {
      left_qualifies <- left_qualifies & (left$USUBJID == m$USUBJID)
    }
    qualifying_idx <- which(left_qualifies)
    if (length(qualifying_idx) == 0) {
      next
    }

    partners <- rr[rr$RELID == m$RELID & toupper(rr$RDOMAIN) != toupper(current_domain), ]
    for (j in seq_len(nrow(partners))) {
      p <- partners[j, ]
      partner_ds <- study$datasets[[toupper(p$RDOMAIN)]]
      if (is.null(partner_ds) || !(p$IDVAR %in% names(partner_ds$data))) {
        next
      }
      right <- partner_ds$data

      for (ri in qualifying_idx) {
        key_val <- if (!is_blank(p$IDVARVAL)) p$IDVARVAL else as.character(left[[m$IDVAR]][ri])
        right_idx <- which(as.character(right[[p$IDVAR]]) == key_val)
        # A GROUP-level relationship (both sides' RELREC row leave USUBJID
        # blank, common when IDVAR/IDVARVAL alone are meant to identify the
        # group) still only ever links records of the SAME subject in
        # practice - RELREC's own IDVAR value (e.g. a shared link-group ID)
        # is not guaranteed unique across different subjects. Confirmed
        # against CORE-000744's real fixture: with no subject constraint,
        # an FA row's FALNKGRP matched an AE row sharing that same numeric
        # AELNKID under a COMPLETELY DIFFERENT USUBJID, fabricating a bogus
        # cross-subject relationship. Only applies when RELREC didn't
        # already pin an explicit partner USUBJID itself (`p$USUBJID`) -
        # that case already narrows correctly on its own.
        if (is_blank(p$USUBJID) && "USUBJID" %in% names(right) && "USUBJID" %in% names(left)) {
          right_idx <- right_idx[as.character(right$USUBJID[right_idx]) == as.character(left$USUBJID[ri])]
        }
        for (rj in right_idx) {
          right_row <- right[rj, ]
          data.table::setnames(right_row, names(right_row), paste0("RELREC.", names(right_row)))
          matched[[length(matched) + 1]] <- cbind(left[ri, ], right_row)
        }
      }
    }
  }

  if (length(matched) == 0) {
    return(list(data = left[0, ], meta = dataset$meta))
  }
  # Unlike the generic Keys-based join (which keeps every row, since a real
  # study should have e.g. a DM record for every USUBJID), a RELREC
  # relationship is itself the thing being checked - a row with NO RELREC
  # partner at all has nothing to compare, and a rule's Check typically has
  # no explicit guard for that (unlike e.g. CORE-000757's own defensive
  # `RELREC.FAOBJ non_empty` condition). Confirmed against CORE-000744's
  # real fixtures: FA records with no RELREC entry at all must never be
  # flagged, but a `not_equal_to` comparison against a genuinely blank
  # comparator is a REAL violation per the reference engine's own truth
  # table ("Populated" target vs "" comparator -> True) - so a left join
  # (keeping unmatched rows with blank joined columns) would wrongly flag
  # them. Dropping unmatched rows entirely (an inner join, matching the
  # reference engine's own default for this join type) is the only way to
  # keep them out of consideration; `.coreval_row_id` still lets any
  # surviving row's violation map back to its correct original Record.
  matched_dt <- data.table::rbindlist(matched, fill = TRUE)
  merged <- matched_dt[order(matched_dt$.coreval_row_id)]
  list(data = merged, meta = dataset$meta)
}

#' Apply all of a rule's Match Datasets joins to a dataset
#' @param dataset The dataset being checked (`list(data, meta)`).
#' @param rule A rule record.
#' @param study Full study object.
#' @param current_domain Domain code of `dataset`.
#' @return `dataset` with every matched dataset's columns joined in.
#' @noRd
apply_match_datasets <- function(dataset, rule, study, current_domain) {
  if (is.null(rule$match_datasets)) {
    return(dataset)
  }
  for (spec in rule$match_datasets) {
    dataset <- apply_match_dataset(dataset, spec, study, current_domain, rule)
  }
  dataset
}

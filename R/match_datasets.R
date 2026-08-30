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
#' Left-join one Match Datasets spec's columns onto a dataset
#' @param dataset The dataset being checked (`list(data, meta)`).
#' @param spec One Match Datasets spec (`Name`, `Keys`, optional `Child`).
#' @param study Full study object.
#' @param current_domain Domain code of `dataset`, used to resolve `"--"` key names.
#' @return `dataset` with the matched columns joined in.
#' @noRd
apply_match_dataset <- function(dataset, spec, study, current_domain) {
  match_name <- spec$Name
  if (identical(match_name, "RELREC") && is.null(spec$Child)) {
    return(apply_relrec_match(dataset, study, current_domain))
  }
  if (!is.null(spec$Child) || identical(match_name, "RELREC") || grepl("^(SUPP|SQ)", match_name)) {
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
  keys <- resolve_var_name(spec$Keys, current_domain)
  if (!all(keys %in% names(dataset$data)) || !all(keys %in% names(match_dataset$data))) {
    return(dataset)
  }

  left <- data.table::copy(dataset$data)
  right <- data.table::copy(match_dataset$data)

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
        for (rj in right_idx) {
          right_row <- right[rj, ]
          data.table::setnames(right_row, names(right_row), paste0("RELREC.", names(right_row)))
          matched[[length(matched) + 1]] <- cbind(left[ri, ], right_row)
        }
      }
    }
  }

  if (length(matched) == 0) {
    return(dataset)
  }
  matched_dt <- data.table::rbindlist(matched, fill = TRUE)
  matched_ids <- unique(matched_dt$.coreval_row_id)
  unmatched <- left[!(left$.coreval_row_id %in% matched_ids), ]
  if (nrow(unmatched) > 0) {
    right_only_cols <- setdiff(names(matched_dt), names(left))
    for (col in right_only_cols) {
      unmatched[[col]] <- matched_dt[[col]][NA_integer_]
    }
  }
  merged <- data.table::rbindlist(list(matched_dt, unmatched), use.names = TRUE, fill = TRUE)
  merged <- merged[order(merged$.coreval_row_id)]
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
    dataset <- apply_match_dataset(dataset, spec, study, current_domain)
  }
  dataset
}

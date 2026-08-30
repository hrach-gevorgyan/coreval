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
apply_match_dataset <- function(dataset, spec, study, current_domain) {
  match_name <- spec$Name
  if (!is.null(spec$Child) || identical(match_name, "RELREC") || grepl("^(SUPP|SQ)", match_name)) {
    stop("Match Datasets: unsupported join type for '", match_name, "'", call. = FALSE)
  }

  match_dataset <- study$datasets[[match_name]]
  if (is.null(match_dataset)) {
    return(dataset)
  }

  keys <- resolve_var_name(spec$Keys, current_domain)
  keys <- keys[keys %in% names(dataset$data) & keys %in% names(match_dataset$data)]
  if (length(keys) == 0) {
    return(dataset)
  }

  left <- data.table::copy(dataset$data)
  right <- data.table::copy(match_dataset$data)

  collide <- intersect(setdiff(names(right), keys), names(left))
  if (length(collide) > 0) {
    data.table::setnames(right, collide, paste0(match_name, ".", collide))
  }

  left$.row_id <- seq_len(nrow(left))
  # A one-to-many match legitimately explodes rows temporarily; the dedup
  # below (keep first match per original row) is what makes that safe.
  merged <- merge(left, right, by = keys, all.x = TRUE, allow.cartesian = TRUE)
  merged <- merged[order(merged$.row_id)]
  # A one-to-many match (e.g. multiple SE records per USUBJID) would
  # duplicate original rows; keep only the first match per original row so
  # the result stays aligned to the dataset being checked.
  merged <- merged[!duplicated(merged$.row_id)]
  merged$.row_id <- NULL

  list(data = merged, meta = dataset$meta)
}

apply_match_datasets <- function(dataset, rule, study, current_domain) {
  if (is.null(rule$match_datasets)) {
    return(dataset)
  }
  for (spec in rule$match_datasets) {
    dataset <- apply_match_dataset(dataset, spec, study, current_domain)
  }
  dataset
}

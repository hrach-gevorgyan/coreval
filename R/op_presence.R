# exists/not_exists check whether the VARIABLE is present in the dataset at
# all - a dataset-level fact, not a per-row value check. (Contrast with
# empty/non_empty below, which check per-row blankness.)
# Operator: exists - is the target variable present in the dataset?
register_operator("exists", function(ctx) ctx$exists)
# Operator: not_exists - is the target variable absent from the dataset?
register_operator("not_exists", function(ctx) !ctx$exists)

# A missing column is UNRESOLVABLE, not "empty in every record" - a domain
# that structurally doesn't have the variable at all (e.g. EC has no
# ECSTAT) is a different situation than one that has the variable, blank.
# An earlier version treated a missing column as empty=TRUE; verified
# empirically against every one of the 333 rules using empty/non_empty
# that returning NA instead is a strict improvement (fixes CORE-000018's
# real fixture - EC's own results.csv expects NO violation when ECSTAT
# doesn't exist, unlike AG/BE/CE/... in the SAME test case, which DO have a
# real, blank --STAT column and ARE expected to violate - with zero
# regressions anywhere else). Char blanks are "" (never NA, per
# read_study()'s convention); numeric blanks are NA.
# Operator: empty - is the target value blank? NA (unresolvable) if the column doesn't exist at all
register_operator("empty", function(ctx) {
  if (!ctx$exists) {
    return(rep(NA, ctx$n))
  }
  if (is.character(ctx$target)) ctx$target == "" else is.na(ctx$target)
})

# Operator: non_empty - is the target value non-blank?
register_operator("non_empty", function(ctx) {
  !get_operator("empty")(ctx)
})

# A family of enumerated columns (target, target1, target2, ... - e.g.
# COVAL/COVAL1/COVAL2) must be populated with no gaps: once one is blank,
# every later one in the sequence must be blank too. Confirmed against
# CORE-000780's real fixtures: COVAL blank but COVAL1/COVAL2 populated is
# flagged (COVAL skipped); COVAL populated, COVAL1 blank, COVAL2 populated
# is also flagged (COVAL1 skipped); COVAL populated with COVAL1/COVAL2 both
# blank is NOT flagged (nothing after the first blank is populated).
# Operator: inconsistent_enumerated_columns - flags a gap in a target/target1/target2/... column family
register_operator("inconsistent_enumerated_columns", function(ctx) {
  if (!ctx$exists) {
    return(rep(FALSE, ctx$n))
  }
  cols <- names(ctx$dataset$data)
  suffixed <- cols[grepl(paste0("^", ctx$name, "[0-9]+$"), cols)]
  suffix_num <- as.integer(sub(paste0("^", ctx$name), "", suffixed))
  ordered_cols <- c(ctx$name, suffixed[order(suffix_num)])
  if (length(ordered_cols) < 2) {
    return(rep(FALSE, ctx$n))
  }
  blank_mat <- vapply(ordered_cols, function(col) is_blank(ctx$dataset$data[[col]]), logical(ctx$n))
  vapply(seq_len(ctx$n), function(i) {
    row_blanks <- blank_mat[i, ]
    first_blank <- which(row_blanks)[1]
    !is.na(first_blank) && first_blank < length(row_blanks) && any(!row_blanks[(first_blank + 1):length(row_blanks)])
  }, logical(1))
})

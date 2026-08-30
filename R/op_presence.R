# exists/not_exists check whether the VARIABLE is present in the dataset at
# all - a dataset-level fact, not a per-row value check. (Contrast with
# empty/non_empty below, which check per-row blankness.)
# Operator: exists - is the target variable present in the dataset?
register_operator("exists", function(ctx) ctx$exists)
# Operator: not_exists - is the target variable absent from the dataset?
register_operator("not_exists", function(ctx) !ctx$exists)

# A missing column is treated as "empty in every record" - there is no value
# to be non-empty. Char blanks are "" (never NA, per read_study()'s
# convention); numeric blanks are NA.
# Operator: empty - is the target value blank (or the column missing)?
register_operator("empty", function(ctx) {
  if (!ctx$exists) {
    return(rep(TRUE, ctx$n))
  }
  if (is.character(ctx$target)) ctx$target == "" else is.na(ctx$target)
})

# Operator: non_empty - is the target value non-blank?
register_operator("non_empty", function(ctx) {
  !get_operator("empty")(ctx)
})

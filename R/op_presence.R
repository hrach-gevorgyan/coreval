# exists/not_exists check whether the VARIABLE is present in the dataset at
# all - a dataset-level fact, not a per-row value check. (Contrast with
# empty/non_empty below, which check per-row blankness.)
register_operator("exists", function(ctx) ctx$exists)
register_operator("not_exists", function(ctx) !ctx$exists)

# A missing column is treated as "empty in every record" - there is no value
# to be non-empty. Char blanks are "" (never NA, per read_study()'s
# convention); numeric blanks are NA.
register_operator("empty", function(ctx) {
  if (!ctx$exists) {
    return(rep(TRUE, ctx$n))
  }
  if (is.character(ctx$target)) ctx$target == "" else is.na(ctx$target)
})

register_operator("non_empty", function(ctx) {
  !get_operator("empty")(ctx)
})

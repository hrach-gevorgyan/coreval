# Regenerates inst/extdata/sdtm_model_variables.rds: for each SDTM
# observation class, the variables the abstract SDTM Model allows for that
# class, with the label, role and data type the Model assigns.
#
# Supersedes the earlier hand-listed, names-only version. Two consumers:
#   * `get_model_column_order` ("is this variable name allowed for this
#     domain's class at all") - the original use, names only.
#   * the CDISC Library variable lookup's FALLBACK. An IG's per-domain
#     variable list doesn't include every variable a sponsor may legitimately
#     use; the Model's generic "--"-templated variables do. Without this
#     fallback a Model-defined variable like LBCHENDY (from "--CHENDY") looks
#     completely unknown, and rules comparing against Library metadata treat
#     it as undefined instead of checking it against the type the Model
#     actually specifies. Confirmed against CORE-001082, where "--CHENDY" is
#     Num and "--DUR" is Char: its negative fixture declares LBCHENDY as Char
#     (a genuine mismatch) and LBDURATION, which matches no Model template at
#     all, while its positive fixture declares LBCHENDY as Num and LBDUR
#     (matching "--DUR", Char) - so all three outcomes hinge on the Model.
#
# Contrast with sdtm_domain_classes.rds, which maps a DOMAIN to its class
# name rather than a class to its variables.
#
# Machine-extracted from cdisc-org/cdisc-rules-engine's own bundled cache
# (resources/cache/standards_models.pkl, key "models/sdtm/2-1" - the newest
# Model, used as a superset per the same simplification domain_classes.R
# documents), which that MIT-licensed, CDISC-published repository commits
# directly to git. NO CDISC API is contacted, at build or run time.
# data-raw/dump_model_variables.py is the unpickle step; re-run it only when
# the clone is refreshed. Both scripts run at build time only.
#
# Variable names here can be "--"-prefixed templates (e.g. "--SEQ") exactly
# like a rule's own `check.name` - resolve_var_name() already handles this.

csv_path <- file.path("data-raw", "model_variables.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_model_variables.py",
    call. = FALSE
  )
}

model_variables <- utils::read.csv(csv_path, stringsAsFactors = FALSE, colClasses = "character")
model_variables <- model_variables[nzchar(model_variables$variable), ]
model_variables$ordinal <- suppressWarnings(as.integer(model_variables$ordinal))

# Every observation class INHERITS the General Observations variables, and
# the cache lists only each class's OWN additions. Consumers ask "is this
# variable allowed for this class at all", so the inherited set is folded
# into each class here rather than at every call site - otherwise a
# perfectly ordinary variable like USUBJID looks disallowed for Findings.
# `source_class` records where a row CAME from, which `class` alone can no
# longer say once inheritance is folded in. The standard's expected variable
# ORDER is built in sections - General Observations identifiers, then the
# class's own variables, then General Observations timing - so reconstructing
# those sections later needs to know which rows were inherited.
model_variables$source_class <- model_variables$class

general <- model_variables[model_variables$class == "General Observations", ]
specific <- model_variables[model_variables$class != "General Observations", ]
inherited <- do.call(rbind, lapply(unique(specific$class), function(cls) {
  rows <- general
  rows$class <- cls
  rows
}))
model_variables <- rbind(model_variables, inherited)
# A class's own definition wins over the inherited one where both exist.
model_variables <- model_variables[!duplicated(model_variables[, c("class", "variable")]), ]

stopifnot(
  nrow(model_variables) > 0,
  "General Observations" %in% model_variables$class,
  # The "--" templates are the entire point of the fallback; a table without
  # them would silently make every sponsor variable look undefined.
  any(startsWith(model_variables$variable, "--")),
  # Spot-check the two the CORE-001082 analysis turns on.
  identical(model_variables$type[model_variables$variable == "--CHENDY"][1], "Num"),
  identical(model_variables$type[model_variables$variable == "--DUR"][1], "Char")
)

saveRDS(
  model_variables,
  file.path("inst", "extdata", "sdtm_model_variables.rds"),
  compress = "xz"
)

cat(sprintf(
  "Wrote inst/extdata/sdtm_model_variables.rds: %d rows across %d classes\n",
  nrow(model_variables), length(unique(model_variables$class))
))

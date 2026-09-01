# Regenerates inst/extdata/sdtm_model_dataset_variables.rds: for each SDTM
# Model DATASET, the variables the Model defines for it.
#
# This is the companion to sdtm_model_variables.rds, which is organised by
# observation CLASS. Four classes - Special-Purpose, Relationship, Trial
# Design and Study Reference - have no class-level variable list in the Model
# at all; each of their datasets (DM, RELREC, TA, TS, ...) defines its own
# variables instead. So for a domain in one of those classes, the class-level
# table is empty and this one is the only answer available.
#
# `get_model_column_order` ("is this variable allowed for this domain") used
# to return NULL for exactly those domains, which meant rules like
# CORE-000550 and CORE-001079 silently found nothing on DM - an invalid
# variable such as ARMCDXX went unreported. The reference engine reads the
# Model's per-dataset metadata here, so this table closes that gap.
#
# Same source, same terms as model_variables.R: cdisc-org/cdisc-rules-engine's
# own bundled cache (resources/cache/standards_models.pkl, key
# "models/sdtm/2-1"), which that MIT-licensed, CDISC-published repository
# commits directly to git. NO CDISC API is contacted, at build or run time.
# data-raw/dump_model_variables.py writes both CSVs in one pass.
#
# Unlike the class-level table these are real, resolved variable names, not
# "--" templates - a dataset's variables are spelled out (DM has ARMCD, not
# "--ARMCD"). No General Observations inheritance is folded in either: these
# datasets are not observation-class datasets and do not inherit from it.

csv_path <- file.path("data-raw", "model_dataset_variables.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_model_variables.py",
    call. = FALSE
  )
}

model_dataset_variables <- utils::read.csv(
  csv_path,
  stringsAsFactors = FALSE, colClasses = "character"
)
model_dataset_variables <- model_dataset_variables[
  nzchar(model_dataset_variables$variable),
]
model_dataset_variables$ordinal <- suppressWarnings(
  as.integer(model_dataset_variables$ordinal)
)

stopifnot(
  nrow(model_dataset_variables) > 0,
  # The domains this table exists to serve.
  all(c("DM", "RELREC", "TA", "TS") %in% model_dataset_variables$domain),
  # Spot-check the one CORE-000550's fixture turns on: ARMCD is a real DM
  # variable, ARMCDXX (its fixture's typo) must not be.
  "ARMCD" %in% model_dataset_variables$variable[model_dataset_variables$domain == "DM"],
  !"ARMCDXX" %in% model_dataset_variables$variable
)

saveRDS(
  model_dataset_variables,
  file.path("inst", "extdata", "sdtm_model_dataset_variables.rds"),
  compress = "xz"
)

cat(sprintf(
  "Wrote inst/extdata/sdtm_model_dataset_variables.rds: %d rows across %d datasets\n",
  nrow(model_dataset_variables), length(unique(model_dataset_variables$domain))
))

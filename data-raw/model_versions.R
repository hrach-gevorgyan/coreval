# Regenerates inst/extdata/sdtm_model_versions.rds: the SDTM Model each
# SDTMIG version links to, for the CORE 1.0 rules.
#
# CORE 1.0 reads the Model an Implementation Guide names (SDTMIG 3.2 uses
# Model 1.4, 3.3 uses 1.7, 3.4 uses 2.0). sdtm_model_variables.rds and
# sdtm_model_dataset_variables.rds hold Model 2.1 alone, which CDISC's rules
# keep using; a 1.0 rule reads the slice its study's guide links to instead
# (see use_sdtm_model()). Read against 2.1, a 3.2 study's AERLPRC was allowed
# where the Model it follows has no --RLPRC (CORE-000550).
#
# Machine-extracted from Verisian's engine's own bundled cache, MIT-licensed
# and committed to git. data-raw/dump_model_versions.py is the unpickle step.
# Build time only.

read <- function(name) {
  path <- file.path("data-raw", name)
  if (!file.exists(path)) {
    stop("Missing ", path, ".\nRegenerate it first:  python data-raw/dump_model_versions.py",
         call. = FALSE)
  }
  out <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  if ("ordinal" %in% names(out)) out$ordinal <- suppressWarnings(as.integer(out$ordinal))
  out
}

map <- read("model_versions_map.csv")
classes <- read("model_versions_classes.csv")
datasets <- read("model_versions_datasets.csv")

# As model_variables.R does for 2.1: every observation class inherits the
# General Observations variables, folded in per Model version, with
# `source_class` saying where a row came from.
fold <- function(rows) {
  rows$source_class <- rows$class
  general <- rows[rows$class == "General Observations", ]
  specific <- rows[rows$class != "General Observations", ]
  inherited <- do.call(rbind, lapply(unique(specific$class), function(cls) {
    g <- general
    g$class <- cls
    g
  }))
  out <- rbind(rows, inherited)
  out[!duplicated(out[, c("class", "variable")]), ]
}

models <- lapply(stats::setNames(nm = unique(map$model_version)), function(v) {
  list(
    variables = fold(classes[classes$model_version == v, setdiff(names(classes), "model_version")]),
    dataset_variables = datasets[datasets$model_version == v, setdiff(names(datasets), "model_version")]
  )
})
out <- list(ig_model = stats::setNames(map$model_version, map$ig_version), models = models)

has <- function(v, cls, var) var %in% out$models[[v]]$variables$variable[out$models[[v]]$variables$class == cls]
stopifnot(
  identical(unname(out$ig_model[c("3.2", "3.3", "3.4")]), c("1-4", "1-7", "2-0")),
  # The variable CORE-000550's 3.2 fixture turns on: Events has --RLPRC only from 2.0.
  !has("1-4", "Events", "--RLPRC"), has("2-0", "Events", "--RLPRC"),
  # SPTOBID arrived in 2.1 and is in none of these.
  !any(vapply(out$models, function(m) "SPTOBID" %in% m$variables$variable, logical(1))),
  all(vapply(out$models, function(m) "ARMCD" %in% m$dataset_variables$variable[m$dataset_variables$domain == "DM"],
             logical(1)))
)

saveRDS(out, file.path("inst", "extdata", "sdtm_model_versions.rds"), compress = "xz")
cat("Wrote inst/extdata/sdtm_model_versions.rds:",
    paste(names(out$models), vapply(out$models, function(m) nrow(m$variables), 1), collapse = ", "), "\n")

# Regenerates inst/extdata/usdm_entities.rds: CDISC's map from a USDM key or
# class name to the entity it holds.
#
#   python data-raw/dump_usdm_entities.py   # writes data-raw/usdm_entities.csv
#   Rscript data-raw/usdm_entities.R
#
# Needed to read a USDM document into tables: an object that does not declare
# its own instanceType is named after the key that held it, and a key like
# `epochId` names StudyEpoch rather than anything spelled like the key.

csv_path <- file.path("data-raw", "usdm_entities.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_usdm_entities.py",
    call. = FALSE
  )
}

raw <- utils::read.csv(csv_path, stringsAsFactors = FALSE, colClasses = "character")
usdm_entities <- stats::setNames(raw$entity, raw$key)

stopifnot(
  length(usdm_entities) > 100,
  !anyDuplicated(names(usdm_entities)),
  all(nzchar(usdm_entities)),
  # The wrapper key is what every top-level attribute of the document is filed
  # under, and it is spelled with backticks, which is the kind of thing a CSV
  # round-trip quietly mangles.
  "`this`" %in% names(usdm_entities),
  identical(unname(usdm_entities[["`this`"]]), "Wrapper"),
  # A couple of the ordinary mappings, so a build that produced the right
  # number of wrong rows does not pass.
  identical(unname(usdm_entities[["epochId"]]), "StudyEpoch"),
  identical(unname(usdm_entities[["activities"]]), "Activity")
)

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
out <- file.path("inst", "extdata", "usdm_entities.rds")
saveRDS(usdm_entities, out, compress = "xz")

cat(sprintf("Wrote %s: %d mappings, %.1f KB\n", out, length(usdm_entities),
            file.size(out) / 1e3))

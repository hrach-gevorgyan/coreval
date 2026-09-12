# Regenerates inst/extdata/dataset_labels.rds: the label each STANDARD gives
# each domain, per standard and version.
#
# Needed by the `domain_label` operation. The reference reads this label from
# the standard's own metadata (operations/domain_label.py), NOT from the
# study's dataset metadata - and the two differ: SENDIG calls LB "Laboratory"
# where SDTMIG calls it "Laboratory Test Results". CORE-000272 compares --CAT
# against that label, so reading the study's own label answers a different
# question and missed the violation CDISC's engine reports.
#
#   python data-raw/dump_dataset_labels.py   # writes data-raw/dataset_labels.csv
#   Rscript data-raw/dataset_labels.R

csv_path <- file.path("data-raw", "dataset_labels.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_dataset_labels.py",
    call. = FALSE
  )
}

dataset_labels <- utils::read.csv(csv_path, stringsAsFactors = FALSE,
                                  colClasses = "character")

stopifnot(
  nrow(dataset_labels) > 0,
  all(c("standard", "version", "domain", "label") %in% names(dataset_labels)),
  !any(is.na(dataset_labels$label)),
  all(nzchar(dataset_labels$label)),
  # The divergence this table exists for. If these two ever collapse to the
  # same string the table has been extracted from the wrong field.
  identical(
    dataset_labels$label[dataset_labels$standard == "sdtmig" &
                           dataset_labels$version == "3-4" &
                           dataset_labels$domain == "LB"],
    "Laboratory Test Results"
  ),
  identical(
    dataset_labels$label[dataset_labels$standard == "sendig" &
                           dataset_labels$version == "3-1-1" &
                           dataset_labels$domain == "LB"],
    "Laboratory"
  )
)

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(dataset_labels, file.path("inst", "extdata", "dataset_labels.rds"))
cat(sprintf(
  "Wrote inst/extdata/dataset_labels.rds: %d rows across %d standards\n",
  nrow(dataset_labels), length(unique(dataset_labels$standard))
))

# Regenerates inst/extdata/ct_packages.rds: which CDISC Controlled
# Terminology packages exist, as (package_type, package_date) pairs.
#
# The DATES only, deliberately - not the terminology. The full CT term data
# in the source cache is ~438 MB across 206 files, which is a separate data
# package's problem, not something to bundle into a CRAN submission. The
# date list is a few hundred bytes and is all `valid_codelist_dates` needs:
# that operation checks whether a study cites a CT version CDISC actually
# published (CORE-000761 flags a TS record whose TSVCDVER is not a real
# package date).
#
# Operations that need the terms THEMSELVES (codelist_terms,
# get_codelist_attributes) remain unimplemented for the same size reason,
# and the rules using them are reported as skipped rather than guessed at.
#
# Source: cdisc-org/cdisc-rules-engine's own bundled cache, which that
# MIT-licensed, CDISC-published repository commits directly to git. NO CDISC
# API is contacted, at build or run time. data-raw/dump_ct_packages.py is
# the extraction step; both run at build time only.

csv_path <- file.path("data-raw", "ct_packages.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_ct_packages.py",
    call. = FALSE
  )
}

ct_packages <- utils::read.csv(csv_path, stringsAsFactors = FALSE, colClasses = "character")

stopifnot(
  nrow(ct_packages) > 0,
  all(c("package_type", "package_date") %in% names(ct_packages)),
  # The two standards the bundled rules actually reference.
  "SDTM" %in% ct_packages$package_type,
  "SEND" %in% ct_packages$package_type,
  # Dates must be ISO, since rules compare them as strings against study data.
  all(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", ct_packages$package_date))
)

saveRDS(ct_packages, file.path("inst", "extdata", "ct_packages.rds"), compress = "xz")

cat(sprintf(
  "Wrote inst/extdata/ct_packages.rds: %d packages across %d types\n",
  nrow(ct_packages), length(unique(ct_packages$package_type))
))

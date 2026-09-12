# Regenerates inst/extdata/ct_codelists.rds: every CDISC Controlled Terminology
# package, reduced to what conformance actually needs.
#
#   python data-raw/dump_ct_codelists.py   # writes data-raw/ct_codelists.csv
#   Rscript data-raw/ct_codelists.R
#
# One row per (package, codelist), with the codelist's own code and submission
# value, whether it is extensible, and its terms' submission values and codes.
# See data-raw/dump_ct_codelists.py for why preferred terms are left out and
# why every package is kept rather than the most recent few.
#
# Compressed with xz, not the default gzip. Consecutive CT releases are nearly
# identical and xz's large window collapses that repetition: the same data is
# 0.95 MB gzipped and 0.54 MB xz'd, and xz costs nothing to read back here
# (both load in about a tenth of a second).

csv_path <- file.path("data-raw", "ct_codelists.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_ct_codelists.py",
    call. = FALSE
  )
}

ct_codelists <- utils::read.csv(csv_path, stringsAsFactors = FALSE,
                                colClasses = "character")

# A codelist with no submission value cannot be looked up by name, and one with
# no terms answers every "is this value in the codelist" question with FALSE -
# which would report every value in the column as a violation.
ct_codelists <- ct_codelists[nzchar(ct_codelists$codelist), ]

n_terms <- lengths(strsplit(ct_codelists$term_values, "\x1f"))

stopifnot(
  nrow(ct_codelists) > 0,
  all(c("package", "codelist_code", "codelist", "extensible",
        "term_values", "term_codes") %in% names(ct_codelists)),
  # Both standards coreval evaluates must be present.
  any(startsWith(ct_codelists$package, "sdtmct-")),
  any(startsWith(ct_codelists$package, "sendct-")),
  # Terms are the whole point. An extraction that produced rows but no terms
  # would look healthy and report every value as invalid.
  sum(n_terms) > 1e6,
  # Values and codes must line up per term, or a `returntype: code` rule would
  # answer with the wrong codes.
  identical(n_terms, lengths(strsplit(ct_codelists$term_codes, "\x1f"))),
  # The extensible flag decides whether a sponsor's own value is a violation,
  # so both states have to have survived as usable strings.
  all(ct_codelists$extensible %in% c("True", "False")),
  # Terminology genuinely differs between releases - this is why every package
  # is kept - so a build that collapsed them all to one answer is broken.
  !identical(
    ct_codelists$term_values[ct_codelists$package == "sdtmct-2026-03-27" &
                               ct_codelists$codelist == "SEX"],
    ct_codelists$term_values[ct_codelists$package == "sdtmct-2014-09-26" &
                               ct_codelists$codelist == "SEX"]
  )
)

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
out <- file.path("inst", "extdata", "ct_codelists.rds")
saveRDS(ct_codelists, out, compress = "xz")

cat(sprintf(
  "Wrote %s: %d codelists across %d packages, %d terms, %.2f MB\n",
  out, nrow(ct_codelists), length(unique(ct_codelists$package)),
  sum(n_terms), file.size(out) / 1e6
))

# Regenerates inst/extdata/ct_pref_terms.rds: the preferred term of every CDISC
# Controlled Terminology term, keyed the same way as ct_codelists.rds.
#
#   python data-raw/dump_ct_codelists.py   # writes both CSVs in one pass
#   Rscript data-raw/ct_pref_terms.R
#
# A separate file rather than a column of ct_codelists.rds. 59 rules ask for a
# preferred term, so it has to ship, but folding it in takes the loaded object
# from 16.1 to 35.2 MB and no rule coreval bundles today needs one. Split out it
# is 0.44 MB installed and loads only when a rule reaches for it, since
# ct_pref_terms() reads it lazily on first use the way ct_codelists() does.
#
# Term order is the order ct_codelists.rds uses, so the Nth preferred term
# belongs to the Nth code of that codelist. The single-pass dump is what
# guarantees that, and the alignment check below is what proves it.

csv_path <- file.path("data-raw", "ct_pref_terms.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_ct_codelists.py",
    call. = FALSE
  )
}

ct_pref_terms <- utils::read.csv(csv_path, stringsAsFactors = FALSE,
                                 colClasses = "character")
codelists <- readRDS(file.path("inst", "extdata", "ct_codelists.rds"))

# ct_codelists.R drops the codelists with no submission value; drop the same
# ones here, or the two tables disagree about which rows exist.
key <- paste(ct_pref_terms$package, ct_pref_terms$codelist_code)
ct_pref_terms <- ct_pref_terms[
  key %in% paste(codelists$package, codelists$codelist_code),
]

n_terms <- lengths(strsplit(codelists$term_codes, "\x1f"))
mine <- lengths(strsplit(ct_pref_terms$term_pref_terms, "\x1f"))

stopifnot(
  nrow(ct_pref_terms) == nrow(codelists),
  all(c("package", "codelist_code", "term_pref_terms") %in% names(ct_pref_terms)),
  # Same rows in the same order, so a match() on one table indexes the other.
  identical(paste(ct_pref_terms$package, ct_pref_terms$codelist_code),
            paste(codelists$package, codelists$codelist_code)),
  # One preferred term per code. A short field would silently pair a code with
  # another term's preferred term, which is worse than having none at all.
  identical(mine, n_terms),
  # The point of the file. A build that produced rows of empty strings would
  # look healthy and answer every pref_term lookup with a blank.
  sum(nzchar(unlist(strsplit(ct_pref_terms$term_pref_terms, "\x1f")))) > 1e6
)

out <- file.path("inst", "extdata", "ct_pref_terms.rds")
saveRDS(ct_pref_terms, out, compress = "xz")

cat(sprintf(
  "Wrote %s: %d codelists across %d packages, %.2f MB\n",
  out, nrow(ct_pref_terms), length(unique(ct_pref_terms$package)),
  file.size(out) / 1e6
))

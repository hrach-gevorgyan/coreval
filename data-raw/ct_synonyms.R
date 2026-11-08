# Regenerates inst/extdata/ct_synonyms.rds: the synonyms of every term of every
# EXTENSIBLE CDISC Controlled Terminology codelist, keyed the same way as
# ct_codelists.rds.
#
#   python data-raw/dump_ct_codelists.py   # writes all three CSVs in one pass
#   Rscript data-raw/ct_synonyms.R
#
# One rule reads it: CORE 1.0's CORE-002117 asks whether a term a define adds
# to an extensible codelist is already a synonym of one of its terms. Only
# extensible codelists can take sponsor terms, so only theirs are kept: 0.27 MB
# installed, against 0.49 MB for every codelist. Loaded lazily by ct_synonyms()
# on first use, so a study whose rules never ask costs nothing.
#
# Term order is the order ct_codelists.rds uses, so the Nth synonym field
# belongs to the Nth term of that codelist. The single-pass dump guarantees
# that; the alignment check below proves it.

csv_path <- file.path("data-raw", "ct_synonyms.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_ct_codelists.py",
    call. = FALSE
  )
}

ct_synonyms <- utils::read.csv(csv_path, stringsAsFactors = FALSE,
                               colClasses = "character")
codelists <- readRDS(file.path("inst", "extdata", "ct_codelists.rds"))

# ct_codelists.R drops the codelists with no submission value; drop the same.
key <- paste(ct_synonyms$package, ct_synonyms$codelist_code)
codelist_key <- paste(codelists$package, codelists$codelist_code)
ct_synonyms <- ct_synonyms[key %in% codelist_key, ]
key <- paste(ct_synonyms$package, ct_synonyms$codelist_code)
at <- match(key, codelist_key)

n_terms <- lengths(strsplit(codelists$term_codes[at], "\x1f"))
# strsplit drops a trailing empty field, so count separators instead: a
# codelist whose last term has no synonym still has one field per term.
fields <- function(x) ifelse(nzchar(x) | n_terms > 0, lengths(regmatches(x, gregexpr("\x1f", x))) + 1L, 0L)
mine <- fields(ct_synonyms$term_synonyms)

stopifnot(
  !anyDuplicated(key),
  !anyNA(at),
  # Only extensible codelists, as the dump intends.
  all(codelists$extensible[at] %in% c("True", "TRUE", "true")),
  # One synonym field per term, or a synonym would land on the wrong term.
  identical(as.integer(mine), as.integer(n_terms)),
  # The point of the file. A build of empty fields would look healthy and let
  # every synonym duplicate through.
  sum(nzchar(unlist(strsplit(ct_synonyms$term_synonyms, "\x1f")))) > 1e5
)

out <- file.path("inst", "extdata", "ct_synonyms.rds")
saveRDS(ct_synonyms, out, compress = "xz")

cat(sprintf(
  "Wrote %s: %d codelists across %d packages, %.2f MB\n",
  out, nrow(ct_synonyms), length(unique(ct_synonyms$package)),
  file.size(out) / 1e6
))

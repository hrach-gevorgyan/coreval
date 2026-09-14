# Does coreval's USDM reader produce the same tables CDISC's own service does?
#
#   python tests/conformance/dump_usdm_tables.py <study.json> <ref-dir>
#   Rscript tests/conformance/compare_usdm_reader.R <study.json> <ref-dir>
#
# Reports, per entity: whether it exists on both sides, whether the record
# count matches, whether the columns match, and whether every cell matches.
#
# Why this exists: no CDISC fixture pairs a USDM document with the tables it
# should flatten to. The Record Data fixtures ship only tables, the JSONata
# fixtures ship only documents. Without a pairing, a reader could be written,
# could look right, and could be wrong in a way nothing would catch, which is
# this package's characteristic bug. dump_usdm_tables.py makes the pairing by
# running the reference, and this grades against it.
#
# Dev tooling only. Not part of the package, not run by R CMD check, and
# Rbuildignored with the rest of tests/conformance.

devtools::load_all(quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: compare_usdm_reader.R <study.json> <ref-dir>", call. = FALSE)
}
document <- args[[1]]
ref_dir <- args[[2]]

study <- read_study(dirname(document))
mine <- study$datasets

ref_files <- Sys.glob(file.path(ref_dir, "*.csv"))
ref_files <- ref_files[basename(ref_files) != "_datasets.csv"]
ref_names <- tools::file_path_sans_ext(basename(ref_files))

# coreval upper-cases dataset names, the reference keeps the entity's own
# casing. Compare on the upper-cased name; a clash between two entities that
# differ only in case would show up as a count mismatch rather than silently.
names(ref_files) <- toupper(ref_names)

only_mine <- setdiff(names(mine), names(ref_files))
only_ref <- setdiff(names(ref_files), names(mine))
cat(sprintf("entities: mine %d, reference %d\n", length(mine), length(ref_files)))
if (length(only_mine)) cat("  only mine     :", paste(only_mine, collapse = ", "), "\n")
if (length(only_ref)) cat("  only reference:", paste(only_ref, collapse = ", "), "\n")

# The reference writes every cell as text, so both sides are compared as text.
# A blank and an absent value are the same statement in a CSV and cannot be
# told apart after the round trip, so they are folded together here rather than
# pretending the file said which it was.
as_text <- function(x) {
  out <- as.character(x)
  out[is.na(out)] <- ""
  # A logical column round-trips through Python as True/False.
  if (is.logical(x)) out <- ifelse(out == "TRUE", "True", ifelse(out == "FALSE", "False", out))
  # A whole number written by pandas has no trailing ".0"; R may add one.
  out <- sub("^(-?[0-9]+)\\.0$", "\\1", out)
  out
}

problems <- 0L
checked <- 0L
for (name in intersect(names(mine), names(ref_files))) {
  # read.csv, not fread: fread does not collapse a doubled quote inside a
  # quoted field when the field holds no separator, which is the bug read.R
  # already carries a repair for. These values are full of quoted XHTML.
  ref <- utils::read.csv(ref_files[[name]], colClasses = "character",
                         check.names = FALSE, na.strings = character(0))
  got <- mine[[name]]$data
  checked <- checked + 1L
  if (nrow(ref) != nrow(got)) {
    cat(sprintf("  %-34s ROWS mine %d, reference %d\n", name, nrow(got), nrow(ref)))
    problems <- problems + 1L
    next
  }
  missing_cols <- setdiff(names(ref), names(got))
  extra_cols <- setdiff(names(got), names(ref))
  if (length(missing_cols) || length(extra_cols)) {
    cat(sprintf("  %-34s COLUMNS missing {%s} extra {%s}\n", name,
                paste(utils::head(missing_cols, 4), collapse = ","),
                paste(utils::head(extra_cols, 4), collapse = ",")))
    problems <- problems + 1L
    next
  }
  if (!identical(names(ref), names(got))) {
    cat(sprintf("  %-34s COLUMN ORDER differs\n", name))
    problems <- problems + 1L
    next
  }
  bad <- character(0)
  for (column in names(ref)) {
    left <- as_text(got[[column]])
    right <- as_text(ref[[column]])
    if (!identical(left, right)) {
      first <- which(left != right)[[1]]
      bad <- c(bad, sprintf("%s[row %d] mine '%s' ref '%s'", column, first,
                            left[[first]], right[[first]]))
    }
  }
  if (length(bad)) {
    cat(sprintf("  %-34s %d column(s) differ; %s\n", name, length(bad), bad[[1]]))
    problems <- problems + 1L
  }
}

cat(sprintf("\n%d entities compared, %d with differences, %d only on one side\n",
            checked, problems, length(only_mine) + length(only_ref)))

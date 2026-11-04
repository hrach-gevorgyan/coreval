# Parse the CORE 1.0 rules in a core-contributor checkout into the shape of
# coreval's bundled rules, so the conformance harness can grade coreval's
# engine on the 1.0 rule definitions themselves rather than on the copies it
# bundles.
#
#   Rscript tests/conformance/extract_v1_rules.R data-raw/upstream/core-contributor <out.rds>
#   COREVAL_CONFORMANCE_RULES=<out.rds> \
#     Rscript tests/conformance/run_conformance.R data-raw/upstream/core-contributor
#
# The parsing is data-raw/extract_rules.R's own extract_one(), taken from that
# file rather than copied, so a 1.0 rule is read exactly as a bundled rule is.
# A rule file that cannot be parsed is reported and left out; the harness then
# lists it as unreadable.
#
# Dev tooling only.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("usage: extract_v1_rules.R <core-contributor checkout> <out.rds>", call. = FALSE)
}
root <- file.path(args[[1]], "sdtm_rules")
if (!dir.exists(root)) stop("no sdtm_rules/ under ", args[[1]], call. = FALSE)

# Everything in extract_rules.R before it starts reading cdisc-open-rules: the
# YAML handlers, the flag normalisation and extract_one(). Not the git call
# that records that repository's commit, which would fail or mislead here.
src <- readLines(file.path("data-raw", "extract_rules.R"))
stop_at <- grep("^published_files <- ", src) - 1L
if (length(stop_at) != 1 || stop_at < 1) {
  stop("could not find where extract_rules.R starts reading files", call. = FALSE)
}
helpers <- src[seq_len(stop_at)]
helpers <- helpers[!grepl("^sha <- ", helpers)]
eval(parse(text = helpers), envir = globalenv())

files <- sort(Sys.glob(file.path(root, "*", "*.yml")))
failed <- character(0)
rules <- lapply(files, function(f) {
  tryCatch(suppressWarnings(extract_one(f, "core_contributor")), error = function(e) {
    failed <<- c(failed, sprintf("%s: %s", basename(dirname(f)), conditionMessage(e)))
    NULL
  })
})
rules <- Filter(Negate(is.null), rules)
names(rules) <- vapply(rules, `[[`, character(1), "id")
if (anyDuplicated(names(rules))) {
  stop("duplicate rule ids: ", paste(unique(names(rules)[duplicated(names(rules))]), collapse = ", "), call. = FALSE)
}
sha <- system2("git", c("-C", args[[1]], "rev-parse", "HEAD"), stdout = TRUE)
saveRDS(list(upstream_sha = sha, rules = rules), args[[2]])
cat(sprintf("%d rule files, %d parsed, %d could not be:\n", length(files), length(rules), length(failed)))
for (f in failed) cat("  ", f, "\n")

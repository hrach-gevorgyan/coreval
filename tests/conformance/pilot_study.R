# Check CDISC's pilot submission with coreval, the way the reference engine
# is run on it, and write the findings out for compare_pilot.py.
#
#   Rscript tests/conformance/pilot_study.R <folder of pilot .xpt files> <out-dir>
#
# The pilot is CDISC's own complete SDTM submission (CDISCPILOT01), published
# in cdisc-org/sdtm-adam-pilot-project under CDISC's terms of use, which do not
# allow it to be redistributed. So it is never committed here: clone it into
# data-raw/upstream/, which is ignored. docs/REAL-STUDY.md has the steps.
#
# The settings match the engine run described there, so the two reports can be
# compared rule by rule: SDTMIG 3.2 (the pilot is 3.1.2, which the engine has
# no rules for), use case INDH, and one named Controlled Terminology package,
# because the pilot's TS declares none. max_records is lifted so no finding is
# cut from the comparison.
#
# Dev tooling only. Not part of the package, not run by R CMD check, and
# Rbuildignored with the rest of tests/conformance.

devtools::load_all(quiet = TRUE)
options(coreval.progress = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: pilot_study.R <folder of pilot .xpt files> <out-dir>", call. = FALSE)
}
pilot <- args[[1]]
out <- args[[2]]
dir.create(out, showWarnings = FALSE, recursive = TRUE)

elapsed <- system.time(
  result <- check_study(pilot, standard = "SDTMIG", version = "3.2",
                        use_case = "INDH", ct_package = "sdtmct-2014-09-26",
                        max_records = 1e7)
)[["elapsed"]]

data.table::fwrite(unique(result$findings[, c("rule_id", "Dataset", "Record")]),
                   file.path(out, "coreval_findings.csv"))
data.table::fwrite(result$skipped, file.path(out, "coreval_skipped.csv"))
rules <- list_rules()
data.table::fwrite(rules[, c("id", "source")], file.path(out, "coreval_rules.csv"))

cat(sprintf("coreval: %.1fs, %d checks run, %d skipped, %d rules with findings\n",
            elapsed, attr(result, "checks_run"), nrow(result$skipped),
            length(unique(result$findings$rule_id))))
cat("wrote", out, "\n")

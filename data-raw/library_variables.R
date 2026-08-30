# Regenerates inst/extdata/library_variables.rds: per standard, per version,
# per domain, per variable - the Core designation (Req/Exp/Perm), ordinal
# position, label, role and data type the CDISC Library assigns.
#
# Supersedes the earlier SDTMIG-only sdtmig_variables.rds. Two things that
# table couldn't do:
#   * SENDIG. sdtmig_variables_for() had to return NULL for any non-SDTMIG
#     study, so rules needing required/expected variables silently could not
#     be evaluated for SEND data - which is most of the bundled rule set.
#   * label / role / type. Several rules compare a dataset's own variable
#     metadata against the Library's (library_variable_label,
#     library_variable_role, library_variable_data_type). Without these the
#     comparison degraded to a literal string and flagged every variable, so
#     those rules had to be refused outright.
#
# Source: cdisc-org/cdisc-rules-engine's own bundled cache
# (resources/cache/variables_metadata.pkl), which that MIT-licensed,
# CDISC-published repository commits directly to git. NO CDISC API is
# contacted, at build time or at run time - the API is only used by that
# project's own cache-refresh path, which needs a key and is not used here.
# data-raw/dump_library_variables.py is the one-time unpickle step; re-run it
# only when the clone is refreshed. Both scripts run at build time only.
#
# Trap this data revealed: a CORE test case that LOOKS SDTM-flavoured is not
# necessarily SDTMIG - its `_env` file can declare SENDIG or another standard
# entirely (CORE-000355's EX fixture is SENDIG 3.1). Consumers MUST check the
# study's declared standard rather than assuming SDTMIG.

csv_path <- file.path("data-raw", "library_variables.csv")
if (!file.exists(csv_path)) {
  stop(
    "Missing ", csv_path, ".\n",
    "Regenerate it first:  python data-raw/dump_library_variables.py",
    call. = FALSE
  )
}

library_variables <- utils::read.csv(csv_path, stringsAsFactors = FALSE, colClasses = "character")

# A variable with no Core designation carries no requirement to check, and a
# blank domain is unusable as a lookup key.
library_variables <- library_variables[
  nzchar(library_variables$domain) & nzchar(library_variables$variable),
]

library_variables$ordinal <- suppressWarnings(as.integer(library_variables$ordinal))

stopifnot(
  nrow(library_variables) > 0,
  !anyNA(library_variables$domain),
  !anyNA(library_variables$variable),
  # The two standards the bundled rules actually need must both be present -
  # a silently SDTMIG-only table is exactly the bug this replaces.
  "sdtmig" %in% library_variables$standard,
  "sendig" %in% library_variables$standard
)

saveRDS(
  library_variables,
  file.path("inst", "extdata", "library_variables.rds"),
  compress = "xz"
)

cat(sprintf(
  "Wrote inst/extdata/library_variables.rds: %d rows, standards: %s\n",
  nrow(library_variables),
  paste(sort(unique(library_variables$standard)), collapse = ", ")
))

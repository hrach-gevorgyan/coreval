# Regenerates inst/extdata/sdtmig_variables.rds: per SDTMIG version, per
# domain, per variable - the exact Core designation (Req/Exp/Perm) and
# ordinal position the CDISC Library assigns. Used by the
# `required_variables`/`expected_variables` Operations types, which need
# genuinely per-domain (not per-CLASS) data - contrast with
# sdtm_model_variables.rds, the abstract SDTM Model's class-level variable
# list used by `get_model_column_order`.
#
# Confirmed this genuinely differs by SDTMIG version for the same domain/
# variable (a variable's Core status is not fixed across editions) - unlike
# sdtm_domain_classes.rds's domain-to-CLASS mapping, which really is stable
# enough to treat as a version-independent superset. All 5 non-appendix
# SDTMIG versions the source cache has are included (3.1.2, 3.1.3, 3.2, 3.3,
# 3.4); the appendix variants (ap-1-0, md-1-0/1-1) are out of scope for now.
#
# Like sdtm_domain_classes.R / sdtm_model_variables.R, this is NOT extracted
# from cdisc-org/cdisc-open-rules (that repo has no Library metadata, only
# the CORE rules themselves). It's machine-extracted from
# cdisc-org/cdisc-rules-engine's own bundled cache
# (resources/cache/variables_metadata.pkl, keys
# "library_variables_metadata/sdtmig/<version>"), which that MIT-licensed,
# CDISC-published repository commits directly to git. It ultimately
# originates from the CDISC Library API's SDTMIG dataset-variable metadata.
# sdtmig_variables.csv (in this directory) is the one-time Python-unpickled
# dump this script reads; regenerate it from a fresh clone of
# cdisc-rules-engine only if the cache is ever refreshed - this script itself
# only runs at build time, never at package install/load.
#
# Trap this data revealed (see CLAUDE.md's Known Traps): a CORE test case
# that LOOKS SDTM-flavored is not necessarily SDTMIG - its `.env` file can
# declare SENDIG or another standard entirely (confirmed for CORE-000355's
# own EX fixture, which is SENDIG 3.1). Consumers of this table MUST check
# the study's own declared standard (see read_env_standard() in R/read.R)
# before assuming SDTMIG applies, rather than defaulting silently.

sdtmig_variables <- read.csv(file.path("data-raw", "sdtmig_variables.csv"), stringsAsFactors = FALSE)
sdtmig_variables <- sdtmig_variables[sdtmig_variables$core != "", ]

stopifnot(nrow(sdtmig_variables) > 0, !anyNA(sdtmig_variables$domain), !anyNA(sdtmig_variables$variable))

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(sdtmig_variables, file.path("inst", "extdata", "sdtmig_variables.rds"))

cat(sprintf(
  "Wrote %d rows across %d SDTMIG versions and %d domains\n",
  nrow(sdtmig_variables), length(unique(sdtmig_variables$version)), length(unique(sdtmig_variables$domain))
))

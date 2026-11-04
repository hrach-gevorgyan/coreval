# Regenerates inst/extdata/core1_reference.rds: two reference tables CORE 1.0's
# engine ships for its own rules to read as if they were datasets
# (data_service/startup/populate_helper_tables.py in
# verisianHQ/cdisc-rules-engine):
#
#   cg_taugs                  the FDA-supported Therapeutic Area User Guides
#   fda_submission_standards  the FDA Data Standards Catalog rows
#   countries_iso3166         ISO 3166-1 country names and codes
#   countries_genc            GENC country names and codes
#
# CORE-002050 and CORE-002057 check TSVAL against them. Both come from that
# repository's resources/helper_data/, under the MIT notice reproduced in
# inst/COPYRIGHTS, at the commit recorded in data-raw/UPSTREAM_SHA_CORE1_ENGINE.
#
#   git clone https://github.com/verisianHQ/cdisc-rules-engine data-raw/upstream/verisian-engine
#   Rscript data-raw/core1_reference.R

engine <- file.path("data-raw", "upstream", "verisian-engine")
helper <- file.path(engine, "resources", "helper_data")
read_table <- function(file) {
  rows <- jsonlite::fromJSON(file.path(helper, file), simplifyVector = TRUE)
  data.table::as.data.table(rows)
}
# The country lists the get_countries operation draws on are written out in
# sql_operations/get_countries.py rather than shipped as data.
read_countries <- function(list_name) {
  src <- readLines(file.path(engine, "cdisc_rules_engine", "sql_operations", "get_countries.py"),
                   encoding = "UTF-8", warn = FALSE)
  start <- grep(paste0("^", list_name, " = [[]"), src)
  end <- start + which(src[(start + 1):length(src)] == "]")[1]
  body <- src[(start + 1):(end - 1)]
  pick <- function(field) sub(paste0('.*"', field, '": "([^"]*)".*'), "\\1", body)
  data.table::data.table(country_name = pick("country_name"), alpha_2 = pick("alpha_2"),
                         alpha_3 = pick("alpha_3"))
}
core1_reference <- list(
  cg_taugs = read_table("taugs.json"),
  fda_submission_standards = read_table("fda-submission-standards.json"),
  countries_iso3166 = read_countries("ISO_3166_COUNTRY_CODES"),
  countries_genc = read_countries("GENC_COUNTRY_CODES")
)
stopifnot(
  identical(names(core1_reference$cg_taugs), "fda_guides"),
  all(c("standard", "property", "property_version") %in% names(core1_reference$fda_submission_standards)),
  nrow(core1_reference$cg_taugs) > 0,
  nrow(core1_reference$fda_submission_standards) > 0,
  nrow(core1_reference$countries_iso3166) > 200, nrow(core1_reference$countries_genc) > 200,
  all(nchar(core1_reference$countries_iso3166$alpha_3) == 3),
  all(nchar(core1_reference$countries_genc$alpha_3) == 3)
)
saveRDS(core1_reference, file.path("inst", "extdata", "core1_reference.rds"), compress = "xz")
sha <- system2("git", c("-C", engine, "rev-parse", "HEAD"), stdout = TRUE)
writeLines(sha, file.path("data-raw", "UPSTREAM_SHA_CORE1_ENGINE"))
cat(paste(names(core1_reference), vapply(core1_reference, nrow, integer(1)), collapse = ", "),
    "rows; engine", sha, "\n")

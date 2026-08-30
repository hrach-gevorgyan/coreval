.datatable.aware <- TRUE

# data.table's special in-`[.data.table` symbol, used in operations.R's
# record_count grouping - not a real global, just needs declaring so
# R CMD check doesn't flag it as an undefined variable.
utils::globalVariables(".N")

.coreval_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  path <- system.file("extdata", "rules.rds", package = pkgname)
  .coreval_env$data <- readRDS(path)

  domain_classes_path <- system.file("extdata", "sdtm_domain_classes.rds", package = pkgname)
  .coreval_env$domain_classes <- readRDS(domain_classes_path)
}

.datatable.aware <- TRUE

# data.table's special in-`[.data.table` symbol, used in operations.R's
# record_count grouping - not a real global, just needs declaring so
# R CMD check doesn't flag it as an undefined variable.
utils::globalVariables(".N")

.coreval_env <- new.env(parent = emptyenv())

#' Load bundled rules and SDTM domain/class reference data into the package environment
#' @param libname,pkgname Standard `.onLoad` arguments.
#' @return `NULL`, invisibly (called for its side effect).
#' @noRd
.onLoad <- function(libname, pkgname) {
  path <- system.file("extdata", "rules.rds", package = pkgname)
  .coreval_env$data <- readRDS(path)

  domain_classes_path <- system.file("extdata", "sdtm_domain_classes.rds", package = pkgname)
  .coreval_env$domain_classes <- readRDS(domain_classes_path)

  model_variables_path <- system.file("extdata", "sdtm_model_variables.rds", package = pkgname)
  .coreval_env$model_variables <- readRDS(model_variables_path)

  library_variables_path <- system.file("extdata", "library_variables.rds", package = pkgname)
  .coreval_env$library_variables <- readRDS(library_variables_path)

  ct_packages_path <- system.file("extdata", "ct_packages.rds", package = pkgname)
  .coreval_env$ct_packages <- readRDS(ct_packages_path)
}

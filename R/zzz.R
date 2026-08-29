.datatable.aware <- TRUE

.coreval_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  path <- system.file("extdata", "rules.rds", package = pkgname)
  .coreval_env$data <- readRDS(path)

  domain_classes_path <- system.file("extdata", "sdtm_domain_classes.rds", package = pkgname)
  .coreval_env$domain_classes <- readRDS(domain_classes_path)
}

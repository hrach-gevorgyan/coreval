.coreval_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  path <- system.file("extdata", "rules.rds", package = pkgname)
  .coreval_env$data <- readRDS(path)
}

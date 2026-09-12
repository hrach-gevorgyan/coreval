# Put data.table's thread count back, so an interactive devtools::test()
# does not leave the session throttled.
old <- getOption("coreval.test.old_dtthreads")
if (!is.null(old)) {
  data.table::setDTthreads(old)
  options(coreval.test.old_dtthreads = NULL)
}

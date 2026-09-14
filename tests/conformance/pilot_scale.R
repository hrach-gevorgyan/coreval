# Check CDISC's pilot study at k times its size, for time and peak memory.
#
#   Rscript tests/conformance/pilot_scale.R <folder of pilot .xpt files> <k>
#
# Every dataset keyed by subject is repeated k times under new USUBJIDs, so
# keys stay unique and the copies add no findings of their own; trial design
# datasets (TA, TE, TI, TS, TV) are one per study and stay as they are. One
# scale per process, so each peak belongs to that scale alone.
#
# Peak memory is the operating system's figure for the whole R process: the
# peak working set on Windows, VmHWM on Linux.
#
# Dev tooling only. Not part of the package, not run by R CMD check, and
# Rbuildignored with the rest of tests/conformance. The pilot data is not in
# this repository; docs/REAL-STUDY.md says where to get it.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("usage: Rscript tests/conformance/pilot_scale.R <pilot xpt folder> <k>")
}
suppressMessages(devtools::load_all(quiet = TRUE))
options(coreval.progress = FALSE)
k <- as.integer(args[[2]])

peak_mb <- function() {
  if (.Platform$OS.type == "windows") {
    out <- system2("powershell", c("-NoProfile", "-Command", shQuote(sprintf(
      "(Get-Process -Id %d).PeakWorkingSet64", Sys.getpid()
    ))), stdout = TRUE)
    return(round(as.numeric(out[length(out)]) / 1024^2))
  }
  hwm <- grep("^VmHWM", readLines("/proc/self/status"), value = TRUE)
  round(as.numeric(gsub("[^0-9]", "", hwm)) / 1024)
}

t_read <- system.time(study <- read_study(args[[1]]))[["elapsed"]]
if (k > 1) {
  for (d in names(study$datasets)) {
    dt <- study$datasets[[d]]$data
    if (!("USUBJID" %in% names(dt))) next
    study$datasets[[d]]$data <- data.table::rbindlist(lapply(seq_len(k), function(i) {
      x <- data.table::copy(dt)
      if (i > 1) {
        suffix <- sprintf("-R%02d", i)
        x[, USUBJID := ifelse(nzchar(USUBJID), paste0(USUBJID, suffix), USUBJID)]
        if ("SUBJID" %in% names(x)) x[, SUBJID := paste0(SUBJID, suffix)]
        if ("RELID" %in% names(x)) x[, RELID := paste0(RELID, suffix)]
      }
      x
    }))
  }
}
rows <- sum(vapply(study$datasets, function(d) nrow(d$data), integer(1)))
invisible(gc())
mem_loaded <- peak_mb()

t_check <- system.time(result <- check_study(study))[["elapsed"]]
cat(sprintf(
  "k=%d rows=%s read=%.0fs check=%.0fs peak_after_load=%dMB peak=%dMB checks=%s findings=%s\n",
  k, format(rows, big.mark = ","), t_read, t_check, mem_loaded, peak_mb(),
  attr(result, "checks_run"), format(nrow(result$findings), big.mark = ",")
))

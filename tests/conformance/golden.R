# Record exactly what check_study() answers, and later prove a change left it
# alone.
#
#   Rscript tests/conformance/golden.R record <out.rds> [<pilot xpt folder>]
#   Rscript tests/conformance/golden.R compare <before.rds> <after.rds>
#
# `record` runs check_study() on every test study in the rules clone (each
# data/ folder under Published, Deprecated and Unpublished) and, if given, on
# CDISC's pilot submission twice: with the settings docs/REAL-STUDY.md uses,
# and with no standard declared, so every rule runs. It keeps each whole
# result: every finding with every column, the skipped rules and their
# reasons, and the counts carried as attributes.
#
# `compare` reports every study whose result is not identical().
#
# Why this exists alongside run_conformance.R: the harness grades each rule on
# its own through evaluate_rule(), which never sees the per-run caches and
# plans check_study() builds, so a change to those can alter what a user gets
# while every rule still grades the same. It also grades pass or fail, and a
# rule can keep its grade while reporting different records. This compares
# the answers themselves.
#
# Dev tooling only. Not part of the package, not run by R CMD check, and
# Rbuildignored with the rest of tests/conformance. The recording holds pilot
# findings, so it is never committed: keep it outside the repository.

args <- commandArgs(trailingOnly = TRUE)
mode <- args[1]

if (identical(mode, "compare")) {
  a <- readRDS(args[2])
  b <- readRDS(args[3])
  missing <- setdiff(names(a), names(b))
  added <- setdiff(names(b), names(a))
  common <- intersect(names(a), names(b))
  differ <- common[!vapply(common, function(k) identical(a[[k]], b[[k]]), logical(1))]
  cat(sprintf("%d studies compared: %d identical, %d differ, %d only before, %d only after\n",
              length(common), length(common) - length(differ), length(differ),
              length(missing), length(added)))
  for (k in head(differ, 30)) {
    x <- a[[k]]
    y <- b[[k]]
    what <- if (inherits(x, "error") || inherits(y, "error")) {
      paste("error:", if (inherits(x, "error")) conditionMessage(x) else "-", "|",
            if (inherits(y, "error")) conditionMessage(y) else "-")
    } else {
      sprintf("findings %d -> %d%s, skipped %d -> %d", nrow(x$findings), nrow(y$findings),
              if (identical(x$findings, y$findings)) " (the same findings)" else "",
              nrow(x$skipped), nrow(y$skipped))
    }
    cat("  ", k, ":", what, "\n")
  }
  if (length(differ) || length(missing) || length(added)) quit(status = 1)
  quit(status = 0)
}

if (!identical(mode, "record") || length(args) < 2) {
  stop("usage: golden.R record <out.rds> [<pilot xpt folder>] | golden.R compare <a.rds> <b.rds>",
       call. = FALSE)
}
out <- args[2]
pilot <- if (length(args) >= 3) args[3] else NULL

root <- file.path("data-raw", "upstream", "cdisc-open-rules")
cases <- unlist(lapply(c("Published", "Deprecated", "Unpublished"), function(s) {
  d <- list.dirs(file.path(root, s), recursive = TRUE)
  d[basename(d) == "data"]
}))
cases <- sort(cases)

# Each result as check_study() returns it. An error is kept as the error, so a
# study that stops failing, or starts, shows up as a difference too.
run_one <- function(dir, ...) {
  tryCatch(check_study(dir, max_records = 1e7, include_deprecated = TRUE, usdm = TRUE, ...),
           error = function(e) simpleError(conditionMessage(e)))
}

started <- Sys.time()
workers <- as.integer(Sys.getenv("COREVAL_WORKERS", "12"))
cl <- parallel::makePSOCKcluster(workers)
on.exit(parallel::stopCluster(cl), add = TRUE)
parallel::clusterEvalQ(cl, {
  suppressMessages(devtools::load_all(quiet = TRUE))
  options(coreval.progress = FALSE)
  data.table::setDTthreads(1)
  NULL
})
timed_one <- function(dir) {
  t0 <- proc.time()[["elapsed"]]
  r <- run_one(dir)
  list(result = r, seconds = proc.time()[["elapsed"]] - t0)
}
parallel::clusterExport(cl, c("run_one", "timed_one"))
# In batches, so progress shows and the time each study took is kept: the
# slowest studies are where coreval's own speed problems show first.
results <- vector("list", length(cases))
seconds <- numeric(length(cases))
batches <- split(seq_along(cases), ceiling(seq_along(cases) / (workers * 20)))
for (b in batches) {
  got <- parallel::parLapplyLB(cl, cases[b], timed_one, chunk.size = 1)
  results[b] <- lapply(got, `[[`, "result")
  seconds[b] <- vapply(got, `[[`, numeric(1), "seconds")
  cat(sprintf("  %d/%d studies, %.0f s\n", max(b), length(cases),
              as.numeric(difftime(Sys.time(), started, units = "secs"))))
}
names(results) <- sub(paste0("^", root, "/"), "", cases)
cat(sprintf("%d test studies in %.0f s\n", length(cases),
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
timing <- data.frame(study = names(results), seconds = seconds)
timing <- timing[order(-timing$seconds), ]
utils::write.csv(timing, sub("\\.rds$", "_seconds.csv", out), row.names = FALSE)
cat("slowest:\n")
print(utils::head(timing, 10), row.names = FALSE)

if (!is.null(pilot)) {
  suppressMessages(devtools::load_all(quiet = TRUE))
  options(coreval.progress = FALSE)
  t0 <- Sys.time()
  results[["pilot, as in REAL-STUDY.md"]] <- run_one(
    pilot, standard = "SDTMIG", version = "3.2", use_case = "INDH",
    ct_package = "sdtmct-2014-09-26"
  )
  results[["pilot, no standard declared"]] <- run_one(pilot)
  cat(sprintf("pilot, both settings, in %.0f s\n",
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

saveRDS(results, out)
errors <- sum(vapply(results, inherits, logical(1), "error"))
cat(sprintf("recorded %d results (%d errors) to %s\n", length(results), errors, out))

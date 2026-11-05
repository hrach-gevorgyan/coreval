# Run the verification a change actually needs, and nothing more.
#
#   Rscript data-raw/verify.R docs      ~1s     prose only
#   Rscript data-raw/verify.R vignette  ~4s     + renders the vignette
#   Rscript data-raw/verify.R roxygen   ~4s     + regenerates man/
#   Rscript data-raw/verify.R code      ~20s    + the test suite
#   Rscript data-raw/verify.R rules     ~90s    + both conformance sweeps
#   Rscript data-raw/verify.R release   ~2m     URLs + R CMD check --as-cran
#
# Each level includes the ones above it.
#
# Why bother: the habit of running `devtools::test()` and then
# `devtools::check()` after every edit costs nearly two minutes, duplicates the
# test run (check runs the tests itself), and tells you nothing at all when the
# edit was to a Markdown file. Measured on this package:
#
#   check --as-cran  94s        test()        19s
#   conformance      32s        vignette       3s
#   document()        2s        load_all       1s
#
# What each level is for:
#
#   docs      Markdown outside vignettes/. Cannot affect the package. The one
#             real risk is a broken URL, and CRAN checks those at submission,
#             so that is a `release` concern rather than a per-edit one.
#   vignette  vignettes/*.Rmd runs real code and ships in the build.
#   roxygen   a change to #' comments. man/ must be regenerated or the docs
#             and the code disagree.
#   code      anything in R/. The suite is the fast, honest signal.
#   rules     operators, evaluation, scoping, bundled data. These can move a
#             rule's answer without moving a single test, which is why the
#             conformance sweep exists. Compare the scoreboard afterwards:
#             a status change you did not intend is the thing to catch.
#   release   before a CRAN submission, and before pushing anything that
#             touches DESCRIPTION, NAMESPACE or inst/.

levels <- c("docs", "vignette", "roxygen", "code", "rules", "release")
arg <- commandArgs(trailingOnly = TRUE)
level <- if (length(arg) == 0) "code" else arg[[1]]
if (!(level %in% levels)) {
  stop("level must be one of: ", paste(levels, collapse = ", "), call. = FALSE)
}
depth <- match(level, levels)
step <- function(name, n) cat(sprintf("\n[%d/%d] %s\n", n, depth, name))
started <- Sys.time()

step("prose", 1)
prose <- system2("Rscript", "data-raw/check_prose.R", stdout = TRUE, stderr = TRUE)
cat(paste(prose, collapse = "\n"), "\n")
prose_clean <- any(grepl("No tells found", prose))

if (depth >= 2) {
  step("vignette renders", 2)
  suppressMessages(devtools::load_all(quiet = TRUE))
  rmarkdown::render("vignettes/coreval.Rmd",
                    output_file = tempfile(fileext = ".html"), quiet = TRUE)
  # render() leaves an intermediate beside the source when knitting in place
  unlink("coreval.md")
  cat("ok\n")
}

if (depth >= 3) {
  step("man/ regenerated", 3)
  suppressMessages(devtools::document())
}

if (depth >= 4) {
  step("test suite", 4)
  devtools::test()
}

if (depth >= 5) {
  step("conformance sweeps", 5)
  # Two sweeps since CORE 1.0. CDISC's rule set against CDISC's test cases is
  # the guard for SEND, TIG and USDM; the shipped SDTM set against CORE 1.0's
  # test cases is the measure for SDTM. See tests/conformance/run_conformance.R.
  sweep <- function(upstream, board) {
    prior <- if (file.exists(board)) utils::read.csv(board, stringsAsFactors = FALSE) else NULL
    started <- Sys.time()
    status <- system2("Rscript", c("tests/conformance/run_conformance.R", upstream), stdout = NULL)
    # A sweep that failed leaves the previous scoreboard in place, and diffing
    # that against itself reported "no rule changed status". Refused instead.
    if (!identical(as.integer(status), 0L) || !file.exists(board) ||
          file.mtime(board) < started) {
      stop("the conformance sweep over ", upstream, " failed (exit status ", status,
           ") or did not rewrite ", board, call. = FALSE)
    }
    now <- utils::read.csv(board, stringsAsFactors = FALSE)
    cat("\n", basename(board), ": ", paste(names(table(now$status)), table(now$status), sep = " ",
                                           collapse = " / "), "\n", sep = "")
    if (is.null(prior)) {
      return(invisible(NULL))
    }
    # all = TRUE, so a rule added or removed upstream is listed too: an inner
    # merge left a new rule out of the diff, however it graded.
    merged <- merge(prior[c("id", "status", "reason")],
                    now[c("id", "status", "reason")], by = "id", all = TRUE,
                    suffixes = c("_before", "_after"))
    differs <- function(a, b) (is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
    added <- merged$id[is.na(merged$status_before)]
    removed <- merged$id[is.na(merged$status_after)]
    both <- merged[!is.na(merged$status_before) & !is.na(merged$status_after), ]
    moved <- both[differs(both$status_before, both$status_after), ]
    changed <- both[!differs(both$status_before, both$status_after) &
                      differs(both$reason_before, both$reason_after), ]
    if (length(added)) {
      cat("new rules:", length(added), "\n")
      for (id in added) cat(sprintf("  %s: %s\n", id, merged$status_after[merged$id == id]))
    }
    if (length(removed)) {
      cat("rules no longer present:", paste(removed, collapse = ", "), "\n")
    }
    if (nrow(moved) == 0 && nrow(changed) == 0) {
      cat("no rule changed status, and no failing rule changed its answer\n")
    } else {
      # A rule that keeps its status while its reported records move is the
      # case a pass rate cannot see, so it is reported alongside.
      if (nrow(moved)) {
        cat("status changes:\n")
        for (i in seq_len(nrow(moved))) {
          cat(sprintf("  %s: %s -> %s\n", moved$id[i],
                      moved$status_before[i], moved$status_after[i]))
        }
      }
      if (nrow(changed)) {
        cat("same status, different answer:", nrow(changed), "\n")
        for (i in seq_len(min(5, nrow(changed)))) cat("  ", changed$id[i], "\n")
      }
    }
  }
  sweep("data-raw/upstream/cdisc-open-rules", "tests/conformance/scoreboard.csv")
  sweep("data-raw/upstream/core-contributor", "tests/conformance/scoreboard_core1.csv")
}

if (depth >= 6) {
  # Before the check, because a dead link is the easiest way to earn a NOTE and
  # the slowest to notice. README links to files in docs/, which is
  # .Rbuildignored and so never in the tarball: those links MUST be absolute
  # GitHub URLs, and the docs they point at must already be pushed. Writing the
  # link before pushing the file gives a URL that is right about the future and
  # 404 today.
  step("URLs resolve", 6)
  if (requireNamespace("urlchecker", quietly = TRUE)) {
    bad <- try(urlchecker::url_check(), silent = TRUE)
    if (inherits(bad, "try-error")) {
      cat("invalid URLs. If they are docs/ links, push docs/ first.\n")
    } else {
      cat("all URLs resolve\n")
    }
  } else {
    cat("urlchecker not installed: install.packages(\"urlchecker\")\n")
  }

  step("R CMD check --as-cran", 7)
  print(devtools::check(args = c("--as-cran"), quiet = TRUE))
}

cat(sprintf("\n%s: %.0fs%s\n", level,
            as.numeric(difftime(Sys.time(), started, units = "secs")),
            if (prose_clean) "" else "  (prose has hits, see above)"))

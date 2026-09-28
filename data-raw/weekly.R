# Weekly upkeep: see what moved upstream, check everything, clean up.
#
#   Rscript data-raw/weekly.R              everything
#   Rscript data-raw/weekly.R --quick      skip CDISC's engine and R CMD check
#   Rscript data-raw/weekly.R --adopt      also move the rule and engine clones
#                                          to CDISC's latest and rebuild rules.rds
#   Rscript data-raw/weekly.R --no-clean   report clutter without removing it
#   Rscript data-raw/weekly.R --serial     run CDISC's engine after the R checks,
#                                          not beside them
#
# Writes data-raw/weekly/<date>/report.md and a copy at data-raw/weekly/latest.md.
# The folder is gitignored. Each run compares itself with the one before, so
# "what changed this week" is the question every section answers: which rules
# moved, which findings on the pilot study moved, how the timings moved.
#
# Nothing here pushes, installs or commits. --adopt changes the working tree
# (rules.rds and the two pins) and leaves the result for a person to review.
# The engine's Python dependencies are never updated by this script; if
# CDISC changed them, the report says so and the update is left to you.
#
# Maintainer tooling. Needs git, network access, Python for the comparison
# scripts, and the clones described in docs/REAL-STUDY.md. Not part of the
# package: data-raw/ is Rbuildignored.

args <- commandArgs(trailingOnly = TRUE)
quick <- "--quick" %in% args
adopt <- "--adopt" %in% args
clean <- !("--no-clean" %in% args)
serial <- "--serial" %in% args

if (!file.exists("DESCRIPTION") || !dir.exists("data-raw")) {
  stop("run from the package root", call. = FALSE)
}

started <- Sys.time()
state <- file.path("data-raw", "weekly")
run_dir <- file.path(state, format(started, "%Y-%m-%d_%H%M"))
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
logs <- file.path(run_dir, "logs")
dir.create(logs, showWarnings = FALSE)

# The previous run, if any, is what this one is compared with.
runs <- sort(list.dirs(state, recursive = FALSE, full.names = TRUE))
runs <- runs[grepl("^\\d{4}-\\d{2}-\\d{2}_\\d{4}$", basename(runs))]
previous <- rev(setdiff(runs, run_dir))[1]
if (is.na(previous)) previous <- NULL

rscript <- file.path(R.home("bin"), "Rscript")
upstream <- file.path("data-raw", "upstream")
rules_clone <- file.path(upstream, "cdisc-open-rules")
engine_clone <- file.path(upstream, "cdisc-rules-engine")
pilot_clone <- file.path(upstream, "sdtm-adam-pilot-project")
pilot_sdtm <- file.path(pilot_clone, "updated-pilot-submission-package", "900172",
                        "m5", "datasets", "cdiscpilot01", "tabulations", "sdtm")
python <- unname(Sys.which("python"))
engine_python <- Filter(file.exists, file.path(engine_clone, ".venv",
                                               c("Scripts/python.exe", "bin/python")))[1]

# ---- report ---------------------------------------------------------------

attention <- character()
sections <- list()
timings <- list()

flag <- function(...) attention <<- c(attention, paste0(...))
say <- function(section, ...) {
  sections[[section]] <<- c(sections[[section]], paste0(...))
}
timed <- function(name, expr) {
  t0 <- Sys.time()
  cat(sprintf("[%s] %s\n", format(t0, "%H:%M:%S"), name))
  out <- tryCatch(expr, error = function(e) {
    flag(name, " could not run: ", conditionMessage(e))
    NULL
  })
  timings[[name]] <<- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  invisible(out)
}

# Runs a command with its output in logs/<name>.log. Returns the exit status
# with the output attached, so a caller can read what it printed.
#
# The output is written in tempdir() and moved in afterwards: R CMD build
# copies the whole package folder before it applies .Rbuildignore, and on
# Windows a log still open for writing cannot be copied, which fails the build.
run <- function(name, cmd, cmd_args) {
  log <- file.path(logs, paste0(name, ".log"))
  tmp <- file.path(tempdir(), paste0(name, ".log"))
  status <- suppressWarnings(system2(cmd, cmd_args, stdout = tmp, stderr = tmp))
  out <- if (file.exists(tmp)) readLines(tmp, warn = FALSE) else character()
  writeLines(out, log)
  unlink(tmp)
  structure(status, output = out, log = log)
}
r_script <- function(name, code) {
  file <- file.path(logs, paste0(name, ".R"))
  writeLines(code, file)
  run(name, rscript, shQuote(file))
}

git <- function(path, ...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(path), ...),
                                  stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) character() else out
}

fetch_text <- function(url) {
  con <- url(url, headers = c("User-Agent" = "coreval-maintainer"))
  on.exit(close(con))
  paste(readLines(con, warn = FALSE), collapse = "\n")
}
fetch_json <- function(url) jsonlite::fromJSON(fetch_text(url), simplifyVector = FALSE)

previous_file <- function(name) {
  if (is.null(previous)) return(NULL)
  f <- file.path(previous, name)
  if (file.exists(f)) f else NULL
}

# Pandoc is needed for the vignette and R CMD check. A RSTUDIO_PANDOC left
# pointing at a removed install counts as not set: look where the installer
# puts it instead.
pandoc_in <- function(dir) nzchar(dir) && any(file.exists(file.path(dir, c("pandoc.exe", "pandoc"))))
if (!pandoc_in(Sys.getenv("RSTUDIO_PANDOC")) && !nzchar(Sys.which("pandoc"))) {
  Sys.unsetenv("RSTUDIO_PANDOC")
  candidates <- file.path(Sys.getenv("LOCALAPPDATA"), "Pandoc")
  candidates <- candidates[vapply(candidates, pandoc_in, logical(1))]
  if (length(candidates)) Sys.setenv(RSTUDIO_PANDOC = candidates[[1]])
}
if (!pandoc_in(Sys.getenv("RSTUDIO_PANDOC")) && !nzchar(Sys.which("pandoc"))) {
  cat("Pandoc not found: the tutorial and R CMD check will fail.\n")
}

# ---- 1. where the project stands ------------------------------------------

branch <- git(".", "rev-parse", "--abbrev-ref", "HEAD")
dirty <- git(".", "status", "--porcelain")
say("Project", "Branch: ", branch, ", last commit ",
    git(".", "log", "-1", shQuote("--format=%h %s (%cs)")))
if (length(dirty)) {
  say("Project", length(dirty), " files have uncommitted changes.")
}
if (!is.null(previous)) say("Project", "Compared with the run of ", basename(previous), ".")

# ---- 2. what CDISC changed ------------------------------------------------

default_branch <- function(path) {
  ref <- git(path, "ls-remote", "--symref", "origin", "HEAD")
  ref <- sub("^ref: refs/heads/(\\S+)\\s+HEAD$", "\\1", grep("^ref:", ref, value = TRUE))
  if (length(ref)) paste0("origin/", ref[[1]]) else "origin/HEAD"
}
pin_of <- function(file) trimws(readLines(file.path("data-raw", file), warn = FALSE)[[1]])

timed("CDISC updates", {
  for (clone in c(rules_clone, engine_clone, pilot_clone)) {
    if (!dir.exists(clone)) {
      flag(basename(clone), " is not cloned; docs/REAL-STUDY.md says how.")
      next
    }
    git(clone, "fetch", "--quiet", "origin")
  }

  if (dir.exists(rules_clone)) {
    pin <- pin_of("UPSTREAM_SHA")
    tip <- default_branch(rules_clone)
    n <- as.integer(git(rules_clone, "rev-list", "--count", paste0(pin, "..", tip)))
    if (length(n) && n > 0) {
      files <- git(rules_clone, "diff", "--name-status", pin, tip, "--",
                   "Published", "Deprecated", "Unpublished")
      ids <- unique(sub("^[A-Z]\\d*\\t(?:[^/]+/)+?((?:CORE|CDISC|FDA)[^/]*)/.*$", "\\1",
                        files, perl = TRUE))
      ids <- ids[!grepl("\t", ids)]
      added <- sum(grepl("^A\\t.*/rule\\.yml$", files))
      removed <- sum(grepl("^D\\t.*/rule\\.yml$", files))
      say("CDISC", "Rules: ", n, " new commits since the pin, touching ",
          length(ids), " rules (", added, " added, ", removed, " removed).")
      for (s in head(git(rules_clone, "log", "--format=%cs %s", paste0(pin, "..", tip)), 10)) {
        say("CDISC", "  - ", s)
      }
      if (!adopt) flag("CDISC published rule changes. Run with --adopt on a branch to take them.")
    } else {
      say("CDISC", "Rules: nothing new since the pin.")
    }
  }

  if (dir.exists(engine_clone)) {
    pin <- pin_of("UPSTREAM_SHA_ENGINE")
    tip <- default_branch(engine_clone)
    n <- as.integer(git(engine_clone, "rev-list", "--count", paste0(pin, "..", tip)))
    if (length(n) && n > 0) {
      say("CDISC", "Engine: ", n, " new commits since the pin.")
      for (s in head(git(engine_clone, "log", "--no-merges", "--format=%cs %s",
                         paste0(pin, "..", tip)), 15)) {
        say("CDISC", "  - ", s)
      }
      cache <- git(engine_clone, "diff", "--name-only", pin, tip, "--", "resources/cache")
      if (length(cache)) {
        flag("The engine's bundled metadata changed (", length(cache), " files, e.g. ",
             basename(cache[[1]]), "). The data-raw/dump_*.py scripts need re-running.")
      }
      deps <- git(engine_clone, "diff", "--name-only", pin, tip, "--",
                  "pyproject.toml", "requirements.txt", "requirements")
      if (length(deps)) {
        flag("The engine's Python dependencies changed. Updating its environment ",
             "needs your approval; until then the engine run may fail.")
      }
      flag("CDISC's engine moved. Read the commits above for behaviour coreval should follow.")
    } else {
      say("CDISC", "Engine: nothing new since the pin.")
    }
  }

  if (dir.exists(pilot_clone)) {
    n <- as.integer(git(pilot_clone, "rev-list", "--count", "HEAD..origin/master"))
    say("CDISC", "Pilot study: ",
        if (length(n) && n > 0) paste(n, "new commits (not pulled)") else "unchanged", ".")
  }
})

if (adopt) {
  timed("Adopt CDISC's latest", {
    before <- pin_of("UPSTREAM_SHA")
    git(rules_clone, "checkout", "--quiet", "--detach", default_branch(rules_clone))
    status <- run("extract_rules", rscript, "data-raw/extract_rules.R")
    if (status != 0) stop("extract_rules.R failed, see ", attr(status, "log"))
    git(engine_clone, "checkout", "--quiet", "--detach", default_branch(engine_clone))
    writeLines(git(engine_clone, "rev-parse", "HEAD"),
               file.path("data-raw", "UPSTREAM_SHA_ENGINE"))
    say("CDISC", "Adopted: rules ", substr(before, 1, 8), " -> ",
        substr(pin_of("UPSTREAM_SHA"), 1, 8), ", engine -> ",
        substr(pin_of("UPSTREAM_SHA_ENGINE"), 1, 8), ". Review, then commit on a branch.")
  })
}

# ---- 3. CDISC's engine on the pilot, started early ------------------------
#
# The engine takes several minutes and needs no R, so by default it runs
# beside the R checks below rather than after them.

pilot_xpt <- file.path(tempdir(), "pilot_xpt")
pilot_out <- file.path(run_dir, "pilot")
dir.create(pilot_out, showWarnings = FALSE)
# Everything the engine writes while it runs stays in tempdir(), for the
# reason given at run(); the report and the end of the log are moved in after.
engine_work <- file.path(tempdir(), "engine")
dir.create(engine_work, showWarnings = FALSE)
engine_log <- file.path(engine_work, "engine_pilot.log")
engine_started <- NULL
have_pilot <- dir.exists(pilot_sdtm)
if (have_pilot) {
  dir.create(pilot_xpt, showWarnings = FALSE)
  invisible(file.copy(list.files(pilot_sdtm, "\\.xpt$", full.names = TRUE), pilot_xpt, overwrite = TRUE))
} else {
  flag("The pilot study is not cloned, so the real-study comparison did not run.")
}

engine_done <- file.path(engine_work, "engine_pilot.done")

# The engine runs from its own clone, in a separate R process that writes
# engine_pilot.done with the exit status when it finishes.
start_engine <- function() {
  if (quick || !have_pilot || is.na(engine_python)) return(invisible())
  engine_started <<- Sys.time()
  abs <- function(p) normalizePath(p, mustWork = FALSE)
  engine_args <- c("core.py", "validate", "-s", "sdtmig", "-v", "3-2", "-uc", "INDH",
                   "-ct", "sdtmct-2014-09-26", "-d", shQuote(abs(pilot_xpt)),
                   "-of", "json", "-rr", "-o", shQuote(abs(file.path(engine_work, "report"))),
                   "-p", "disabled", "-l", "error")
  wrapper <- file.path(engine_work, "engine_pilot.R")
  writeLines(c(
    sprintf("setwd(%s)", deparse(abs(engine_clone))),
    sprintf("status <- system2(%s, %s, stdout = %s, stderr = %s)",
            deparse(abs(engine_python)), paste(deparse(engine_args), collapse = ""),
            deparse(abs(engine_log)), deparse(abs(engine_log))),
    sprintf("writeLines(as.character(status), %s)", deparse(abs(engine_done)))
  ), wrapper)
  system2(rscript, shQuote(wrapper), wait = FALSE, stdout = FALSE, stderr = FALSE)
}
if (!serial) start_engine()

# ---- 4. the checks --------------------------------------------------------

timed("Writing check", {
  status <- run("prose", rscript, "data-raw/check_prose.R")
  out <- attr(status, "output")
  if (any(grepl("No tells found", out))) {
    say("Checks", "Writing check: clean.")
  } else {
    flag("The writing check found habits to fix in the docs (logs/prose.log).")
  }
})

timed("Help pages", {
  status <- r_script("document", "suppressMessages(devtools::document(quiet = TRUE))")
  stale <- git(".", "status", "--porcelain", "--", "man", "NAMESPACE")
  if (status != 0) {
    flag("Regenerating the help pages failed (logs/document.log).")
  } else if (length(stale)) {
    flag("The help pages were out of date with the code; regenerated, ",
         length(stale), " files changed. Review and commit.")
  } else {
    say("Checks", "Help pages: up to date with the code.")
  }
})

timed("Tutorial", {
  status <- r_script("vignette", c(
    "suppressMessages(devtools::load_all(quiet = TRUE))",
    "rmarkdown::render('vignettes/coreval.Rmd', output_file = tempfile(fileext = '.html'), quiet = TRUE)"
  ))
  unlink("coreval.md")
  if (status == 0) say("Checks", "Tutorial: builds.") else
    flag("The tutorial does not build (logs/vignette.log).")
})

timed("Test suite", {
  status <- r_script("tests", c(
    "suppressMessages(devtools::load_all(quiet = TRUE))",
    "r <- as.data.frame(testthat::test_dir('tests/testthat', reporter = 'silent', stop_on_failure = FALSE))",
    "cat(sprintf('\\nRESULT %d %d %d %d\\n', sum(r$nb), sum(r$failed), sum(r$error), sum(r$skipped)))",
    "bad <- r[r$failed > 0 | r$error, c('file', 'test')]",
    "for (i in seq_len(nrow(bad))) cat('FAILED', bad$file[i], '::', bad$test[i], '\\n')"
  ))
  res <- grep("^RESULT", attr(status, "output"), value = TRUE)
  if (!length(res)) stop("no result line, see logs/tests.log")
  n <- as.integer(strsplit(res, " ")[[1]][-1])
  say("Checks", sprintf("Tests: %d checks, %d failed, %d errors, %d skipped.", n[1], n[2], n[3], n[4]))
  if (n[2] + n[3] > 0) {
    flag(n[2] + n[3], " tests fail: ",
         paste(sub("^FAILED ", "", grep("^FAILED", attr(status, "output"), value = TRUE)),
               collapse = "; "))
  }
})

timed("CDISC's test cases", {
  # system2(env =) is ignored on Windows, so the worker count goes through
  # this process's environment, which the child inherits.
  Sys.setenv(COREVAL_WORKERS = "8")
  status <- run("conformance", rscript,
                c("tests/conformance/run_conformance.R", rules_clone))
  sb <- "tests/conformance/scoreboard.csv"
  if (status != 0 || !file.exists(sb)) stop("the sweep failed, see logs/conformance.log")
  file.copy(sb, file.path(run_dir, "scoreboard.csv"), overwrite = TRUE)
  now <- utils::read.csv(sb, stringsAsFactors = FALSE)
  tab <- table(now$status)
  say("Checks", "CDISC's test cases: ", paste(names(tab), tab, collapse = ", "), ".")
  prior <- previous_file("scoreboard.csv")
  if (!is.null(prior)) {
    was <- utils::read.csv(prior, stringsAsFactors = FALSE)
    m <- merge(was[c("id", "status", "reason")], now[c("id", "status", "reason")],
               by = "id", all = TRUE, suffixes = c("_was", "_now"))
    differs <- function(a, b) (is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
    moved <- m[differs(m$status_was, m$status_now), ]
    answer <- m[!differs(m$status_was, m$status_now) & differs(m$reason_was, m$reason_now), ]
    for (i in seq_len(nrow(moved))) {
      line <- sprintf("%s: %s -> %s", moved$id[i], moved$status_was[i], moved$status_now[i])
      say("Checks", "  - moved: ", line)
      if (identical(moved$status_now[i], "FAIL") || identical(moved$status_was[i], "PASS")) {
        flag("Rule got worse on CDISC's test cases: ", line)
      }
    }
    for (i in seq_len(nrow(answer))) {
      say("Checks", "  - same status, different answer: ", answer$id[i])
    }
    if (nrow(answer)) {
      flag(nrow(answer), " rules kept their status but changed which records they report.")
    }
    if (!nrow(moved) && !nrow(answer)) say("Checks", "  No rule moved since the last run.")
  }
})

finding_counts <- function(file) {
  if (is.null(file) || !file.exists(file)) return(NULL)
  f <- utils::read.csv(file, stringsAsFactors = FALSE)
  table(paste(f$rule_id, f$Dataset))
}

if (have_pilot) timed("Pilot study, coreval", {
  status <- run("pilot_coreval", rscript,
                c("tests/conformance/pilot_study.R", shQuote(pilot_xpt), shQuote(pilot_out)))
  if (status != 0) stop("pilot_study.R failed, see logs/pilot_coreval.log")
  line <- grep("^coreval:", attr(status, "output"), value = TRUE)
  secs <- as.numeric(sub("^coreval: ([0-9.]+)s.*", "\\1", line))
  writeLines(as.character(secs), file.path(run_dir, "pilot_seconds.txt"))
  now <- finding_counts(file.path(pilot_out, "coreval_findings.csv"))
  say("Real study", sprintf("coreval: %s findings in %.1f s.", format(sum(now), big.mark = ","), secs))
  prior <- previous_file(file.path("pilot", "coreval_findings.csv"))
  if (!is.null(prior)) {
    was <- finding_counts(prior)
    keys <- union(names(was), names(now))
    a <- as.integer(was[keys]); a[is.na(a)] <- 0L
    b <- as.integer(now[keys]); b[is.na(b)] <- 0L
    diff <- keys[a != b]
    if (length(diff)) {
      flag("Findings on the pilot study moved for ", length(diff), " rule/dataset pairs.")
      for (k in head(diff, 20)) {
        say("Real study", sprintf("  - %s: %d -> %d", k, a[keys == k], b[keys == k]))
      }
    } else {
      say("Real study", "  The same findings as the last run.")
    }
    prior_secs <- previous_file("pilot_seconds.txt")
    if (!is.null(prior_secs)) {
      old <- as.numeric(readLines(prior_secs, warn = FALSE))
      if (secs > old * 1.25 && secs - old > 3) {
        flag(sprintf("coreval got slower on the pilot study: %.1f s, was %.1f s.", secs, old))
      }
    }
  }
})

if (!quick) {
  timed("R CMD check --as-cran", {
    status <- r_script("rcmdcheck", c(
      "res <- rcmdcheck::rcmdcheck(args = c('--as-cran', '--no-manual'), error_on = 'never',",
      "                            check_dir = tempfile('check'), quiet = FALSE)",
      "cat(sprintf('\\nRESULT %d %d %d\\n', length(res$errors), length(res$warnings), length(res$notes)))",
      "for (x in c(res$errors, res$warnings, res$notes)) cat('ITEM', gsub('\\n', ' ', x), '\\n')"
    ))
    res <- grep("^RESULT", attr(status, "output"), value = TRUE)
    if (!length(res)) stop("no result line, see logs/rcmdcheck.log")
    n <- as.integer(strsplit(res, " ")[[1]][-1])
    say("Checks", sprintf("CRAN check: %d errors, %d warnings, %d notes.", n[1], n[2], n[3]))
    items <- sub("^ITEM ", "", grep("^ITEM", attr(status, "output"), value = TRUE))
    for (x in items) say("Checks", "  - ", substr(x, 1, 200))
    # One NOTE is expected on a submission: "Days since last update" or a new
    # maintainer. Anything past that is worth reading.
    if (n[1] + n[2] > 0) flag("R CMD check --as-cran reports errors or warnings.")
  })

  timed("Links", {
    status <- r_script("urls", c(
      "res <- urlchecker::url_check(progress = FALSE)",
      "cat('\\nRESULT', nrow(res), '\\n')",
      "if (nrow(res)) for (i in seq_len(nrow(res))) cat('ITEM', res$URL[i], res$Status[i], '\\n')"
    ))
    res <- grep("^RESULT", attr(status, "output"), value = TRUE)
    n <- if (length(res)) as.integer(sub("RESULT ", "", res)) else NA
    if (is.na(n)) {
      flag("The link check did not finish (logs/urls.log).")
    } else if (n == 0) {
      say("Checks", "Links: all resolve.")
    } else {
      flag(n, " links in the package are broken or moved (logs/urls.log).")
    }
  })
}

if (serial) start_engine()

if (is.null(engine_started) && !quick && have_pilot) {
  flag("CDISC's engine has no environment set up, so the pilot comparison with it was skipped.")
}
if (!is.null(engine_started)) timed("Pilot study, CDISC's engine", {
  report <- file.path(engine_work, "report.json")
  deadline <- Sys.time() + 45 * 60
  while (!file.exists(engine_done) && Sys.time() < deadline) Sys.sleep(5)
  if (!file.exists(engine_done)) stop("the engine did not finish within 45 minutes")
  # The engine logs a traceback for every rule that meets a missing column,
  # hundreds of thousands of lines on the pilot. Keep the end.
  if (file.exists(engine_log)) {
    writeLines(utils::tail(readLines(engine_log, warn = FALSE), 300),
               file.path(logs, "engine_pilot.log"))
  }
  if (readLines(engine_done, warn = FALSE)[[1]] != "0" || !file.exists(report)) {
    stop("the engine failed, see logs/engine_pilot.log")
  }
  engine_secs <- as.numeric(difftime(file.mtime(engine_done), engine_started, units = "secs"))
  file.copy(report, pilot_out, overwrite = TRUE)
  report <- file.path(pilot_out, "report.json")
  compare <- run("compare_pilot", python,
                 c("tests/conformance/compare_pilot.py", shQuote(report), shQuote(pilot_out)))
  out <- attr(compare, "output")
  counts <- grep("^[a-z].*: \\d+$", out, value = TRUE)
  say("Real study", sprintf("CDISC's engine: %.0f s.", engine_secs))
  for (x in counts) say("Real study", "  ", x)
  writeLines(counts, file.path(run_dir, "pilot_agreement.txt"))
  prior <- previous_file("pilot_agreement.txt")
  if (!is.null(prior) && !identical(readLines(prior, warn = FALSE), counts)) {
    flag("The agreement with CDISC's engine on the pilot study changed; see the Real study section.")
  }
})

# ---- 5. out in the world --------------------------------------------------

slug <- sub("^.*github\\.com[/:]([^/]+/[^/.]+)(\\.git)?$", "\\1",
            git(".", "remote", "get-url", "origin"))

timed("CRAN", {
  page <- fetch_text("https://cran.r-project.org/web/checks/check_results_coreval.html")
  # One cell per CRAN machine: <td class="check_ok">, check_note, ...
  status <- regmatches(page, gregexpr("class=\"check_(ok|note|warn|warning|error|fail)\"", page))[[1]]
  status <- table(toupper(sub("^class=\"check_(\\w+)\"$", "\\1", status)))
  if (!length(status)) flag("CRAN's check page could not be read; its layout may have changed.")
  say("Out there", "CRAN's own checks: ",
      if (length(status)) paste(names(status), status, collapse = ", ") else "none listed", ".")
  if (any(names(status) %in% c("WARN", "WARNING", "ERROR", "FAIL"))) {
    flag("CRAN's checks show a problem: https://cran.r-project.org/web/checks/check_results_coreval.html")
  }
  week <- fetch_json("https://cranlogs.r-pkg.org/downloads/total/last-week/coreval")[[1]]$downloads
  total <- fetch_json(paste0("https://cranlogs.r-pkg.org/downloads/total/2020-01-01:",
                             format(Sys.Date(), "%Y-%m-%d"), "/coreval"))[[1]]$downloads
  say("Out there", sprintf("Downloads: %d last week, %d in all.", week, total))

  cran <- utils::available.packages(repos = "https://cloud.r-project.org")
  for (p in c("data.table", "haven", "xml2", "jsonlite", "testthat")) {
    have <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA)
    latest <- if (p %in% rownames(cran)) cran[p, "Version"] else NA
    if (!is.na(have) && !is.na(latest) && package_version(latest) > package_version(have)) {
      say("Out there", sprintf("  %s %s is on CRAN; %s is installed here.", p, latest, have))
      if (p %in% c("data.table", "haven")) {
        flag(p, " ", latest, " is out. coreval is tested here against ", have,
             "; updating it here needs your approval.")
      }
    }
  }
})

timed("GitHub", {
  api <- paste0("https://api.github.com/repos/", slug)
  ci <- fetch_json(paste0(api, "/actions/runs?branch=master&per_page=5"))$workflow_runs
  say("Out there", "GitHub's checks on master, latest first:")
  for (r in ci) {
    say("Out there", sprintf("  %s: %s (%s)", r$name,
                             if (is.null(r$conclusion)) r$status else r$conclusion,
                             substr(r$created_at, 1, 10)))
  }
  # The latest run of each workflow is what counts; an old failure since
  # fixed is history.
  latest <- ci[!duplicated(vapply(ci, `[[`, "", "name"))]
  if (any(vapply(latest, function(r) identical(r$conclusion, "failure"), logical(1)))) {
    flag("A recent GitHub check on master failed: https://github.com/", slug, "/actions")
  }
  issues <- fetch_json(paste0(api, "/issues?state=open&per_page=50"))
  prs <- sum(vapply(issues, function(i) !is.null(i$pull_request), logical(1)))
  say("Out there", sprintf("Open on GitHub: %d issues, %d pull requests.",
                           length(issues) - prs, prs))
  if (length(issues)) flag("Someone opened an issue or pull request: https://github.com/", slug, "/issues")
  pv <- fetch_json("https://api.github.com/repos/pharmaverse/pharmaverse/issues/454")
  say("Out there", sprintf("pharmaverse listing request: %s, %d comments, last activity %s.",
                           pv$state, pv$comments, substr(pv$updated_at, 1, 10)))
  prior <- previous_file("pharmaverse.txt")
  writeLines(as.character(pv$comments), file.path(run_dir, "pharmaverse.txt"))
  if (!is.null(prior) && readLines(prior, warn = FALSE) != as.character(pv$comments)) {
    flag("New comments on the pharmaverse listing request: https://github.com/pharmaverse/pharmaverse/issues/454")
  }
})

# ---- 6. clean up ----------------------------------------------------------

timed("Clean-up", {
  # Only things this project's own tools generate and nothing reads back.
  junk <- c(
    Sys.glob(c("*.Rcheck", "coreval_*.tar.gz", ".Rhistory", "coreval.md",
               "vignettes/*.html", "vignettes/*.R", "vignettes/*_cache", "vignettes/*_files",
               "tests/conformance/.engine-out", "tests/conformance/__pycache__",
               "Rplots.pdf", "tests/testthat/Rplots.pdf"))
  )
  junk <- junk[file.exists(junk)]
  # Keep the last eight weekly runs.
  old_runs <- head(sort(runs), max(0, length(runs) - 8))
  junk <- c(junk, old_runs)
  size <- sum(vapply(junk, function(p) {
    f <- if (dir.exists(p)) list.files(p, recursive = TRUE, full.names = TRUE, all.files = TRUE) else p
    sum(file.size(f), na.rm = TRUE)
  }, numeric(1)))
  if (length(junk)) {
    if (clean) {
      unlink(junk, recursive = TRUE)
      say("Clean-up", sprintf("Removed %d leftovers (%.1f MB): %s", length(junk), size / 1e6,
                              paste(basename(junk), collapse = ", ")))
    } else {
      say("Clean-up", sprintf("Would remove %d leftovers (%.1f MB): %s", length(junk), size / 1e6,
                              paste(basename(junk), collapse = ", ")))
    }
  } else {
    say("Clean-up", "Nothing left lying around.")
  }

  # Reported, never removed: these need a person's decision.
  untracked <- git(".", "ls-files", "--others", "--exclude-standard")
  if (length(untracked)) {
    say("Clean-up", "Files git does not track and does not ignore: ",
        paste(head(untracked, 15), collapse = ", "))
  }
  merged <- setdiff(trimws(sub("^\\*", "", git(".", "branch", "--merged", "master"))),
                    c("master", branch))
  if (length(merged)) say("Clean-up", "Branches already merged into master: ", paste(merged, collapse = ", "))
  stashes <- git(".", "stash", "list")
  if (length(stashes)) say("Clean-up", length(stashes), " stashed changes are waiting.")
  unpushed <- git(".", "log", "--oneline", "origin/master..HEAD")
  if (length(unpushed)) {
    say("Clean-up", sprintf("%d commits on %s are not on GitHub yet.", length(unpushed), branch))
  }
})

# ---- write the report -----------------------------------------------------

total <- as.numeric(difftime(Sys.time(), started, units = "secs"))
lines <- c(
  paste0("# coreval weekly check, ", format(started, "%Y-%m-%d %H:%M")),
  "",
  if (length(attention)) c("## Needs attention", "", paste0("- ", attention)) else
    c("## Needs attention", "", "Nothing. Everything below is for the record."),
  ""
)
for (s in names(sections)) {
  items <- sections[[s]]
  items <- ifelse(grepl("^  ", items), paste0("  ", sub("^ +(- )?", "- ", items)),
                  paste0("- ", items))
  lines <- c(lines, paste("##", s), "", items, "")
}
lines <- c(lines, "## Timings", "",
           sprintf("- %s: %.0f s", names(timings), unlist(timings)),
           sprintf("- whole run: %.0f s (%s)", total,
                   if (serial) "engine after the R checks" else "engine beside the R checks"),
           "")
writeLines(lines, file.path(run_dir, "report.md"))
invisible(file.copy(file.path(run_dir, "report.md"), file.path(state, "latest.md"), overwrite = TRUE))
cat("\n", paste(lines, collapse = "\n"), "\n", sep = "")

# Reports whether the pinned upstream rule set has moved, and whether the
# local clones are fresh. Run before a release, or whenever a rule's
# behaviour is in question.
#
#   Rscript data-raw/check_upstream.R
#   Rscript data-raw/check_upstream.R --fetch    # also `git fetch` first
#
# This is a MAINTAINER tool, not part of the package: it needs `git` and
# network access, neither of which the package itself ever uses. Nothing
# here changes the pinned SHA - re-pinning is a deliberate act, done by
# re-running data-raw/extract_rules.R against an updated clone.

args <- commandArgs(trailingOnly = TRUE)
do_fetch <- "--fetch" %in% args

pinned_path <- file.path("data-raw", "UPSTREAM_SHA")
if (!file.exists(pinned_path)) {
  stop("No pinned SHA at ", pinned_path, call. = FALSE)
}
pinned <- trimws(readLines(pinned_path, warn = FALSE)[[1]])

repos <- list(
  list(
    name = "cdisc-open-rules",
    path = file.path("data-raw", "upstream", "cdisc-open-rules"),
    why = "the rule definitions and reference test data this package bundles"
  ),
  list(
    name = "cdisc-rules-engine",
    path = file.path("data-raw", "upstream", "cdisc-rules-engine"),
    why = "the reference implementation, consulted to settle rule semantics"
  )
)

git <- function(path, ...) {
  out <- suppressWarnings(system2(
    "git", c("-C", shQuote(path), ...),
    stdout = TRUE, stderr = TRUE
  ))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) NA_character_ else out
}

cat("Pinned rule set:", pinned, "\n\n")

for (repo in repos) {
  cat("--", repo$name, "\n   ", repo$why, "\n")
  if (!dir.exists(repo$path)) {
    cat("    NOT CLONED at", repo$path, "\n")
    cat("    git clone https://github.com/cdisc-org/", repo$name, ".git ", repo$path, "\n\n", sep = "")
    next
  }
  if (do_fetch) {
    cat("    fetching...\n")
    git(repo$path, "fetch", "--quiet", "origin")
  }

  head_sha <- git(repo$path, "rev-parse", "HEAD")[[1]]
  head_date <- git(repo$path, "log", "-1", "--format=%cs", "HEAD")[[1]]
  cat("    local HEAD:", head_sha, "(", head_date, ")\n")

  # How far the local clone is behind its own remote-tracking branch. A
  # shallow clone (--depth 1) has no upstream ref to compare against, which
  # is a normal and expected state here, not an error.
  behind <- git(repo$path, "rev-list", "--count", "HEAD..@{upstream}")
  if (!is.na(behind[[1]]) && nzchar(behind[[1]])) {
    n <- suppressWarnings(as.integer(behind[[1]]))
    if (!is.na(n)) {
      cat("    behind remote by:", n, if (n == 1) "commit" else "commits",
          if (n == 0) "(up to date)" else "- run with --fetch, then re-clone/pull to update", "\n")
    }
  } else {
    cat("    behind remote: unknown (shallow clone, or no upstream tracking ref)\n")
  }

  if (identical(repo$name, "cdisc-open-rules")) {
    if (identical(head_sha, pinned)) {
      cat("    MATCHES the pinned SHA - bundled rules are built from this clone\n")
    } else {
      cat("    DIFFERS from the pinned SHA\n")
      ahead <- git(repo$path, "rev-list", "--count", paste0(pinned, "..HEAD"))
      if (!is.na(ahead[[1]]) && nzchar(ahead[[1]])) {
        cat("    clone is", ahead[[1]], "commits ahead of the pin\n")
      }
      cat("    -> to adopt: Rscript data-raw/extract_rules.R (rewrites UPSTREAM_SHA),\n")
      cat("       then re-run the conformance harness and review every status change\n")
    }
  }
  cat("\n")
}

cat("Re-pinning is deliberate: adopting a newer rule set can change which\n")
cat("records every rule flags, so always diff the conformance scoreboard after.\n")

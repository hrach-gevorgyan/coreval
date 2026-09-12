# Flags the writing habits that make documentation read like it was generated
# rather than written. Run it before a release, or after any doc change:
#
#   Rscript data-raw/check_prose.R
#
# It reports file:line for each hit and exits non-zero if anything is found, so
# it can go in CI later. Nothing here is a rule of grammar - every pattern is
# defensible in isolation. The problem is DENSITY: 53 em dashes in one README
# is a tell, three is a style.
#
# Code fences are skipped. The report banner coreval prints really does contain
# an em dash, and a doc showing real output must show it.

files <- c(
  "README.md", "NEWS.md", "NOTICE.md", "cran-comments.md",
  "vignettes/coreval.Rmd",
  # The public half of docs/. RELEASING.md and archive/ are the maintainer's
  # own and are not held to this.
  "docs/README.md", "docs/DECISIONS.md", "docs/COVERAGE.md",
  "docs/REFERENCE-BEHAVIOUR.md", "docs/BENCHMARKS.md",
  list.files("R", pattern = "[.]R$", full.names = TRUE)
)

# Each entry: a regex, and why it is worth looking at.
patterns <- list(
  c("—", "em dash: prefer a full stop, a comma, or a colon"),
  c("\\bworth noting\\b", "'worth noting': if it is, just say it"),
  c("\\bthat said\\b", "'that said': usually deletable"),
  c("\\bin other words\\b", "'in other words': say it once, in the right words"),
  c("\\beither way\\b", "'either way': often a hedge"),
  c("\\bit'?s not just\\b", "'it's not just X': the 'not X but Y' shape, used heavily"),
  c("\\bgenuinely\\b", "'genuinely': intensifier, rarely earns its place"),
  c("\\bhonest(ly)?\\b", "'honest': show it, do not claim it"),
  c("\\bdelve|\\btapestry|\\bmultifaceted|\\bnavigate the\\b", "generated-text vocabulary")
)

# Only what a user reads: Markdown outside code fences, and roxygen (#') in an
# .R file. Ordinary code comments are for whoever maintains this and are left
# alone. Scrubbing "genuinely" out of an explanation of why a join works would
# cost clarity and buy nothing.
prose_lines <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (grepl("[.]R$", path)) {
    keep <- grepl("^\\s*#'", lines)
    return(data.frame(n = which(keep), text = lines[keep], stringsAsFactors = FALSE))
  }
  fence <- cumsum(grepl("^\\s*```", lines)) %% 2 == 1
  fence <- fence | grepl("^\\s*```", lines)
  data.frame(n = which(!fence), text = lines[!fence], stringsAsFactors = FALSE)
}

total <- 0L
for (path in files) {
  if (!file.exists(path)) next
  pl <- prose_lines(path)
  if (nrow(pl) == 0) next
  for (p in patterns) {
    hit <- grep(p[[1]], pl$text, ignore.case = TRUE)
    for (i in hit) {
      total <- total + 1L
      cat(sprintf("%s:%d  [%s]\n    %s\n", path, pl$n[i], p[[2]],
                  trimws(substr(pl$text[i], 1, 96))))
    }
  }
}

if (total == 0L) {
  cat("No tells found in", length(files), "files.\n")
} else {
  cat("\n", total, " to look at. None is automatically wrong; density is the signal.\n", sep = "")
}
quit(status = if (total > 0L) 1L else 0L)

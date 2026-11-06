# Read a workbook write_findings() wrote back into R, with base R only, so the
# tests that use it run on every machine rather than skipping where readxl is
# not installed. An .xlsx is a zip of XML: the sheet names and their order are
# in xl/workbook.xml, the text in xl/sharedStrings.xml, and each sheet's cells
# in xl/worksheets/. Every value comes back as text, blank where the cell is
# empty, which is how writexl leaves an empty string or an NA.
read_xlsx_text <- function(path) {
  dir <- tempfile("xlsx_")
  on.exit(unlink(dir, recursive = TRUE))
  utils::unzip(path, exdir = dir)
  slurp <- function(...) paste(readLines(file.path(dir, ...), warn = FALSE, encoding = "UTF-8"), collapse = "")
  unescape <- function(x) {
    x <- gsub("&lt;", "<", x, fixed = TRUE)
    x <- gsub("&gt;", ">", x, fixed = TRUE)
    x <- gsub("&quot;", "\"", x, fixed = TRUE)
    x <- gsub("&apos;", "'", x, fixed = TRUE)
    gsub("&amp;", "&", x, fixed = TRUE)
  }
  grab <- function(text, pattern) regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  field <- function(x, pattern) sub(pattern, "\\1", regmatches(x, regexpr(pattern, x, perl = TRUE)), perl = TRUE)

  workbook <- slurp("xl", "workbook.xml")
  sheets <- grab(workbook, "<sheet [^>]*/>")
  names_ <- unescape(field(sheets, 'name="([^"]*)"'))
  ids <- field(sheets, 'r:id="([^"]*)"')
  rels <- grab(slurp("xl", "_rels", "workbook.xml.rels"), "<Relationship [^>]*/>")
  targets <- setNames(field(rels, 'Target="([^"]*)"'), field(rels, 'Id="([^"]*)"'))

  strings <- if (file.exists(file.path(dir, "xl", "sharedStrings.xml"))) {
    si <- grab(slurp("xl", "sharedStrings.xml"), "<si>.*?</si>")
    unescape(vapply(si, function(s) paste(sub("<t[^>]*>(.*)</t>", "\\1", grab(s, "<t[^>]*>.*?</t>"), perl = TRUE), collapse = ""), character(1), USE.NAMES = FALSE))
  } else {
    character(0)
  }
  col_number <- function(letters) {
    vapply(strsplit(letters, ""), function(ch) Reduce(function(a, b) a * 26 + b, match(ch, LETTERS)), numeric(1))
  }

  out <- lapply(seq_along(names_), function(i) {
    xml <- slurp("xl", targets[[ids[i]]])
    cells <- grab(xml, "<c [^>]*?(/>|>.*?</c>)")
    if (length(cells) == 0) return(data.frame())
    ref <- field(cells, ' r="([A-Z]+[0-9]+)"')
    row <- as.integer(sub("^[A-Z]+", "", ref))
    col <- col_number(sub("[0-9]+$", "", ref))
    value <- vapply(cells, function(c) {
      v <- field(c, "<v>(.*?)</v>")
      if (length(v) == 0) return("")
      if (grepl(' t="s"', c, fixed = TRUE)) strings[as.integer(v) + 1L] else unescape(v)
    }, character(1), USE.NAMES = FALSE)
    grid <- matrix("", nrow = max(row), ncol = max(col))
    grid[cbind(row, col)] <- value
    df <- as.data.frame(grid[-1, , drop = FALSE], stringsAsFactors = FALSE)
    names(df) <- grid[1, ]
    df
  })
  setNames(out, names_)
}

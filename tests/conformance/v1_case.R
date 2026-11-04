# Read a CORE 1.0 test case and write it out in the layout CDISC's
# cdisc-open-rules test cases use, so the rest of the harness grades it exactly
# as it grades those.
#
# The 1.0 rules are written and tested in verisianHQ/core-contributor, where
# each case is one Excel workbook (a Library sheet naming the standard, a
# Datasets sheet, an optional Validation sheet, and one sheet per dataset) and
# a results/results.json. cdisc-open-rules uses a .env, _datasets.csv,
# _variables.csv, one CSV per dataset and a results/results.csv. Converting
# into that layout means read_study() and run_case_graded() read and grade a
# 1.0 case through the same code as every other case: a second reader would be
# a second code path for one job, and those drift.
#
# Every rule for turning a cell into a value follows the reference loader,
# sharepoint_xlsx_to_test_datasets() in the engine's
# tests/rule_regression/regression.py, which reads the workbook with pandas and
# openpyxl. Where that loader's behaviour depends on something not yet seen in
# any 1.0 case (a date-formatted cell, a non-numeric value in a Num column),
# this stops with an error naming the file rather than guessing.
#
# Needs xml2. Dev tooling only: Rbuildignored with the rest of
# tests/conformance, and nothing here runs in the package.

# ---- the workbook ------------------------------------------------------------

xl_col_index <- function(letters) {
  vapply(strsplit(letters, ""), function(ch) {
    sum((match(ch, LETTERS)) * 26^(rev(seq_along(ch)) - 1))
  }, numeric(1))
}

xl_text_runs <- function(node) {
  # The text of a string item: its own <t> plus the <t> of each rich-text run.
  # Phonetic runs (<rPh>) are not part of the value.
  t <- xml2::xml_find_all(node, "./*[local-name()='t'] | ./*[local-name()='r']/*[local-name()='t']")
  paste(xml2::xml_text(t), collapse = "")
}

# Built-in number formats openpyxl treats as dates and times.
XL_DATE_FORMAT_IDS <- c(14:22, 45:47)

# Which cell styles openpyxl reads as a date, and which as a duration. Its
# is_date_format() looks at the first section of the format only, ignores
# quoted text, escaped characters and bracketed sections other than [h], [m]
# and [s], and calls it a date if a d, m, y, h or s is left. A bracketed
# [h], [m] or [s] makes it a duration instead.
xl_date_styles <- function(dir) {
  path <- file.path(dir, "xl", "styles.xml")
  none <- list(date = integer(0), duration = integer(0))
  if (!file.exists(path)) return(none)
  st <- xml2::read_xml(path)
  custom <- xml2::xml_find_all(st, ".//*[local-name()='numFmts']/*[local-name()='numFmt']")
  custom_ids <- as.integer(xml2::xml_attr(custom, "numFmtId"))
  codes <- sub(";.*$", "", xml2::xml_attr(custom, "formatCode") %||% character(0))
  bracket_unit <- "\\[(h|hh|m|mm|s|ss)\\]"
  stripped <- gsub('"[^"]*"|\\\\.|\\[(?!(h|hh|m|mm|s|ss)\\])[^]]*\\]', "", codes, perl = TRUE)
  date_custom <- custom_ids[grepl("[dmyhs]", stripped, ignore.case = TRUE)]
  duration_custom <- custom_ids[grepl(bracket_unit, codes, ignore.case = TRUE)]
  xfs <- xml2::xml_find_all(st, ".//*[local-name()='cellXfs']/*[local-name()='xf']")
  fmt <- as.integer(xml2::xml_attr(xfs, "numFmtId"))
  list(date = which(fmt %in% c(XL_DATE_FORMAT_IDS, date_custom)) - 1L,
       duration = which(fmt %in% c(46L, duration_custom)) - 1L)
}

# A serial number, as openpyxl's from_excel() turns it into a datetime and
# str() then prints it: "2011-02-08 00:00:00", with ".ffffff" only when there
# are microseconds, and a bare "HH:MM:SS" for a value below one day. The 1900
# calendar counts a 29 February 1900 that never was, so openpyxl adds a day
# below serial 60, and a workbook can use the 1904 calendar instead.
#
# No 1.0 answer file reports the value of a date cell, so this rests on the
# source of openpyxl and pandas rather than on an answer the reference gave.
xl_serial_text <- function(serial, date1904) {
  vapply(as.numeric(serial), function(v) {
    day <- floor(v)
    ms <- round((v - day) * 86400 * 1000)
    hms <- function(t) {
      txt <- sprintf("%02d:%02d:%02d", t %/% 3600000, (t %/% 60000) %% 60, (t %/% 1000) %% 60)
      if (t %% 1000 > 0) paste0(txt, sprintf(".%06d", (t %% 1000) * 1000)) else txt
    }
    if (v >= 0 && v < 1 && ms < 86400000) return(hms(ms))
    if (!date1904 && v > 0 && v < 60) day <- day + 1
    epoch <- if (date1904) as.Date("1904-01-01") else as.Date("1899-12-30")
    paste(format(epoch + day + ms %/% 86400000, "%Y-%m-%d"), hms(ms %% 86400000))
  }, character(1))
}

# Each sheet as a matrix of cells, with what kind of cell each one is. Kinds:
# "empty", "num" (value is the number as written), "str", "bool" (TRUE/FALSE),
# "err". Rows and columns are the sheet's own.
xl_read <- function(path, dates = c("convert", "raw")) {
  dates <- match.arg(dates)
  dir <- tempfile("xlsx_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  utils::unzip(path, exdir = dir)

  wb <- xml2::read_xml(file.path(dir, "xl", "workbook.xml"))
  sheet_nodes <- xml2::xml_find_all(wb, ".//*[local-name()='sheets']/*[local-name()='sheet']")
  sheet_names <- xml2::xml_attr(sheet_nodes, "name")
  sheet_rid <- vapply(xml2::xml_attrs(sheet_nodes), function(a) {
    unname(a[grepl("(^|:)id$", names(a))][1])
  }, character(1))
  rels <- xml2::read_xml(file.path(dir, "xl", "_rels", "workbook.xml.rels"))
  rel_nodes <- xml2::xml_find_all(rels, ".//*[local-name()='Relationship']")
  targets <- stats::setNames(xml2::xml_attr(rel_nodes, "Target"), xml2::xml_attr(rel_nodes, "Id"))
  sheet_file <- vapply(sheet_rid, function(id) {
    t <- targets[[id]]
    if (startsWith(t, "/")) file.path(dir, sub("^/", "", t)) else file.path(dir, "xl", t)
  }, character(1))

  shared <- character(0)
  ss_path <- file.path(dir, "xl", "sharedStrings.xml")
  if (file.exists(ss_path)) {
    ss <- xml2::read_xml(ss_path)
    si <- xml2::xml_find_all(ss, ".//*[local-name()='si']")
    # All of an item's text is its value unless it carries phonetic runs,
    # which are not; reading run by run is only needed then, and is slow.
    shared <- if (length(xml2::xml_find_all(ss, ".//*[local-name()='rPh']"))) {
      vapply(si, xl_text_runs, character(1))
    } else {
      xml2::xml_text(si)
    }
  }
  styles <- xl_date_styles(dir)
  pr <- xml2::xml_find_first(wb, ".//*[local-name()='workbookPr']")
  date1904 <- !inherits(pr, "xml_missing") && isTRUE(xml2::xml_attr(pr, "date1904") %in% c("1", "true"))

  sheets <- lapply(seq_along(sheet_names), function(i) {
    x <- xml2::read_xml(sheet_file[[i]])
    cells <- xml2::xml_find_all(x, ".//*[local-name()='sheetData']/*[local-name()='row']/*[local-name()='c']")
    if (length(cells) == 0) {
      return(list(value = matrix(character(0), 0, 0), kind = matrix(character(0), 0, 0)))
    }
    ref <- xml2::xml_attr(cells, "r")
    if (anyNA(ref)) stop("a cell without a reference in ", basename(path), ", sheet ", sheet_names[[i]], call. = FALSE)
    type <- xml2::xml_attr(cells, "t")
    style <- as.integer(xml2::xml_attr(cells, "s"))
    v <- xml2::xml_text(xml2::xml_find_first(cells, "./*[local-name()='v']"))
    row <- as.integer(sub("^[A-Z]+", "", ref))
    col <- xl_col_index(sub("[0-9]+$", "", ref))

    kind <- rep("empty", length(cells))
    value <- rep(NA_character_, length(cells))
    numeric <- is.na(type) | type == "n"
    kind[numeric & !is.na(v)] <- "num"
    value[numeric & !is.na(v)] <- v[numeric & !is.na(v)]
    s <- !is.na(type) & type == "s"
    kind[s] <- "str"
    value[s] <- shared[as.integer(v[s]) + 1L]
    fs <- !is.na(type) & type == "str"
    kind[fs] <- "str"
    value[fs] <- ifelse(is.na(v[fs]), "", v[fs])
    inl <- which(!is.na(type) & type == "inlineStr")
    if (length(inl)) {
      is_nodes <- xml2::xml_find_first(cells[inl], "./*[local-name()='is']")
      kind[inl] <- "str"
      value[inl] <- if (length(xml2::xml_find_all(x, ".//*[local-name()='rPh']"))) {
        vapply(seq_along(inl), function(j) {
          if (inherits(is_nodes[[j]], "xml_missing")) "" else xl_text_runs(is_nodes[[j]])
        }, character(1))
      } else {
        txt <- xml2::xml_text(is_nodes)
        ifelse(is.na(txt), "", txt)
      }
    }
    b <- !is.na(type) & type == "b"
    kind[b] <- "bool"
    value[b] <- ifelse(v[b] == "1", "TRUE", "FALSE")
    kind[!is.na(type) & type == "e"] <- "err"
    if (any(!is.na(type) & type == "d")) {
      stop("an ISO date cell (t=\"d\") in ", basename(path), ", sheet ", sheet_names[[i]],
           ": the reference reads it as a datetime, which is not handled yet", call. = FALSE)
    }
    timed <- kind == "num" & !is.na(style) & style %in% styles$duration
    if (any(timed)) {
      stop("a duration-formatted number in ", basename(path), ", sheet ", sheet_names[[i]],
           ", cell ", ref[timed][1], ": the reference reads it as a timedelta, ",
           "which is not handled yet", call. = FALSE)
    }
    dated <- kind == "num" & !is.na(style) & style %in% styles$date
    if (any(dated)) {
      kind[dated] <- "date"
      if (dates == "convert") value[dated] <- xl_serial_text(value[dated], date1904)
    }

    n_row <- max(row)
    n_col <- max(col)
    vm <- matrix(NA_character_, n_row, n_col)
    km <- matrix("empty", n_row, n_col)
    vm[cbind(row, col)] <- value
    km[cbind(row, col)] <- kind
    list(value = vm, kind = km)
  })
  stats::setNames(sheets, sheet_names)
}

# ---- one cell, the way the reference sees it ---------------------------------

# Python's repr() of a float: the shortest digits that round-trip, fixed
# notation from 1e-4 up to 1e16 and scientific outside it, and ".0" on a whole
# number. str() of a float in pandas' loader produces exactly this.
py_float_repr <- function(x) {
  vapply(x, function(v) {
    if (is.na(v)) return(NA_character_)
    if (is.infinite(v)) return(if (v > 0) "inf" else "-inf")
    if (v == 0) return(if (1 / v < 0) "-0.0" else "0.0")
    for (p in 1:17) {
      s <- sprintf("%.*e", p - 1L, v)
      if (as.numeric(s) == v) break
    }
    m <- regmatches(s, regexec("^(-?)([0-9])(?:[.]([0-9]+))?e([+-][0-9]+)$", s))[[1]]
    sign <- m[2]
    digits <- sub("0+$", "", paste0(m[3], m[4]))
    if (!nzchar(digits)) digits <- "0"
    e <- as.integer(m[5])
    n <- nchar(digits)
    if (e >= -4 && e < 16) {
      if (e >= 0) {
        int_part <- if (n > e + 1) substr(digits, 1, e + 1) else paste0(digits, strrep("0", e + 1 - n))
        frac <- if (n > e + 1) substr(digits, e + 2, n) else "0"
        paste0(sign, int_part, ".", frac)
      } else {
        paste0(sign, "0.", strrep("0", -e - 1), digits)
      }
    } else {
      mant <- if (n > 1) paste0(substr(digits, 1, 1), ".", substr(digits, 2, n)) else digits
      paste0(sign, mant, "e", if (e < 0) "-" else "+", sprintf("%02d", abs(e)))
    }
  }, character(1), USE.NAMES = FALSE)
}

# pandas turns an integral number into an int and leaves the rest float
# (_openpyxl.py, _convert_cell), and the loader then calls str() on it.
cell_as_char <- function(value, kind) {
  out <- rep("", length(value))
  str <- kind == "str"
  out[str] <- value[str]
  num <- kind == "num"
  if (any(num)) {
    x <- as.numeric(value[num])
    integral <- !is.na(x) & is.finite(x) & x == round(x)
    # int(x) of a whole float, then str(): every digit, never an exponent.
    out[num][integral] <- ifelse(x[integral] == 0, "0", sprintf("%.0f", x[integral]))
    out[num][!integral] <- py_float_repr(x[!integral])
  }
  out[kind == "bool"] <- ifelse(value[kind == "bool"] == "TRUE", "True", "False")
  out[kind == "date"] <- value[kind == "date"]
  # "" and errors are NaN to pandas, and NaN becomes "" in a Char column.
  out
}

# float() of the cell, None when empty.
cell_as_num <- function(value, kind, where) {
  if (any(kind == "date")) {
    stop("a date cell in a Num column (", where, "): float() of a datetime fails, ",
         "so the reference would refuse this case.", call. = FALSE)
  }
  out <- rep(NA_real_, length(value))
  out[kind == "num"] <- as.numeric(value[kind == "num"])
  out[kind == "bool"] <- ifelse(value[kind == "bool"] == "TRUE", 1, 0)
  txt <- kind == "str" & nzchar(value %||% "")
  if (any(txt)) {
    parsed <- suppressWarnings(as.numeric(trimws(value[txt])))
    if (anyNA(parsed)) {
      stop("non-numeric text in a Num column (", where, "): '",
           value[txt][is.na(parsed)][1], "'. The reference would refuse this case.", call. = FALSE)
    }
    out[txt] <- parsed
  }
  out
}

# Rows after the last one holding anything are dropped, as pandas does; rows
# in between are kept, empty or not, because the loader keeps them as records.
trim_trailing_rows <- function(sheet) {
  has <- apply(sheet$kind != "empty" & !(sheet$kind == "str" & !nzchar(ifelse(is.na(sheet$value), "", sheet$value))), 1, any)
  last <- if (any(has)) max(which(has)) else 0L
  list(value = sheet$value[seq_len(last), , drop = FALSE], kind = sheet$kind[seq_len(last), , drop = FALSE])
}

# ---- the case ------------------------------------------------------------------

v1_library <- function(sheet) {
  sh <- trim_trailing_rows(sheet)
  text <- function(r, c) {
    if (nrow(sh$value) < r || ncol(sh$value) < c) return("")
    cell_as_char(sh$value[r, c], sh$kind[r, c])
  }
  standard <- trimws(text(2, 1))
  version <- trimws(text(2, 2))
  ct <- character(0)
  if (nrow(sh$value) >= 3) {
    for (r in 3:nrow(sh$value)) {
      a <- trimws(text(r, 1))
      b <- trimws(text(r, 2))
      if (nzchar(a) && nzchar(b) && endsWith(tolower(a), "ct")) ct <- c(ct, paste0(a, "-", b))
    }
  }
  list(standard = standard, version = version, ct = ct)
}

# A dataset sheet: row 1 names, row 2 labels, row 3 types, row 4 lengths, data
# from row 5. A column with no name is skipped, as pandas' "Unnamed: n" columns
# are.
v1_dataset <- function(sheet, where) {
  sh <- trim_trailing_rows(sheet)
  if (nrow(sh$value) < 4) stop("dataset sheet ", where, " has fewer than four header rows", call. = FALSE)
  header <- cell_as_char(sh$value[1, ], sh$kind[1, ])
  if (any(sh$kind[1, ] == "num")) stop("a numeric column name in ", where, call. = FALSE)
  keep <- which(nzchar(header))
  if (anyDuplicated(header[keep])) {
    stop("a repeated column name in ", where, ": pandas would rename it", call. = FALSE)
  }
  data_rows <- if (nrow(sh$value) >= 5) 5:nrow(sh$value) else integer(0)
  vars <- data.frame(variable = header[keep], label = "", type = "", length = "", stringsAsFactors = FALSE)
  cols <- list()
  for (i in seq_along(keep)) {
    j <- keep[[i]]
    vars$label[i] <- cell_as_char(sh$value[2, j], sh$kind[2, j])
    type <- cell_as_char(sh$value[3, j], sh$kind[3, j])
    if (!type %in% c("Char", "Num")) {
      stop("unknown variable type '", type, "' for ", header[[j]], " in ", where,
           ". The reference refuses this case.", call. = FALSE)
    }
    vars$type[i] <- type
    vars$length[i] <- cell_as_char(sh$value[4, j], sh$kind[4, j])
    v <- sh$value[data_rows, j]
    k <- sh$kind[data_rows, j]
    cols[[header[[j]]]] <- if (type == "Num") cell_as_num(v, k, paste(where, header[[j]])) else cell_as_char(v, k)
  }
  list(variables = vars, data = cols, n = length(data_rows))
}

# What the reference expected, in the Dataset,Record,Variable,Value shape of a
# results.csv. Study-level facts go under STUDY with no record, which is how
# CDISC's sheets file them; 1.0 files them under whichever dataset the engine
# visited first.
v1_results_csv <- function(results_json, rule) {
  r <- jsonlite::fromJSON(results_json, simplifyVector = FALSE)
  study_level <- isTRUE(startsWith(rule$rule_type %||% "", "Domain Presence Check"))
  rows <- list()
  add <- function(ds, rec, var, val) {
    rows[[length(rows) + 1]] <<- data.frame(Dataset = ds, Record = rec, Variable = var, Value = val,
                                            stringsAsFactors = FALSE)
  }
  for (d in r$datasets) {
    name <- toupper(sub("[.][^.]*$", "", d$dataset %||% ""))
    status <- d$execution_status %||% ""
    if (identical(status, "execution_error")) {
      add(name, "", "EXECUTION_ERROR", substr(paste(unlist(d$errors), collapse = " "), 1, 200))
      next
    }
    if (!identical(status, "success") || length(d$errors) == 0) {
      # Looked at and found nothing, or not applicable. No row at all, rather
      # than CDISC's `PP,,,` placeholder: the harness reads any row with a
      # dataset as a sheet that expects something, and every 1.0 case lists
      # every dataset, so placeholders would make each one look like it was
      # built to catch a problem.
      next
    }
    for (e in d$errors) {
      rec <- if (is.null(e$row) || study_level) "" else as.character(e$row)
      vals <- e$value %||% list()
      ds <- if (study_level) "STUDY" else name
      if (length(vals) == 0) {
        # A finding that names no variable still has to count as one.
        add(ds, rec, "*", "")
      } else {
        for (v in names(vals)) {
          x <- vals[[v]]
          add(ds, rec, v, if (is.null(x)) "" else paste(unlist(x), collapse = ","))
        }
      }
    }
  }
  if (length(rows) == 0) {
    return(data.frame(Dataset = character(0), Record = character(0), Variable = character(0),
                      Value = character(0)))
  }
  out <- do.call(rbind, rows)
  unique(out)
}

#' Convert one 1.0 case directory into a cdisc-open-rules case directory
#' @param case_dir A `positive/NN` or `negative/NN` directory of core-contributor.
#' @param rule The rule being graded, for how its expected findings are filed.
#' @param out_dir Where to write `data/` and `results/`.
#' @return A list: `library` (standard, version, ct) and `note`.
v1_convert_case <- function(case_dir, rule, out_dir) {
  data_in <- file.path(case_dir, "data")
  books <- sort(list.files(data_in, pattern = "^[^~].*[.]xlsx$"))
  if (length(books) == 0) stop("no workbook in ", data_in, call. = FALSE)
  # The reference loads the first workbook it finds and ignores the rest.
  note <- if (length(books) > 1) paste("more than one workbook; used", books[[1]]) else NA_character_
  sheets <- xl_read(file.path(data_in, books[[1]]))
  if (!"Library" %in% names(sheets)) stop("no Library sheet in ", books[[1]], call. = FALSE)
  if (!"Datasets" %in% names(sheets)) stop("no Datasets sheet in ", books[[1]], call. = FALSE)
  library <- v1_library(sheets[["Library"]])

  data_out <- file.path(out_dir, "data")
  res_out <- file.path(out_dir, "results")
  dir.create(data_out, recursive = TRUE, showWarnings = FALSE)
  dir.create(res_out, recursive = TRUE, showWarnings = FALSE)

  writeLines(c(paste0("PRODUCT=", toupper(library$standard)), paste0("VERSION=", library$version)),
             file.path(data_out, ".env"))
  if (length(library$ct)) writeLines(library$ct, file.path(data_out, "_library_ct.txt"))

  ds_sheet <- trim_trailing_rows(sheets[["Datasets"]])
  head <- cell_as_char(ds_sheet$value[1, ], ds_sheet$kind[1, ])
  fcol <- match("Filename", head)
  lcol <- match("Label", head)
  if (is.na(fcol)) stop("the Datasets sheet has no Filename column in ", books[[1]], call. = FALSE)
  listed <- data.frame(Filename = character(0), Label = character(0), stringsAsFactors = FALSE)
  variables <- list()
  for (r in seq_len(nrow(ds_sheet$value))[-1]) {
    filename <- cell_as_char(ds_sheet$value[r, fcol], ds_sheet$kind[r, fcol])
    # Only datasets listed here AND present as a sheet are loaded.
    if (!nzchar(filename) || !filename %in% names(sheets)) next
    label <- if (is.na(lcol)) "" else cell_as_char(ds_sheet$value[r, lcol], ds_sheet$kind[r, lcol])
    base <- tolower(sub("[.][^.]*$", "", filename))
    ds <- v1_dataset(sheets[[filename]], paste0(books[[1]], " / ", filename))
    listed[nrow(listed) + 1, ] <- c(base, label)
    vars <- ds$variables
    variables[[base]] <- data.frame(dataset = base, variable = vars$variable, label = vars$label,
                                    type = vars$type, length = vars$length, stringsAsFactors = FALSE)
    frame <- if (length(ds$data) == 0) data.table::data.table() else data.table::as.data.table(ds$data)
    if (ncol(frame) > 0) data.table::setnames(frame, vars$variable)
    data.table::fwrite(frame, file.path(data_out, paste0(base, ".csv")), quote = TRUE, na = "")
  }
  data.table::fwrite(listed, file.path(data_out, "_datasets.csv"))
  if (length(variables) == 0) stop("no dataset in ", books[[1]], " is both listed and present", call. = FALSE)
  data.table::fwrite(do.call(rbind, variables), file.path(data_out, "_variables.csv"))

  # The reference runner takes data/define.xml as the define and data/stf.xml
  # as a study tagging file, which is a different input. Only the define is
  # carried over: coreval reads a lone .xml as a define, and has no use for a
  # tagging file yet.
  if (file.exists(file.path(data_in, "define.xml"))) {
    file.copy(file.path(data_in, "define.xml"), file.path(data_out, "define.xml"))
  }

  expected <- v1_results_csv(file.path(case_dir, "results", "results.json"), rule)
  data.table::fwrite(expected, file.path(res_out, "results.csv"))
  list(library = library, note = note)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

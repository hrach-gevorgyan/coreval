#' Read a study into coreval's internal representation
#'
#' Detects whether `path` is a directory of XPT datasets (a real study) or a
#' CORE test-case `data/` directory (`_variables.csv` + one CSV per dataset,
#' usually also `.env` and `_datasets.csv`), and reads either into the same
#' internal representation, so the evaluator never has to know which one it
#' got.
#'
#' Character columns use `""` for blank/missing (never `NA`) to match how
#' SAS XPT round-trips blanks; numeric columns use `NA`. Column types are
#' taken from the source (XPT's own types, or `_variables.csv`'s declared
#' `Char`/`Num`) rather than guessed from the data, so numeric-looking
#' identifiers (e.g. `"007"`) are never silently coerced.
#'
#' @param path Directory path.
#' @return A study object: `list(datasets = <named list of domain ->
#'   list(data, meta, label)>, define, ct = NULL, standard =
#'   list(product, version))`. `define` is the parsed Define-XML if one was
#'   found in `path` and the `xml2` package is installed, and `NULL`
#'   otherwise; `ct` is always `NULL` (controlled terminology is not
#'   bundled). Each `data` is a [data.table::data.table()];
#'   each `meta` is a data.table with columns `variable`, `label`, `type`;
#'   `label` is the dataset's own label (e.g. `"Adverse Events"`), or `NA` if
#'   unavailable. `standard` is the study's declared standard/version (e.g.
#'   `list(product = "SDTMIG", version = "3-4")`), read from a CORE test
#'   case's `.env` file - both `NA` for a real XPT-based study (no `.env`).
#' @examples
#' dir <- tempfile("coreval_study_")
#' dir.create(dir)
#' haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
#' study <- read_study(dir)
#' study$datasets$DM$data
#' unlink(dir, recursive = TRUE)
#' @export
read_study <- function(path) {
  # A missing folder used to read as an empty study, and an empty study checks
  # clean - so a typo in the path reported the data as fine. check_study()
  # already refuses a path it cannot find; read_study() must not be laxer than
  # its sibling.
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("`path` must be a single folder path.", call. = FALSE)
  }
  if (!dir.exists(path)) {
    stop("no such folder: ", path, call. = FALSE)
  }
  if (file.exists(file.path(path, "_variables.csv"))) {
    return(read_study_test_case(path))
  }
  # XPT first when both are present. A folder holding transport files and a
  # Dataset-JSON of the same data is a conversion in progress, and the transport
  # files are the ones a submission is made of.
  if (length(list.files(path, pattern = "[.]xpt$", ignore.case = TRUE)) > 0) {
    return(read_study_xpt(path))
  }
  if (length(list.files(path, pattern = "[.](json|ndjson)$", ignore.case = TRUE)) > 0) {
    return(read_study_dataset_json(path))
  }
  # No datasets in any readable format. read_study_xpt() returns an empty study
  # for this, which is the honest answer, and check_study() refuses to call an
  # empty study clean.
  read_study_xpt(path)
}

#' Undo `fread`'s handling of an escaped quote inside a quoted CSV field
#'
#' RFC 4180 escapes a quote inside a quoted field by doubling it, so
#' `"<ref klass=""Range""/>"` is the value `<ref klass="Range"/>`. `fread` does
#' not collapse the pair when the field contains no separator and no newline:
#' it hands back `<ref klass=""Range""/>`, quotes and all. `utils::read.csv`
#' reads the same file correctly, so this is not ambiguity in the data.
#'
#' The consequence is a wrong value rather than a failure to read, which is why
#' it went unnoticed: a rule matching the value against a pattern gets a
#' definite answer computed from text the file does not contain. Found on
#' CORE-000833, whose values are `usdm:ref` elements full of quoted attributes.
#'
#' Only files that actually contain a doubled quote are re-read, so the common
#' case pays one scan of the raw bytes and nothing else. The re-read is
#' authoritative for character columns only; every type decision stays with the
#' `fread` call, which the rest of this function depends on.
#'
#' @param dt The data.table just read, mutated by reference.
#' @param path The file it came from.
#' @return `invisible(NULL)`; `dt` is modified in place.
#' @noRd
repair_doubled_quotes <- function(dt, path) {
  if (nrow(dt) == 0 || !file.exists(path)) {
    return(invisible(NULL))
  }
  char_cols <- names(dt)[vapply(dt, is.character, logical(1))]
  if (length(char_cols) == 0) {
    return(invisible(NULL))
  }
  affected <- char_cols[vapply(char_cols, function(v) {
    any(grepl('""', dt[[v]], fixed = TRUE), na.rm = TRUE)
  }, logical(1))]
  if (length(affected) == 0) {
    return(invisible(NULL))
  }
  proper <- tryCatch(
    utils::read.csv(path, colClasses = "character", check.names = FALSE,
                    na.strings = character(0)),
    error = function(e) NULL
  )
  if (is.null(proper) || nrow(proper) != nrow(dt)) {
    return(invisible(NULL))
  }
  for (v in intersect(affected, names(proper))) {
    data.table::set(dt, j = v, value = as.character(proper[[v]]))
  }
  invisible(NULL)
}

#' Rewrite `NA` to `""` for every character column of a data.table, in place
#' @param dt A data.table, mutated by reference.
#' @return `invisible(NULL)`; `dt` is modified in place.
#' @noRd
fill_char_blanks <- function(dt) {
  for (v in names(dt)) {
    if (is.character(dt[[v]])) {
      data.table::set(dt, j = v, value = ifelse(is.na(dt[[v]]), "", dt[[v]]))
    }
  }
  invisible(NULL)
}

#' Read a directory of XPT datasets into the internal study representation
#' @param path Directory containing `.xpt` files.
#' @return A study list, see [read_study()].
#' @noRd
read_study_xpt <- function(path) {
  files <- list.files(path, pattern = "\\.xpt$", ignore.case = TRUE, full.names = TRUE)
  datasets <- lapply(files, function(f) build_dataset_from_data_frame(haven::read_xpt(f)))
  names(datasets) <- toupper(tools::file_path_sans_ext(basename(files)))
  list(datasets = datasets, define = read_define_xml(find_define_xml(path)), ct = NULL, standard = list(product = NA_character_, version = NA_character_))
}

#' Convert a data frame into a `list(data, meta)` dataset entry
#'
#' Used for a whole directory of XPT files, and for a single data frame handed
#' straight to [check_dataset()]. Column labels are read from each column's
#' `label` attribute, which `haven` sets and a plain data frame simply lacks.
#'
#' @param raw A data frame, e.g. from [haven::read_xpt()].
#' @return `list(data, meta)`, see [read_study()].
#' @noRd
build_dataset_from_data_frame <- function(raw) {
  dt <- data.table::as.data.table(raw)
  labels <- vapply(raw, function(col) {
    lbl <- attr(col, "label")
    if (is.null(lbl)) NA_character_ else lbl
  }, character(1))

  # A factor is text as far as every rule is concerned, but it is an integer
  # vector underneath, so nzchar()/startsWith() on one is an error rather than
  # a wrong answer - the whole check died with "'nzchar()' requires a
  # character vector". `read.csv(stringsAsFactors = TRUE)` and plenty of older
  # code still hand over factors, so convert rather than refuse.
  for (v in names(dt)) {
    if (is.factor(dt[[v]])) {
      data.table::set(dt, j = v, value = as.character(dt[[v]]))
    }
  }

  fill_char_blanks(dt)

  meta <- data.table::data.table(
    variable = names(dt),
    label = unname(labels[names(dt)]),
    type = vapply(dt, function(col) if (is.character(col)) "Char" else "Num", character(1))
  )

  dataset_label <- attr(raw, "label")
  list(data = dt, meta = meta, label = if (is.null(dataset_label)) NA_character_ else dataset_label)
}

#' Read a CORE test-case `data/` directory into the internal study representation
#' @param path Directory containing `_variables.csv`, one CSV per dataset,
#'   and (usually) `_datasets.csv`.
#' @return A study list, see [read_study()].
#' @noRd
read_study_test_case <- function(path) {
  # strip.white = FALSE for the same reason as build_dataset_from_csv()'s own
  # data read below: fread()'s default trims leading/trailing whitespace,
  # which would silently shorten a `label` value that has a real trailing
  # space in the source data - confirmed against CORE-000019's real fixture,
  # where ML.USUBJID's label is "...Unique Subject " (41 chars, WITH a
  # trailing space) and the rule flags labels longer than 40; stripping that
  # space would wrongly make the label look 40 chars long and miss the
  # violation entirely.
  variables_csv <- data.table::fread(
    file.path(path, "_variables.csv"),
    colClasses = "character", na.strings = character(0), strip.white = FALSE
  )

  # A handful of real CORE test cases ship `_variables.csv` and the per-
  # dataset CSVs but no `_datasets.csv` manifest at all (confirmed against
  # e.g. CORE-000395's own fixtures) - fall back to the dataset names
  # `_variables.csv` itself declares, with no Label available (nothing else
  # names one).
  datasets_csv_path <- file.path(path, "_datasets.csv")
  datasets_csv <- if (file.exists(datasets_csv_path)) {
    data.table::fread(datasets_csv_path, colClasses = "character")
  } else {
    fnames <- unique(variables_csv$dataset)
    data.table::data.table(Filename = fnames, Label = NA_character_)
  }

  datasets <- lapply(seq_len(nrow(datasets_csv)), function(i) {
    build_dataset_from_csv(path, datasets_csv$Filename[i], variables_csv, datasets_csv$Label[i])
  })
  names(datasets) <- toupper(datasets_csv$Filename)

  list(datasets = datasets, define = read_define_xml(find_define_xml(path)), ct = NULL, standard = read_env_standard(path))
}

# A CORE test case's `.env` file declares which standard/version its data
# actually conforms to (e.g. "PRODUCT=SENDIG" / "VERSION=3-1") - confirmed
# this is NOT always SDTMIG even for rules that look SDTM-flavored on their
# face (e.g. CORE-000355's own EX fixture is SENDIG 3.1, not SDTMIG). Library
# metadata operators (required_variables, expected_variables, ...) need this
# to pick the right per-standard table rather than silently assuming SDTMIG.
#
# Also checks `_env` (leading underscore, no dot) as a fallback: this
# package's own bundled test fixtures (tests/testthat/fixtures/) rename
# their copies of upstream's `.env` files to `_env`, since R CMD check
# flags shipped dot-files as "most likely included in error" - excluding
# them via .Rbuildignore instead (tried first) silently broke every
# fixture-based test that depends on the declared standard, since a
# missing `.env` looks identical to "no declaration, default to SDTMIG"
# (confirmed via CORE-000355: with .env excluded, its SENDIG-declared AE
# fixture was silently evaluated as SDTMIG instead, masking the real
# behavior the test exists to verify). A real CDISC CORE test-case
# directory (e.g. a fresh upstream clone) always uses `.env`; `_env` is
# purely this package's own packaging workaround.
#' Parse a CORE test case's `.env` (or `_env`) file into a standard/version pair
#' @param path Study directory (may or may not contain `.env`/`_env`).
#' @return `list(product, version)`, both `NA_character_` if absent/unparseable.
#' @noRd
read_env_standard <- function(path) {
  env_path <- file.path(path, ".env")
  if (!file.exists(env_path)) {
    env_path <- file.path(path, "_env")
  }
  if (!file.exists(env_path)) {
    return(list(product = NA_character_, version = NA_character_))
  }
  lines <- readLines(env_path, warn = FALSE)
  # Only lines that actually assign something. A blank line, a comment, or a
  # stray heading has no "=" at all, and strsplit() would yield a one-element
  # piece for it.
  lines <- lines[grepl("=", lines, fixed = TRUE)]
  if (length(lines) == 0) {
    return(list(product = NA_character_, version = NA_character_))
  }
  kv <- strsplit(lines, "=", fixed = TRUE)
  keys <- toupper(trimws(vapply(kv, function(x) x[1], character(1))))
  # An EMPTY value ("VERSION=") is legitimate and common - strsplit drops the
  # trailing empty piece, so such a line yields a length-1 vector. Returning
  # NULL there (as `if` without `else` does) made vapply reject a zero-length
  # result and abort the ENTIRE study read over one blank field, rather than
  # reporting that one field as absent.
  vals <- trimws(vapply(kv, function(x) {
    if (length(x) >= 2) paste(x[-1], collapse = "=") else NA_character_
  }, character(1)))
  list(
    product = toupper(vals[match("PRODUCT", keys)]),
    version = vals[match("VERSION", keys)]
  )
}

#' Locate a dataset's CSV, tolerating a case difference in the declared name
#'
#' A dataset's NAME comes from `_datasets.csv`'s `Filename` or, when that
#' manifest is absent, from `_variables.csv`'s `dataset` column - in whatever
#' case upstream happened to write it. The FILE beside them carries its own
#' case. The two need not agree: a study can declare `TS` and ship `ts.csv`.
#'
#' `read_xpt_dir()` has always matched case-insensitively
#' (`list.files(ignore.case = TRUE)`); this applies the same rule to the CSV
#' path, which assumed the declared case matched the file exactly. On a
#' case-insensitive filesystem (Windows, and macOS by default) that assumption
#' is invisible, because opening `TS.csv` simply returns `ts.csv`. On a
#' case-sensitive one (Linux, so also CRAN's build machines) it is a hard
#' `fread()` error that aborts the whole study read.
#'
#' Falls back to the exact path when there is no unique case-insensitive match,
#' so a missing file still produces `fread()`'s own clear error rather
#' than a silently different one.
#'
#' @param path Study directory.
#' @param fname Dataset name as declared, in any case.
#' @return Path to the CSV to read.
#' @noRd
dataset_csv_path <- function(path, fname) {
  wanted <- paste0(fname, ".csv")
  files <- list.files(path, pattern = "\\.csv$", ignore.case = TRUE)

  # Resolve against the directory listing rather than testing file.exists()
  # on the constructed name. file.exists() is itself case-insensitive on
  # Windows and macOS, so it would answer TRUE for "TS.csv" when the file is
  # ts.csv and hand back a name that does not exist on a case-sensitive
  # filesystem - reintroducing the very platform split this exists to remove.
  # Going through the listing returns the file's REAL name everywhere.
  hit <- files[files == wanted]
  if (length(hit) == 0) {
    hit <- files[tolower(files) == tolower(wanted)]
  }
  if (length(hit) == 1) file.path(path, hit) else file.path(path, wanted)
}

#' Read one test-case dataset CSV, typed per `_variables.csv`
#' @param path Study directory.
#' @param fname Dataset filename (without extension).
#' @param variables_csv Parsed `_variables.csv` table.
#' @param dataset_label This dataset's `_datasets.csv` `Label` value.
#' @return `list(data, meta, label)`, see [read_study()].
#' @noRd
build_dataset_from_csv <- function(path, fname, variables_csv, dataset_label = NA_character_) {
  vmeta <- variables_csv[toupper(variables_csv$dataset) == toupper(fname), ]

  col_classes <- list(
    character = vmeta$variable[vmeta$type == "Char"],
    numeric = vmeta$variable[vmeta$type == "Num"]
  )
  col_classes <- col_classes[lengths(col_classes) > 0]

  # fread()'s default na.strings = "NA" would silently turn a genuine CDISC
  # null-flavor value like TSVALNF = "NA" (real, meaningful text - "Not
  # Applicable") into R's NA, which fill_char_blanks() then rewrites to ""
  # for character columns - indistinguishable from an actually blank field.
  # Numeric columns don't need na.strings at all: fread already parses a
  # genuinely blank numeric field as NA on its own.
  # fread()'s default strip.white = TRUE would also silently trim leading/
  # trailing whitespace from character fields - destroying exactly the kind
  # of data-quality defect CORE conformance rules exist to catch (e.g.
  # CORE-000867's "text variable must not have leading spaces").
  #
  # A dataset can be listed in _datasets.csv with zero matching rows in
  # _variables.csv at all (a real upstream data gap, confirmed for
  # CORE-000094's own "ec" dataset) - fread() errors on an empty-but-typed
  # colClasses list ("colClasses is type list but has no names"), which
  # would otherwise crash the ENTIRE study read over one broken domain.
  # Falling back to auto-detected types for just that one dataset is the
  # only option when upstream's own type declarations are simply absent.
  # `fill` and `header` are both about a CSV whose rows do not all carry the
  # same number of fields, which real exports produce and which fread's
  # defaults handle in two ways that silently lose data:
  #
  #   - a SHORT last row is read as a footer and DISCARDED. CORE-000103's
  #     pr.csv has three records, the third missing its trailing PRSCAT, and
  #     coreval saw two. A violation on that row could never be reported.
  #   - a row with MORE fields than the header makes fread decide the header
  #     is not a header: it invents a `V1` column and names the rest after the
  #     first row's VALUES. The same fixture's ce.csv came back with columns
  #     called `1234.0` and `Fracture` and no CETERM, CECAT or CESCAT at all,
  #     so every rule about them found nothing and looked clean.
  #
  # fill = TRUE pads a short row with NA instead of dropping it, which is also
  # what the reference reads through pandas, and header = TRUE stops the first
  # line being anything but the header.
  #
  # sep = "," is not redundant next to them. fread re-runs separator detection
  # under fill, and these files carry trailing spaces inside fields
  # ("STUDYID ,DOMAIN ,"), so on CORE-000549's sj.csv it chose WHITESPACE and
  # returned 13 columns named V1..V13 from a file whose every line has ten
  # comma-separated fields. The rule then found no RSTGCD and reported nothing.
  # These files are comma-separated by definition; there is nothing to detect.
  fread_args <- list(
    dataset_csv_path(path, fname),
    na.strings = character(0), strip.white = FALSE,
    fill = TRUE, header = TRUE, sep = ","
  )
  if (length(col_classes) > 0) {
    fread_args$colClasses <- col_classes
  }
  # fread warns "Attempt to override column <X> of inherent type 'string'
  # down to 'float64' ignored" when a column declared Num holds a value it
  # reads as text - SAS's "." missing token being the usual cause. The
  # coercion immediately below handles exactly that case properly, so the
  # warning is noise here rather than information; nothing else fread has to
  # say is suppressed.
  dt <- withCallingHandlers(
    do.call(data.table::fread, fread_args),
    warning = function(w) {
      if (grepl("Attempt to override column", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
  repair_doubled_quotes(dt, dataset_csv_path(path, fname))

  # A column declared Num whose data contains SAS's own numeric-missing token
  # (a lone ".") comes back as character: fread reads "." as a string, and
  # colClasses cannot down-cast an inherently-string column to double - it
  # warns and leaves it alone. The column then silently stays character
  # despite being declared numeric, which is the kind of quiet type drift a
  # conformance check should never inherit. Confirmed against CORE-000183's
  # own fixture, where pc.PCSTRESN is declared Num and every value is ".".
  #
  # "." and "" both mean missing for a numeric variable, so they become NA
  # and the column is coerced explicitly. Anything else that will not parse
  # is left alone rather than destroyed - a declared-Num column carrying real
  # text is itself a finding, and silently turning it into NA would hide it.
  declared_num <- vmeta$variable[vmeta$type == "Num"]
  for (v in intersect(declared_num, names(dt))) {
    col <- dt[[v]]
    if (!is.character(col)) {
      next
    }
    blank <- trimws(col) %in% c(".", "")
    parsed <- suppressWarnings(as.numeric(ifelse(blank, NA_character_, col)))
    if (all(is.na(parsed) == (blank | is.na(col)))) {
      data.table::set(dt, j = v, value = parsed)
    }
  }

  fill_char_blanks(dt)

  meta <- data.table::data.table(
    variable = vmeta$variable,
    label = vmeta$label,
    type = vmeta$type
  )

  list(data = dt, meta = meta, label = dataset_label)
}

#' Read a study into coreval's internal representation
#'
#' Detects whether `path` is a directory of XPT datasets (a real study) or a
#' CORE test-case `data/` directory (`.env` + `_datasets.csv` +
#' `_variables.csv` + one CSV per dataset), and reads either into the same
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
#'   list(data, meta)>, define = NULL, ct = NULL)`. Each `data` is a
#'   [data.table::data.table()]; each `meta` is a data.table with columns
#'   `variable`, `label`, `type`.
#' @export
read_study <- function(path) {
  if (file.exists(file.path(path, "_datasets.csv"))) {
    read_study_test_case(path)
  } else {
    read_study_xpt(path)
  }
}

read_study_xpt <- function(path) {
  files <- list.files(path, pattern = "\\.xpt$", ignore.case = TRUE, full.names = TRUE)
  datasets <- lapply(files, function(f) build_dataset_from_xpt(haven::read_xpt(f)))
  names(datasets) <- toupper(tools::file_path_sans_ext(basename(files)))
  list(datasets = datasets, define = NULL, ct = NULL)
}

build_dataset_from_xpt <- function(raw) {
  dt <- data.table::as.data.table(raw)
  labels <- vapply(raw, function(col) {
    lbl <- attr(col, "label")
    if (is.null(lbl)) NA_character_ else lbl
  }, character(1))

  for (v in names(dt)) {
    if (is.character(dt[[v]])) {
      data.table::set(dt, j = v, value = ifelse(is.na(dt[[v]]), "", dt[[v]]))
    }
  }

  meta <- data.table::data.table(
    variable = names(dt),
    label = unname(labels[names(dt)]),
    type = vapply(dt, function(col) if (is.character(col)) "Char" else "Num", character(1))
  )

  list(data = dt, meta = meta)
}

read_study_test_case <- function(path) {
  datasets_csv <- data.table::fread(file.path(path, "_datasets.csv"), colClasses = "character")
  variables_csv <- data.table::fread(file.path(path, "_variables.csv"), colClasses = "character")

  datasets <- lapply(datasets_csv$Filename, function(fname) {
    build_dataset_from_csv(path, fname, variables_csv)
  })
  names(datasets) <- toupper(datasets_csv$Filename)

  list(datasets = datasets, define = NULL, ct = NULL)
}

build_dataset_from_csv <- function(path, fname, variables_csv) {
  vmeta <- variables_csv[toupper(variables_csv$dataset) == toupper(fname), ]

  col_classes <- list(
    character = vmeta$variable[vmeta$type == "Char"],
    numeric = vmeta$variable[vmeta$type == "Num"]
  )
  col_classes <- col_classes[lengths(col_classes) > 0]

  dt <- data.table::fread(file.path(path, paste0(fname, ".csv")), colClasses = col_classes)

  for (v in names(dt)) {
    if (is.character(dt[[v]])) {
      data.table::set(dt, j = v, value = ifelse(is.na(dt[[v]]), "", dt[[v]]))
    }
  }

  meta <- data.table::data.table(
    variable = vmeta$variable,
    label = vmeta$label,
    type = vmeta$type
  )

  list(data = dt, meta = meta)
}

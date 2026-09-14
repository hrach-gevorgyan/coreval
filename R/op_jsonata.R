# 96 rules state their whole check as a JSONata expression over the study
# document rather than as the Check/Operations structure the rest use. Nothing
# here is per-rule: the expression is data like any other rule, and this file
# is the operator that runs it.

#' Can JSONata rules be evaluated in this session?
#'
#' Both packages are `Suggests`. Without them a JSONata rule is skipped naming
#' what is missing, the same as a rule needing `xml2` on a machine without it.
#'
#' @return `TRUE` when the evaluator and a JSON parser are both installed.
#' @noRd
jsonata_available <- function() {
  requireNamespace("QuickJSR", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE)
}

#' CDISC's JSONata utility functions, assembled into a prelude
#'
#' The expressions call `$utils.sift_tree(...)` and `$utils.parse_refs(...)`,
#' which are not part of JSONata: CDISC ships them as `.jsonata` files and its
#' engine glues them onto the front of every expression at run time
#' (`jsonata_processor.py`: `get_all_custom_functions`). Each file is an object
#' literal, so its outer braces come off and the bodies are joined into one
#' object bound to `$utils`.
#'
#' Assembled from the bundled files rather than baked in as a string, so
#' re-vendoring CDISC's copies is the only step needed to follow a change.
#'
#' @return A single string ending in `;`, or `""` if the files are not installed.
#' @noRd
jsonata_prelude <- function() {
  if (!is.null(.coreval_env$jsonata_prelude)) {
    return(.coreval_env$jsonata_prelude)
  }
  dir <- system.file("extdata", "jsonata", package = "coreval")
  files <- if (nzchar(dir)) sort(Sys.glob(file.path(dir, "*.jsonata"))) else character(0)
  if (length(files) == 0) {
    stop("the bundled JSONata utility functions are not installed with this ",
         "build of the package", call. = FALSE)
  }
  bodies <- vapply(files, function(path) {
    text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    # First "{" and last "}" removed, which is what the reference does to turn
    # each file's object literal into a fragment that can be joined with the
    # others.
    text <- sub("{", "", text, fixed = TRUE)
    close_at <- gregexpr("}", text, fixed = TRUE)[[1]]
    if (identical(close_at[[1]], -1L)) {
      stop("JSONata utility file has no closing brace: ", basename(path),
           call. = FALSE)
    }
    last <- max(close_at)
    paste0(substr(text, 1, last - 1), substr(text, last + 1, nchar(text)))
  }, character(1))
  .coreval_env$jsonata_prelude <-
    paste0("$utils:={\n", paste(bodies, collapse = ",\n"), "\n};\n")
  .coreval_env$jsonata_prelude
}

# Loaded into the engine once, beside the evaluator.
#
# `addPaths` is the reference's `add_json_pointer_paths`
# (jsonata_dataset_builder.py): every OBJECT in the document gets a `_path`
# holding its JSON Pointer, and arrays get none. The expressions read that
# `_path` to say which record they are reporting, so without it a rule parses,
# evaluates, and quietly returns nothing.
#
# `coreval_run` returns JSON rather than a value, so a result of any shape
# crosses back in one piece. A single object becomes a one-element list, which
# is what the reference does with a non-list result.
JSONATA_SHIM <- "
function addPaths(node, path) {
  if (node === null || typeof node !== 'object') { return; }
  if (Array.isArray(node)) {
    for (var i = 0; i < node.length; i++) { addPaths(node[i], path + '/' + i); }
    return;
  }
  node._path = path;
  for (var k in node) {
    if (k !== '_path' && Object.prototype.hasOwnProperty.call(node, k)) {
      addPaths(node[k], path + '/' + k);
    }
  }
}
function coreval_run(expr, inputJson) {
  var input, compiled;
  try { input = JSON.parse(inputJson); addPaths(input, ''); }
  catch (e) { return JSON.stringify({stage: 'input', err: String(e && e.message || e)}); }
  try { compiled = jsonata(expr); }
  catch (e) { return JSON.stringify({stage: 'parse', err: String(e && e.message || e)}); }
  try {
    var out = compiled.evaluate(input);
    if (out === undefined || out === null) { out = []; }
    if (!Array.isArray(out)) { out = [out]; }
    return JSON.stringify({stage: 'ok', results: out});
  } catch (e) { return JSON.stringify({stage: 'eval', err: String(e && e.message || e)}); }
}
"

#' The JavaScript context, built on first use
#'
#' Parsing 76 KB of evaluator on every rule would dominate the run, so the
#' context is kept for the session. It holds no study data between calls: the
#' document goes in as an argument and the result comes straight back.
#'
#' @return A `QuickJSR::JSContext`.
#' @noRd
jsonata_context <- function() {
  if (!is.null(.coreval_env$jsonata_context)) {
    return(.coreval_env$jsonata_context)
  }
  if (!jsonata_available()) {
    stop("evaluating a JSONata rule needs the QuickJSR and jsonlite packages, ",
         "which are not installed", call. = FALSE)
  }
  path <- system.file("extdata", "js", "jsonata.min.js", package = "coreval")
  if (!nzchar(path)) {
    stop("the bundled JSONata evaluator is not installed with this build of ",
         "the package", call. = FALSE)
  }
  ctx <- QuickJSR::JSContext$new()
  ctx$source(file = path)
  ctx$source(code = JSONATA_SHIM)
  .coreval_env$jsonata_context <- ctx
  ctx
}

#' Evaluate one JSONata rule against a study document
#'
#' The expression is wrapped the way the reference wraps it: the utility
#' prelude and the rule's own expression inside one set of parentheses, which
#' is what lets the prelude's `:=` binding be in scope for the expression.
#'
#' A parse or evaluation failure raises rather than returning no findings.
#' `check_study()` records that as a SKIPPED row carrying the message, so a
#' malformed expression reads as a rule that could not run and not as a study
#' with nothing wrong with it.
#'
#' @param rule A rule whose `check` is a JSONata expression string.
#' @param document The study document as JSON text.
#' @return A list of result objects, each a named list. Empty when the rule
#'   found nothing.
#' @noRd
evaluate_jsonata_rule <- function(rule, document) {
  if (!is.character(rule$check) || length(rule$check) != 1L) {
    stop("a JSONata rule's check must be a single expression", call. = FALSE)
  }
  ctx <- jsonata_context()
  expression <- paste0("(\n", jsonata_prelude(), rule$check, "\n)")
  raw <- ctx$call("coreval_run", expression, document)
  answer <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
  if (!identical(answer$stage, "ok")) {
    stop("JSONata rule could not be ",
         switch(answer$stage, input = "given its study document",
                parse = "parsed", "evaluated"),
         ": ", answer$err, call. = FALSE)
  }
  answer$results
}

#' The entity and record a JSONata result names
#'
#' A result is an object the rule's own expression built, so its shape is the
#' rule's business rather than this package's. Only the keys the reference
#' reads are given a meaning here (`jsonata_processor.py`): the entity comes
#' from `entity`, `dataset` or `instanceType`, whichever is present, and the
#' location from `path` or `_path`. Everything else in the object is a reported
#' attribute and is carried through as written.
#'
#' @param result One result object.
#' @return A list with `entity`, `path` and `attributes`.
#' @noRd
jsonata_result_parts <- function(result) {
  pick <- function(...) {
    for (key in c(...)) {
      value <- result[[key]]
      if (!is.null(value) && length(value) == 1L && nzchar(as.character(value))) {
        return(as.character(value))
      }
    }
    NA_character_
  }
  list(
    entity = pick("entity", "dataset", "instanceType"),
    path = pick("path", "_path"),
    attributes = result[setdiff(names(result), c("entity", "dataset", "path", "_path"))]
  )
}

#' Findings from one JSONata rule, in the shape a USDM report states them
#'
#' USDM findings are `path, attribute, value` rather than the
#' `Dataset, Record, Variable, Value` a tabular domain produces, because a USDM
#' finding names a place in a document graph and not a row of a table. The
#' rule's own expression decides which attributes it reports; they are carried
#' through under the names it gave them.
#'
#' A rule's declared output variables are the attributes a report shows, the
#' way the reference's report does: the expression may build more (an `id`, an
#' `instanceType`) to locate the record, and those are not findings in
#' themselves. A rule that declares none reports everything it built.
#'
#' @param rule A JSONata rule.
#' @param study A study read from a USDM document.
#' @return A [data.table::data.table()] with `entity`, `path`, `attribute` and
#'   `value`.
#' @noRd
jsonata_findings <- function(rule, study) {
  if (is.null(study$document)) {
    stop("a JSONata rule is written against a USDM study document, and this ",
         "study is not one", call. = FALSE)
  }
  wanted <- as.character(unlist(rule$outcome[["Output Variables"]]))
  results <- evaluate_jsonata_rule(rule, study$document)
  rows <- lapply(results, function(result) {
    parts <- jsonata_result_parts(result)
    attributes <- parts$attributes
    # Every declared output variable, blank where this result lacks it. That is
    # how the reference writes them, and dropping the absent ones instead lost
    # whole findings: a result carrying none of its rule's declared variables
    # vanished from the report, and three rules stopped matching their sheets.
    if (length(wanted) > 0) {
      attributes <- stats::setNames(
        lapply(wanted, function(w) if (w %in% names(attributes)) attributes[[w]] else ""),
        wanted
      )
    }
    if (length(attributes) == 0) {
      return(NULL)
    }
    data.table::data.table(
      entity = parts$entity,
      path = parts$path,
      attribute = names(attributes),
      value = vapply(attributes, function(v) {
        if (is.null(v) || length(v) == 0) "" else paste(as.character(unlist(v)), collapse = ", ")
      }, character(1))
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) {
    return(data.table::data.table(entity = character(0), path = character(0),
                                  attribute = character(0), value = character(0)))
  }
  data.table::rbindlist(rows)
}

#' The JSONata rules a study should be checked against
#'
#' A JSONata rule asks one question of a whole document, so it is chosen once
#' per study rather than per dataset, and by the same standard, version and
#' deprecation filters as every other rule. Its entity scope is not applied:
#' the expression walks the document itself, which is how the reference runs it
#' and how all 96 are verified against CDISC's answer sheets.
#'
#' @param study A study.
#' @param standard,version The declared standard and version, or `NULL`.
#' @param include_deprecated Whether deprecated rules run.
#' @param types Which document-level rule types to select.
#' @return A character vector of rule ids, empty unless the study is a USDM
#'   document.
#' @noRd
jsonata_rules_for_study <- function(study, standard = NULL, version = NULL,
                                    include_deprecated = FALSE, types = "JSONata") {
  if (is.null(study$document)) {
    return(character(0))
  }
  rules <- .coreval_env$data$rules
  keep <- vapply(rules, function(r) {
    if (!isTRUE(r$rule_type %in% types)) {
      return(FALSE)
    }
    if (!isTRUE(include_deprecated) && identical(r$source, "deprecated_dir")) {
      return(FALSE)
    }
    if (!is.null(standard) && !(toupper(standard) %in% toupper(r$standards))) {
      return(FALSE)
    }
    if (!is.null(standard) && !is.null(version) &&
          !targets_standard_version(r$standard_versions, standard, version)) {
      return(FALSE)
    }
    TRUE
  }, logical(1))
  names(rules)[keep]
}

#' One JSONata rule's findings, in the shape every other check reports
#'
#' `check_study()` reports `Dataset`, `Record`, `Variable` and `Value`, and a
#' USDM finding is a place in a document. The two meet through the entity
#' tables the document is also read into: every row of those carries the JSON
#' Pointer of the object it came from, so a finding's path names a row, and the
#' finding is reported against that entity and that row number. Those are the
#' same numbers the record-data USDM rules report against, so both kinds of
#' finding on one record line up. A path matching no row keeps its entity and
#' is reported with no row number rather than a guessed one.
#'
#' @param rule A JSONata rule.
#' @param study A study read from a USDM document.
#' @param max_records Most records to keep.
#' @return A findings table, with attribute `records_found`.
#' @noRd
jsonata_study_findings <- function(rule, study, max_records = 1000) {
  raw <- jsonata_findings(rule, study)
  entities <- usdm_entities()
  dataset_for <- function(entity) {
    if (is.na(entity) || !nzchar(entity)) {
      return("STUDY")
    }
    mapped <- if (is.null(entities)) NA_character_ else entity_lookup(entities, entity)
    toupper(if (is.na(mapped)) entity else mapped)
  }
  datasets <- vapply(raw$entity, dataset_for, character(1), USE.NAMES = FALSE)
  records <- mapply(function(ds, path) {
    table <- study$datasets[[ds]]$data
    if (is.null(table) || is.na(path) || !("_path" %in% names(table))) {
      return(NA_integer_)
    }
    hit <- match(path, table[["_path"]])
    if (is.na(hit)) NA_integer_ else as.integer(hit)
  }, datasets, raw$path, USE.NAMES = FALSE)

  findings <- data.table::data.table(
    Dataset = datasets,
    Record = as.integer(records),
    Variable = raw$attribute,
    Value = raw$value
  )
  located <- paste(findings$Dataset, findings$Record, raw$path)
  found <- length(unique(located))
  if (found > max_records) {
    findings <- findings[located %in% utils::head(unique(located), max_records)]
  }
  attr(findings, "records_found") <- found
  findings
}

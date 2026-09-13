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
#' @param rule A JSONata rule.
#' @param study A study read from a USDM document.
#' @return A [data.table::data.table()] with `path`, `attribute` and `value`.
#' @noRd
jsonata_findings <- function(rule, study) {
  if (is.null(study$document)) {
    stop("a JSONata rule is written against a USDM study document, and this ",
         "study is not one", call. = FALSE)
  }
  results <- evaluate_jsonata_rule(rule, study$document)
  rows <- lapply(results, function(result) {
    parts <- jsonata_result_parts(result)
    if (length(parts$attributes) == 0) {
      return(NULL)
    }
    data.table::data.table(
      path = parts$path,
      attribute = names(parts$attributes),
      value = vapply(parts$attributes, function(v) {
        if (is.null(v) || length(v) == 0) "" else paste(as.character(unlist(v)), collapse = ", ")
      }, character(1))
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) {
    return(data.table::data.table(path = character(0), attribute = character(0),
                                  value = character(0)))
  }
  data.table::rbindlist(rows)
}

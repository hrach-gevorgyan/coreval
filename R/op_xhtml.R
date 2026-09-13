#' Which bundled XSD answers for a namespace
#'
#' The reference keeps the same one-entry-per-namespace map
#' (`default_file_paths.py`: `LOCAL_XSD_FILE_MAP`). Only the USDM namespace is
#' bundled: it is the one all four rules using this operation declare, and its
#' own schema includes the XHTML modules it needs.
#'
#' @param namespace The namespace URI an Operations entry declares.
#' @return A path relative to `inst/extdata/schema/xml`, or `NULL`.
#' @noRd
xhtml_schema_file <- function(namespace) {
  switch(as.character(namespace %||% "")[[1]],
    "http://www.cdisc.org/ns/usdm/xhtml/v1.0" =
      file.path("cdisc-usdm-xhtml-1.0", "usdm-xhtml-1.0.xsd"),
    NULL
  )
}

#' The compiled schema for a namespace, read on first use
#'
#' Compiling the USDM schema pulls in the whole XHTML 1.1 module set through
#' `xs:include` and `xs:redefine`, which is slow enough to be worth doing once
#' per session rather than once per row.
#'
#' Raises rather than answering when it cannot: no `xml2`, an unknown
#' namespace, or a schema that will not compile. `check_study()` turns that
#' into a SKIPPED row naming the reason. A rule that found no XHTML errors
#' because there was no schema to find them with would read exactly like a
#' clean document.
#'
#' @param namespace The namespace URI an Operations entry declares.
#' @return An `xml_document` holding the schema.
#' @noRd
xhtml_schema <- function(namespace) {
  if (!requireNamespace("xml2", quietly = TRUE)) {
    stop("validating XHTML needs the xml2 package, which is not installed",
         call. = FALSE)
  }
  rel <- xhtml_schema_file(namespace)
  if (is.null(rel)) {
    stop("no bundled schema for the XHTML namespace '", namespace, "'",
         call. = FALSE)
  }
  key <- paste0("xhtml_schema:", rel)
  if (is.null(.coreval_env[[key]])) {
    path <- system.file("extdata", "schema", "xml", rel, package = "coreval")
    if (!nzchar(path)) {
      stop("the bundled XHTML schemas are not installed with this build of ",
           "the package", call. = FALSE)
    }
    .coreval_env[[key]] <- xml2::read_xml(path)
  }
  .coreval_env[[key]]
}

#' The namespace declarations a wrapped fragment needs
#'
#' Built from the schema's own root element, minus the XML Schema namespace
#' itself, which is how the reference builds it. For the USDM schema that is
#' the XHTML default namespace plus the `usdm` prefix, so a fragment using
#' `<usdm:ref>` resolves rather than failing to parse.
#'
#' @param schema The schema document.
#' @return A single string of `xmlns` declarations.
#' @noRd
xhtml_namespace_decl <- function(schema) {
  ns <- xml2::xml_ns(schema)
  keep <- ns[!vapply(ns, function(u) identical(u, "http://www.w3.org/2001/XMLSchema"), logical(1))]
  if (length(keep) == 0) {
    return("")
  }
  # xml2 names the default namespace `d1`, `d2`, ... rather than "". The
  # schema's own target namespace is the document's default here, so the
  # fragment has to declare it as the default too: an element written `<p>` in
  # a narrative fragment is an XHTML p, not a no-namespace one.
  target <- xml2::xml_attr(schema, "targetNamespace")
  decls <- vapply(seq_along(keep), function(i) {
    uri <- keep[[i]]
    prefix <- names(keep)[[i]]
    if (identical(uri, target) || grepl("^d[0-9]+$", prefix)) {
      paste0("xmlns=\"", uri, "\"")
    } else {
      paste0("xmlns:", prefix, "=\"", uri, "\"")
    }
  }, character(1))
  paste(unique(decls), collapse = " ")
}

#' Wrap a narrative fragment in enough XHTML to validate
#'
#' The values these rules check are fragments, not documents: `<p>text</p>`, or
#' bare text with no markup at all. The schema describes a whole `html`
#' element, so a fragment has to be placed inside one before it can be judged.
#' The four cases are the reference's own (`_wrap_xhtml`), in its order.
#'
#' @param text The fragment.
#' @param nsdec Namespace declarations from [xhtml_namespace_decl()].
#' @return The text, wrapped where it needed wrapping.
#' @noRd
xhtml_wrap <- function(text, nsdec) {
  shell <- function(inner) {
    paste0("<html ", nsdec, "><head><title></title></head><body>\n", inner,
           "\n</body></html>")
  }
  if (!startsWith(text, "<")) {
    return(shell(paste0("<div>\n", text, "\n</div>")))
  }
  if (!grepl("<body>", text, fixed = TRUE)) {
    return(shell(text))
  }
  if (!grepl("<head>", text, fixed = TRUE)) {
    if (startsWith(text, "<html")) {
      return(sub("<body>", "<head><title></title></head><body>", text, fixed = TRUE))
    }
    return(shell(text))
  }
  text
}

#' Every XHTML error in one narrative fragment
#'
#' A parse failure and a schema violation are both reported, in that order, the
#' way the reference reports its parser log before its schema log. Blank values
#' have no errors rather than one: an absent narrative is a different fact from
#' a malformed one, and the rules using this ask only about malformed.
#'
#' The messages are not textually identical to the reference's. That one runs
#' libxml2 in recovering mode and reads its error log, so it can name a line
#' and a severity and go on to find later errors in a broken document; xml2
#' surfaces the first parse error as an R condition and nothing after it. Which
#' records a rule flags is unaffected, since one error is as disqualifying as
#' three. What differs is the wording in the report's own value column.
#'
#' @param text One fragment.
#' @param schema The compiled schema.
#' @param nsdec Namespace declarations.
#' @return A character vector of messages, empty when the fragment is clean.
#' @noRd
xhtml_errors <- function(text, schema, nsdec) {
  if (is.na(text) || !nzchar(trimws(text))) {
    return(character(0))
  }
  doc <- tryCatch(xml2::read_xml(xhtml_wrap(trimws(text), nsdec)),
                  error = function(e) e, warning = function(w) w)
  if (inherits(doc, "condition")) {
    return(paste0("Invalid XHTML: ", trimws(conditionMessage(doc))))
  }
  ok <- tryCatch(xml2::xml_validate(doc, schema), error = function(e) e)
  if (inherits(ok, "error")) {
    return(paste0("Invalid XHTML: ", trimws(conditionMessage(ok))))
  }
  if (isTRUE(as.logical(ok))) {
    return(character(0))
  }
  # libxml2 spells an element's namespace as `{uri}local`. The reference
  # rewrites that to the document's own prefix before reporting, so a reader
  # sees `usdm:ref` rather than a URI in braces.
  msgs <- trimws(attr(ok, "errors"))
  ns <- xml2::xml_ns(doc)
  for (i in seq_along(ns)) {
    prefix <- names(ns)[[i]]
    if (grepl("^d[0-9]+$", prefix)) {
      prefix <- ""
    }
    msgs <- gsub(paste0("{", ns[[i]], "}"), if (nzchar(prefix)) paste0(prefix, ":") else "",
                 msgs, fixed = TRUE)
  }
  paste0("Invalid XHTML: ", msgs)
}

#' Validate the XHTML in one column, row by row
#'
#' @param op The Operations entry, carrying `name` and `namespace`.
#' @param dt The dataset being checked.
#' @return A [per_row_binding()] whose value is one character vector per row.
#' @noRd
xhtml_errors_binding <- function(op, dt) {
  target <- as.character(op$name %||% "")[[1]]
  if (is.null(dt) || !(target %in% names(dt))) {
    stop("get_xhtml_errors needs a column '", target,
         "', which this dataset does not have", call. = FALSE)
  }
  schema <- xhtml_schema(op$namespace)
  nsdec <- xhtml_namespace_decl(schema)
  values <- as.character(dt[[target]])
  # One list element per row, kept as a list even where every row holds one
  # error: `empty` reads a zero-length element as blank, which is what turns
  # this into a per-row violation flag, and an atomic column cannot say
  # "no errors" that way.
  per_row_binding(lapply(values, xhtml_errors, schema = schema, nsdec = nsdec))
}

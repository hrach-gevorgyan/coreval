# Reads a define.xml (CDISC Define-XML 2.0/2.1) into two flat tables: one
# row per dataset (ItemGroupDef) and one row per (dataset, variable) pair
# (ItemGroupDef -> ItemRef -> ItemDef). Those feed the rule types that
# compare a study's actual metadata against what define.xml declares.
#
# `xml2` is a SUGGESTS dependency, not an Import, so the package's runtime
# dependency footprint stays `data.table` + `haven` (see the project's own
# hard constraints). Define-XML support is therefore optional: without
# `xml2` installed, read_study() simply reports no define, and the rules
# that need it are skipped with a reason rather than silently evaluating
# against absent columns.
#
# Namespaces are stripped rather than matched. A Define-XML 2.0 file
# declares the `def` prefix as .../ns/def/v2.0 and a 2.1 file as
# .../ns/def/v2.1, so matching on the namespace URI would need a
# version-detecting factory (which is exactly what the reference engine
# builds). Stripping first and matching on local names handles both with
# one code path, since the element and attribute NAMES this reader wants
# (ItemGroupDef, ItemDef, ItemRef, HasNoData, ...) are unchanged between
# the two versions.

# A dataset's UNSPLIT name - the name the domain has when it isn't split
# across files. Per the reference's SDTMDatasetMetadata: the DOMAIN
# column's value, or SUPP/SQ + RDOMAIN for a supplemental dataset, falling
# back to the dataset's own name. `lbae.csv` carrying `DOMAIN=LB` unsplits
# to LB, so it IS split; `ae.csv` carrying `DOMAIN=AE` unsplits to itself,
# so it is not. Distinct from dataset_wildcard(), which returns the AP
# SUFFIX for an Associated Persons dataset (APQS -> QS) where the unsplit
# name is APQS.
#' A dataset's unsplit name (the DOMAIN it belongs to)
#' @param dataset The dataset (`list(data, meta)`).
#' @param domain The dataset's key/file name.
#' @return A single string.
#' @noRd
dataset_unsplit_name <- function(dataset, domain) {
  if (!is.null(dataset$unsplit)) {
    return(dataset$unsplit)
  }
  # Asked about a million times in a study sweep (every rule, every dataset),
  # so during a sweep each dataset's answer is worked out once. A dataset key
  # names one dataset for the whole sweep.
  cache <- .coreval_env$prep_cache
  if (!is.null(cache) && length(domain) == 1L) {
    cache_key <- paste0("unsplit:", domain)
    hit <- cache[[cache_key]]
    if (!is.null(hit)) {
      return(hit)
    }
    answer <- compute_unsplit_name(dataset, domain)
    assign(cache_key, answer, envir = cache)
    return(answer)
  }
  compute_unsplit_name(dataset, domain)
}

compute_unsplit_name <- function(dataset, domain) {
  up <- toupper(domain)
  # Only a value that can be a domain code is taken as one. A file whose
  # label row was saved as data (one of CDISC's own rule fixtures) otherwise
  # belonged to a domain called "DOMAIN ABBREVIATION", had no class, and no
  # class-scoped rule ran on it.
  code_like <- function(x) grepl("^[A-Za-z][A-Za-z0-9]{1,7}$", x)
  dom_col <- dataset$data[["DOMAIN"]]
  if (!is.null(dom_col) && length(dom_col) > 0) {
    first <- trimws(as.character(dom_col[1]))
    if (!is.na(first) && nzchar(first) && code_like(first)) {
      return(toupper(first))
    }
  }
  # A SUPP/SQ dataset has no DOMAIN of its own; it names its parent in
  # RDOMAIN, so SUPPLBAE unsplits to SUPPLB.
  rdom <- dataset$data[["RDOMAIN"]]
  if (grepl("^(SUPP|SQ)", up) && !is.null(rdom) && length(rdom) > 0) {
    first <- trimws(as.character(rdom[1]))
    if (!is.na(first) && nzchar(first) && code_like(first)) {
      prefix <- if (startsWith(up, "SUPP")) "SUPP" else "SQ"
      return(paste0(prefix, toupper(first)))
    }
  }
  up
}

#' Is this dataset one file of a domain split across several?
#' @param dataset The dataset (`list(data, meta)`).
#' @param domain The dataset's key/file name.
#' @return `TRUE` if the dataset's name differs from its unsplit name.
#' @noRd
dataset_is_split <- function(dataset, domain) {
  !identical(toupper(domain), dataset_unsplit_name(dataset, domain))
}

#' A domain's data, whole, however many files it is split across
#'
#' A rule that joins another domain, or computes over one, names it by its
#' domain code. Looked up by file name, LB was never found when it arrived as
#' LBCH and LBHE: every SUPPLB row was reported as pointing at a record that
#' does not exist, and every rule reading LB from another dataset lost it.
#'
#' The parts are stacked once per sweep and kept in the per-run cache.
#'
#' @param study The study object.
#' @param code A domain code, e.g. `"LB"` or `"SUPPLB"`.
#' @return A dataset entry (`list(data, meta, label)`), or `NULL` if the study
#'   has no dataset of that domain.
#' @noRd
domain_dataset <- function(study, code) {
  code <- toupper(code)
  keys <- names(study$datasets)
  parts <- keys[vapply(keys, function(k) {
    identical(dataset_unsplit_name(study$datasets[[k]], k), code)
  }, logical(1))]
  direct <- study$datasets[[code]]
  if (length(parts) <= 1) {
    return(if (!is.null(direct)) direct else if (length(parts) == 1) study$datasets[[parts]] else NULL)
  }
  cache <- .coreval_env$prep_cache
  cache_key <- paste0("domain_dataset:", code)
  if (!is.null(cache) && exists(cache_key, envir = cache, inherits = FALSE)) {
    return(get(cache_key, envir = cache, inherits = FALSE))
  }
  first <- study$datasets[[parts[[1]]]]
  out <- list(
    data = data.table::rbindlist(lapply(parts, function(k) study$datasets[[k]]$data),
                                 use.names = TRUE, fill = TRUE),
    meta = first$meta,
    label = first$label
  )
  if (!is.null(cache)) {
    assign(cache_key, out, envir = cache)
  }
  out
}

#' Is define.xml support available (i.e. is `xml2` installed)?
#' @return `TRUE` if define.xml files can be read.
#' @noRd
define_xml_available <- function() {
  requireNamespace("xml2", quietly = TRUE)
}

#' Locate a define.xml in a study directory
#' @param path Directory to search.
#' @return A single file path, or `NULL` if there is no define.xml.
#' @noRd
find_define_xml <- function(path) {
  files <- list.files(path, pattern = "\\.xml$", ignore.case = TRUE, full.names = TRUE)
  # A study tagging file is not a define, so a folder holding define.xml and
  # stf.xml, or stf.xml alone, never reads the STF as one.
  files <- files[!grepl("^stf", basename(files), ignore.case = TRUE)]
  # A study directory can legitimately contain other XML (a stylesheet, an
  # annotated CRF); match the conventional define*.xml naming first and
  # only fall back to a lone .xml file.
  #
  # define.xml itself wins. Any other choice among several is said aloud: the
  # first in sort order was taken silently, and "define-old.xml" sorts before
  # "define.xml". A define named for its study ("cdiscpilot01-define.xml")
  # beside another XML file was not found at all, and every define rule
  # skipped as if there were none.
  exact <- files[tolower(basename(files)) == "define.xml"]
  if (length(exact) > 0) {
    return(exact[[1]])
  }
  define <- files[grepl("^define", basename(files), ignore.case = TRUE)]
  if (length(define) == 0) {
    define <- files[grepl("define", basename(files), ignore.case = TRUE)]
  }
  if (length(define) > 1) {
    warning("more than one define file in ", basename(path), ": read ", basename(define[[1]]),
            ", not ", paste(basename(define[-1]), collapse = ", "), call. = FALSE)
  }
  if (length(define) > 0) {
    return(define[[1]])
  }
  if (length(files) == 1) files[[1]] else NULL
}

#' First non-empty attribute value from a set of candidate names
#' @param nodes An `xml_nodeset`.
#' @param names Candidate attribute names, tried in order.
#' @return A character vector, one element per node (`NA` where absent).
#' @noRd
xml_attr_any <- function(nodes, names) {
  out <- rep(NA_character_, length(nodes))
  for (nm in names) {
    vals <- xml2::xml_attr(nodes, nm)
    out <- ifelse(is.na(out) & !is.na(vals), vals, out)
  }
  out
}

#' A node's own `Description/TranslatedText` label
#' @param nodes An `xml_nodeset`.
#' @return A character vector of labels, `""` where absent.
#' @noRd
xml_translated_text <- function(nodes) {
  vapply(nodes, function(node) {
    txt <- xml2::xml_find_first(node, "./Description/TranslatedText")
    if (inherits(txt, "xml_missing")) "" else xml2::xml_text(txt)
  }, character(1))
}

#' The label of a dataset or variable, from any Define-XML version
#'
#' Define-XML 2.0 and 2.1 put it in a `Description/TranslatedText` child;
#' Define-XML 1.0 puts it in a `def:Label` attribute. Read as 2.0 only, a 1.0
#' define (CDISC's own pilot submission uses one) parsed without complaint and
#' gave every label as blank, so the rule comparing each variable's label with
#' the define reported every labelled variable in the study.
#'
#' @param nodes An `xml_nodeset` of ItemGroupDef or ItemDef elements.
#' @return A character vector, `""` where no label is given.
#' @noRd
define_label <- function(nodes) {
  label <- xml_translated_text(nodes)
  attr_label <- xml_attr_any(nodes, "Label")
  ifelse(!nzchar(label) & !is.na(attr_label), attr_label, label)
}

#' Where a variable's values came from, from any Define-XML version
#'
#' 2.0 and 2.1 give it as the `Type` of a `def:Origin` child. 1.0 gives it as
#' free text in an `Origin` attribute ("CRF Page 7", "Derived"), so the type is
#' taken from how that text starts, and a value that names none of the types is
#' left unknown rather than guessed.
#'
#' @param items An `xml_nodeset` of ItemDef elements.
#' @return A character vector, `NA` where no origin is given.
#' @noRd
define_origin_type <- function(items) {
  # Matched by local-name(): `def:Origin` keeps its namespace for XPath
  # purposes even after xml_ns_strip(), so a plain "./Origin" finds nothing.
  child <- xml2::xml_attr(
    xml2::xml_find_first(items, "./*[local-name()='Origin']"), "Type"
  )
  text <- trimws(xml2::xml_attr(items, "Origin"))
  types <- c("CRF", "Derived", "Assigned", "Protocol", "eDT", "Predecessor")
  from_text <- vapply(text, function(t) {
    if (is.na(t)) return(NA_character_)
    hit <- types[startsWith(tolower(t), tolower(types))]
    if (length(hit) == 0) NA_character_ else hit[[1]]
  }, character(1), USE.NAMES = FALSE)
  ifelse(is.na(child), from_text, child)
}

#' Convert Define-XML's "Yes"/"No" attribute convention to a logical
#' @param x Character vector.
#' @param default Value to use where the attribute is absent.
#' @return A logical vector.
#' @noRd
yesno_to_logical <- function(x, default = FALSE) {
  ifelse(is.na(x), default, toupper(x) == "YES")
}

#' Read a define.xml into flat dataset-level and variable-level tables
#'
#' @param path Path to a define.xml file.
#' @return `list(datasets, variables, ct_standards)`, each a
#'   [data.table::data.table()], or `NULL` with a warning naming the reason if
#'   the file is present and cannot be read. `datasets` has one row per
#'   `ItemGroupDef`; `variables` one row per (dataset, variable) pair;
#'   `ct_standards` one row per controlled terminology package it declares.
#' @noRd
read_define_xml <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return(NULL)
  }
  # A define.xml that is present but unreadable is NOT the same fact as no
  # define.xml, and returning NULL for both made them indistinguishable. The
  # rules that needed it then skipped for whatever reason came next, which
  # after the define became a source of the CT version meant a corrupt file
  # was reported as "this study does not say which terminology it follows,
  # pass ct_package" - true of the parsed result, and useless to someone whose
  # actual problem is a truncated file. Warn once, at the point the fact is
  # known, naming the file.
  unreadable <- function(why) {
    warning("define.xml found but not read (", why, "): ", basename(path),
            ". Rules that compare against it will be skipped.",
            call. = FALSE)
    NULL
  }
  if (!define_xml_available()) {
    return(unreadable("the 'xml2' package is not installed"))
  }
  # Read the bytes first and parse from memory. xml2::read_xml(<path>) hands
  # libxml2 the filename and lets it open the file itself, and on a parse
  # error that descriptor is not released - a malformed define.xml therefore
  # left an open handle behind, which on Windows keeps the file locked and
  # makes a later unlink() of the study folder fail. Reading first means R
  # owns and closes the connection whatever the parser then does.
  raw <- tryCatch(readBin(path, "raw", file.size(path)), error = function(e) NULL)
  if (is.null(raw)) {
    return(unreadable("the file could not be opened"))
  }
  doc <- tryCatch(xml2::read_xml(raw), error = function(e) conditionMessage(e))
  if (is.character(doc)) {
    return(unreadable(paste0("not well-formed XML: ", trimws(doc))))
  }
  xml2::xml_ns_strip(doc)

  groups <- xml2::xml_find_all(doc, "//ItemGroupDef")
  items <- xml2::xml_find_all(doc, "//ItemDef")
  # Well-formed XML that declares no dataset is not a Define-XML. Structural,
  # and enough for what this reader depends on: validating against CDISC's own
  # schema would mean shipping their XSD, which carries its own terms and is
  # not the MIT-licensed material this package bundles.
  if (length(groups) == 0) {
    # xml_ns_strip() removes only a default namespace. A define written with
    # the ODM namespace as a prefix (<odm:ItemGroupDef>) is not read, and
    # saying it has no ItemGroupDef would be untrue.
    if (length(xml2::xml_find_all(doc, "//*[local-name()='ItemGroupDef']")) > 0) {
      return(unreadable(paste0("its ODM elements carry a namespace prefix (odm:ItemGroupDef), ",
                               "which coreval does not read; write ODM as the default namespace")))
    }
    return(unreadable("no ItemGroupDef elements, so it does not describe any dataset"))
  }

  datasets <- data.table::data.table(
    define_dataset_name = xml_attr_any(groups, c("Name", "SASDatasetName")),
    define_dataset_label = define_label(groups),
    define_dataset_domain = xml2::xml_attr(groups, "Domain"),
    # An attribute up to Define-XML 2.0, a def:Class child element in 2.1.
    define_dataset_class = ifelse(
      is.na(xml_attr_any(groups, "Class")),
      xml2::xml_attr(xml2::xml_find_first(groups, "./*[local-name()='Class']"), "Name"),
      xml_attr_any(groups, "Class")
    ),
    define_dataset_structure = xml_attr_any(groups, "Structure"),
    # def:HasNoData is a Define-XML 2.1 addition; its absence means the
    # dataset is expected to carry data, so the default is FALSE.
    define_dataset_has_no_data = yesno_to_logical(xml_attr_any(groups, "HasNoData")),
    define_dataset_is_non_standard = yesno_to_logical(xml_attr_any(groups, "IsNonStandard")),
    stringsAsFactors = FALSE
  )

  # ItemDef carries a variable's definition; ItemRef attaches it to a
  # dataset (with that dataset's own ordering, mandatory flag and role).
  # Both halves are needed: the label lives on ItemDef, the per-dataset
  # role and HasNoData on ItemRef.
  item_defs <- data.table::data.table(
    oid = xml2::xml_attr(items, "OID"),
    define_variable_name = xml_attr_any(items, c("Name", "SASFieldName")),
    define_variable_label = define_label(items),
    define_variable_data_type = xml2::xml_attr(items, "DataType"),
    define_variable_length = suppressWarnings(as.integer(xml2::xml_attr(items, "Length"))),
    # def:Origin says where a variable's values came from. "Was it collected
    # on the CRF" is spelled differently in the two Define-XML versions -
    # 2.1 uses Origin Type "Collected", 2.0 uses "CRF" - and the reference
    # engine keeps a separate reader per version for exactly this. Both
    # spellings are accepted here instead, in the same spirit as this file's
    # namespace stripping: no version uses both, and the remaining Origin
    # types (Derived, Assigned, Protocol, Predecessor, eDT) are shared, so
    # the union is unambiguous. NA where a variable declares no Origin at
    # all, which is not the same as declaring a non-collected one.
    define_variable_origin_type = define_origin_type(items),
    # def:Origin's Source attribute (Define-XML 2.1: Investigator, Sponsor,
    # Subject, Vendor), which CORE 1.0's CORE-002004 reads. NA without one.
    define_variable_source_type = xml2::xml_attr(
      xml2::xml_find_first(items, "./*[local-name()='Origin']"), "Source"
    ),
    stringsAsFactors = FALSE
  )

  # A variable's codelist C-code, e.g. "C66770". Two hops: the ItemDef's
  # CodeListRef names a CodeList by OID, and that CodeList carries the code
  # as its own `Alias` with Context "nci:ExtCodeID"
  # (`_get_codelist_ccode` in the reference's base_define_xml_reader).
  #
  # `./Alias` is deliberately a DIRECT child: every EnumeratedItem inside a
  # codelist has an nci:ExtCodeID Alias too, one per term, and matching those
  # would pick a term's code instead of the codelist's.
  #
  # "" rather than NA where a variable has no codelist, because that is what
  # the rules test - `define_variable_ccode empty` has to be TRUE for a
  # variable the define declares no codelist for.
  code_lists <- xml2::xml_find_all(doc, "//CodeList")
  codelist_ccode <- stats::setNames(
    vapply(
      code_lists,
      function(cl) {
        alias <- xml2::xml_find_first(cl, "./Alias[@Context='nci:ExtCodeID']")
        if (inherits(alias, "xml_missing")) "" else (xml2::xml_attr(alias, "Name") %||% "")
      },
      character(1)
    ),
    xml2::xml_attr(code_lists, "OID")
  )
  item_codelist_oid <- xml2::xml_attr(
    xml2::xml_find_first(items, "./CodeListRef"), "CodeListOID"
  )
  item_defs$define_variable_ccode <- ifelse(
    is.na(item_codelist_oid), "",
    ifelse(
      is.na(codelist_ccode[item_codelist_oid]), "",
      codelist_ccode[item_codelist_oid]
    )
  )

  # The term codes inside a variable's codelist, as opposed to the codelist's
  # own C-code above. These are the study's own declaration, read straight out
  # of its define.xml; they are not Controlled Terminology and need nothing
  # bundled. A rule asks "is this variable's coded set contained by the CT
  # package's", so the whole set travels as one element per variable, and the
  # column is a list.
  #
  # Three details are the reference's (`_get_codelist_coded_codes`), not
  # choices: both `CodeListItem` and `EnumeratedItem` carry terms and both
  # count, `CodeListItem` first; EVERY `Alias` on an item is taken, with no
  # Context filter, which is deliberately unlike the codelist's own C-code
  # just above where only `nci:ExtCodeID` counts; and a variable with no
  # codelist gets `character(0)`, not NA, so `empty` is TRUE for it.
  codelist_codes <- lapply(code_lists, function(cl) {
    # Two separate searches rather than one `a | b` union: XPath returns a
    # union in document order, and the reference concatenates the two lists
    # with CodeListItem first.
    codes <- c(
      xml2::xml_attr(xml2::xml_find_all(cl, "./CodeListItem/Alias"), "Name"),
      xml2::xml_attr(xml2::xml_find_all(cl, "./EnumeratedItem/Alias"), "Name")
    )
    codes[!is.na(codes)]
  })
  names(codelist_codes) <- xml2::xml_attr(code_lists, "OID")
  # The coded values themselves, in the same order (_get_codelist_coded_values:
  # CodedValue of each CodeListItem, then of each EnumeratedItem). CORE 1.0's
  # CORE-000726 asks whether ETHNIC's codelist offers HISPANIC OR LATINO.
  codelist_values <- lapply(code_lists, function(cl) {
    v <- c(
      xml2::xml_attr(xml2::xml_find_all(cl, "./CodeListItem"), "CodedValue"),
      xml2::xml_attr(xml2::xml_find_all(cl, "./EnumeratedItem"), "CodedValue")
    )
    v[!is.na(v)]
  })
  names(codelist_values) <- xml2::xml_attr(code_lists, "OID")
  item_defs$define_variable_codelist_coded_values <- lapply(
    item_codelist_oid,
    function(oid) {
      if (is.na(oid) || is.null(codelist_values[[oid]])) character(0) else codelist_values[[oid]]
    }
  )
  item_defs$define_variable_codelist_coded_codes <- lapply(
    item_codelist_oid,
    function(oid) {
      if (is.na(oid) || is.null(codelist_codes[[oid]])) character(0) else codelist_codes[[oid]]
    }
  )

  item_defs$define_variable_is_collected <- ifelse(
    is.na(item_defs$define_variable_origin_type),
    NA,
    item_defs$define_variable_origin_type %in% c("Collected", "CRF")
  )

  refs <- lapply(seq_along(groups), function(i) {
    node_refs <- xml2::xml_find_all(groups[[i]], "./ItemRef")
    if (length(node_refs) == 0) {
      return(NULL)
    }
    data.table::data.table(
      define_dataset_name = datasets$define_dataset_name[i],
      oid = xml2::xml_attr(node_refs, "ItemOID"),
      define_variable_order_number = suppressWarnings(as.integer(xml2::xml_attr(node_refs, "OrderNumber"))),
      define_variable_is_mandatory = yesno_to_logical(xml2::xml_attr(node_refs, "Mandatory")),
      define_variable_role = xml2::xml_attr(node_refs, "Role"),
      define_variable_has_no_data = yesno_to_logical(xml_attr_any(node_refs, "HasNoData")),
      # The dataset's key variables, in key order (ItemRef/@KeySequence).
      define_variable_key_sequence = suppressWarnings(as.integer(xml2::xml_attr(node_refs, "KeySequence"))),
      stringsAsFactors = FALSE
    )
  })
  refs <- data.table::rbindlist(Filter(Negate(is.null), refs))

  variables <- if (nrow(refs) == 0) {
    data.table::data.table()
  } else {
    merged <- merge(refs, item_defs, by = "oid", all.x = TRUE, sort = FALSE)
    data.table::setorderv(merged, c("define_dataset_name", "define_variable_order_number"), na.last = TRUE)
    merged$oid <- NULL
    merged
  }

  # Define-XML 2.1 names the terminology the study was built against, in
  # def:Standards: one def:Standard per standard, those with Type="CT"
  # carrying a PublishingSet ("SDTM", "SEND", "DEFINE-XML") and a Version
  # that is the CT release date. "SDTM" + "2020-12-18" is the bundled package
  # sdtmct-2020-12-18. Matched by local-name() for the same reason as
  # def:Origin above: the prefix survives xml_ns_strip() for XPath purposes.
  standards <- xml2::xml_find_all(doc, "//*[local-name()='Standard'][@Type='CT']")
  ct_standards <- if (length(standards) == 0) {
    data.table::data.table(
      publishing_set = character(0), version = character(0), package = character(0)
    )
  } else {
    set <- tolower(trimws(xml2::xml_attr(standards, "PublishingSet") %||% ""))
    version <- trimws(xml2::xml_attr(standards, "Version") %||% "")
    keep <- !is.na(set) & nzchar(set) & !is.na(version) & nzchar(version)
    data.table::data.table(
      publishing_set = set[keep],
      version = version[keep],
      package = paste0(set[keep], "ct-", version[keep]),
      stringsAsFactors = FALSE
    )
  }

  # The external dictionaries the define's codelists name, with the version
  # each cites (CodeList/ExternalCodeList, e.g. MedDRA 26.0).
  ext <- xml2::xml_find_all(doc, "//CodeList/ExternalCodeList")
  external_dictionaries <- data.table::data.table(
    dictionary = xml2::xml_attr(ext, "Dictionary"),
    version = xml2::xml_attr(ext, "Version")
  )
  list(datasets = datasets, variables = variables, ct_standards = ct_standards,
       vlms = define_value_level(doc, groups, item_defs),
       external_dictionaries = external_dictionaries)
}

#' The define's value-level metadata, one row per value-list item
#'
#' Follows CORE 1.0's `extract_value_level_metadata()`
#' (base_define_xml_reader.py): for each dataset variable whose ItemDef has a
#' def:ValueListRef, every ItemRef of that def:ValueListDef with the
#' def:WhereClauseDef it points to. The item's own ItemDef supplies its
#' metadata, named `define_vlm_*` in place of `define_variable_*`, and
#' `where` holds the clause's range checks (variable, comparator, values). An
#' item whose where clause is missing is left out, as there.
#'
#' @param doc The define document, namespaces stripped.
#' @param groups Its ItemGroupDef nodes.
#' @param item_defs The ItemDef table built by read_define_xml().
#' @return A data.table, possibly empty.
#' @noRd
define_value_level <- function(doc, groups, item_defs) {
  local_all <- function(node, name) xml2::xml_find_all(node, paste0(".//*[local-name()='", name, "']"))
  attr_of <- function(nodes, name) {
    plain <- xml2::xml_attr(nodes, name)
    ifelse(is.na(plain), xml2::xml_attr(nodes, paste0("def:", name)), plain)
  }
  item_nodes <- xml2::xml_find_all(doc, "//ItemDef")
  item_name <- stats::setNames(xml_attr_any(item_nodes, c("Name", "SASFieldName")), xml2::xml_attr(item_nodes, "OID"))
  value_list_of <- stats::setNames(
    attr_of(xml2::xml_find_first(item_nodes, "./*[local-name()='ValueListRef']"), "ValueListOID"),
    xml2::xml_attr(item_nodes, "OID")
  )
  lists <- local_all(doc, "ValueListDef")
  wheres <- local_all(doc, "WhereClauseDef")
  where_checks <- lapply(wheres, function(w) {
    checks <- xml2::xml_find_all(w, "./RangeCheck")
    lapply(checks, function(ch) list(
      variable = unname(item_name[attr_of(ch, "ItemOID")]),
      comparator = xml2::xml_attr(ch, "Comparator"),
      values = xml2::xml_text(xml2::xml_find_all(ch, "./CheckValue"))
    ))
  })
  names(where_checks) <- xml2::xml_attr(wheres, "OID")
  list_by_oid <- stats::setNames(lists, xml2::xml_attr(lists, "OID"))
  rows <- list()
  for (g in seq_along(groups)) {
    dataset <- xml2::xml_attr(groups[[g]], "Name")
    if (is.na(dataset)) dataset <- xml2::xml_attr(groups[[g]], "SASDatasetName")
    for (oid in xml2::xml_attr(xml2::xml_find_all(groups[[g]], "./ItemRef"), "ItemOID")) {
      vl <- value_list_of[oid]
      if (is.na(vl) || is.null(list_by_oid[[vl]])) next
      refs <- xml2::xml_find_all(list_by_oid[[vl]], "./ItemRef")
      for (r in seq_along(refs)) {
        wc <- attr_of(xml2::xml_find_first(refs[[r]], "./*[local-name()='WhereClauseRef']"), "WhereClauseOID")
        where <- if (is.na(wc)) NULL else where_checks[[wc]]
        if (is.null(where) || !length(where)) next
        def <- item_defs[item_defs$oid == xml2::xml_attr(refs[[r]], "ItemOID"), ]
        if (nrow(def) == 0) next
        def <- def[1, ]
        def$oid <- NULL
        names(def) <- sub("^define_variable_", "define_vlm_", names(def))
        def$define_vlm_role <- xml2::xml_attr(refs[[r]], "Role")
        def$define_vlm_mandatory <- yesno_to_logical(xml2::xml_attr(refs[[r]], "Mandatory"))
        def$define_dataset_name <- dataset
        def$define_variable_name <- unname(item_name[oid])
        data.table::set(def, j = "where", value = list(list(where)))
        rows[[length(rows) + 1]] <- def
      }
    }
  }
  if (!length(rows)) {
    return(data.table::data.table())
  }
  data.table::rbindlist(rows, use.names = TRUE, fill = TRUE)
}

#' The bundled CT package a study's define.xml declares, or `NULL`
#'
#' Parallel to `ct_package_from_ts()`: the study says which terminology it
#' follows and coreval reads it rather than guessing. A SEND study cites SEND
#' terminology and an SDTM study SDTM's, so the publishing set has to match the
#' standard being checked; the DEFINE-XML set that sits alongside describes the
#' define document itself, not the data, and is never the answer here.
#'
#' @param study Full study object.
#' @return A bundled package name, or `NULL` when the define declares none,
#'   declares one for another standard, or names a release not bundled.
#' @noRd
ct_package_from_define <- function(study) {
  standards <- study$define$ct_standards
  if (is.null(standards) || nrow(standards) == 0) {
    return(NULL)
  }
  product <- toupper(study$standard$product %||% NA_character_)
  family <- if (!is.na(product) && startsWith(product, "SEND")) "send" else "sdtm"
  rows <- standards[standards$publishing_set == family, ]
  if (nrow(rows) == 0) {
    return(NULL)
  }
  # Newest first, so a define citing several releases is read the same way the
  # TS reader resolves a disagreement rather than by document order.
  candidates <- sort(unique(rows$package), decreasing = TRUE)
  hit <- candidates[candidates %in% ct_package_names()]
  if (length(hit) == 0) NULL else hit[[1]]
}

#' Which records a value-level where clause selects
#'
#' CORE 1.0's `where_clause_to_sql()` (metadata/vlm.py): every range check
#' must hold. EQ and NE use the first check value, IN and NOTIN all of them;
#' a missing value equals only an empty check value and satisfies NE and
#' NOTIN; ordering comparators never hold for a missing value. A check naming
#' a variable the dataset lacks, or an unknown comparator, makes the clause
#' untranslatable, and the item is skipped (`NULL`), as it is there.
#'
#' @param where The item's range checks.
#' @param data The dataset's records.
#' @return A logical vector over the records, or `NULL`.
#' @noRd
vlm_where_matches <- function(where, data) {
  keep <- rep(TRUE, nrow(data))
  for (check in where) {
    v <- check$variable
    if (is.null(v) || is.na(v) || !v %in% names(data) || !length(check$values)) {
      return(NULL)
    }
    x <- data[[v]]
    values <- check$values
    cmp <- toupper(check$comparator %||% "")
    if (cmp %in% c("LT", "LE", "GT", "GE")) {
      op <- switch(cmp, LT = `<`, LE = `<=`, GT = `>`, GE = `>=`)
      hit <- if (is.numeric(x)) {
        want <- suppressWarnings(as.numeric(values[[1]]))
        if (is.na(want)) return(NULL)
        op(x, want)
      } else {
        t <- as.character(x)
        t[!is.na(t) & !nzchar(t)] <- NA
        op(t, values[[1]])
      }
      hit <- hit %in% TRUE
    } else if (cmp %in% c("EQ", "NE", "IN", "NOTIN")) {
      if (cmp %in% c("EQ", "NE")) values <- values[1]
      hit <- if (is.numeric(x)) {
        nums <- suppressWarnings(as.numeric(values[nzchar(trimws(values))]))
        (x %in% nums[!is.na(nums)]) | (is.na(x) & any(!nzchar(trimws(values))))
      } else {
        t <- as.character(x)
        t[is.na(t)] <- ""
        t %in% values
      }
      if (cmp %in% c("NE", "NOTIN")) hit <- !hit
    } else {
      return(NULL)
    }
    keep <- keep & hit
  }
  keep
}


#' The study tagging file (stf*.xml) in a folder, or `NULL`
#' @param path A folder.
#' @return A path or `NULL`.
#' @noRd
find_stf_xml <- function(path) {
  files <- list.files(path, pattern = "^stf.*[.]xml$", ignore.case = TRUE, full.names = TRUE)
  if (length(files) > 1) {
    warning("more than one study tagging file in ", basename(path), ": read ",
            basename(files[[1]]), ", not ", paste(basename(files[-1]), collapse = ", "),
            call. = FALSE)
  }
  if (length(files)) files[[1]] else NULL
}

#' Read an eCTD study tagging file into one row per document file tag
#'
#' The shape CORE 1.0 checks (metadata/stf.py, `_build_rows`): for each
#' doc-content of the study-document, in order, one row per file-tag, carrying
#' the study's id and title, the document's title and href, and the tag's
#' name and info-type. A document with no file tag is one row with no tag.
#' CORE-002116 asks whether the tags data-tabulation-dataset-sdtm and
#' data-tabulation-data-definition are present.
#'
#' @param path Path to the STF, or `NULL`.
#' @return A data.table, or `NULL` (with a warning when the file is unreadable).
#' @noRd
read_stf_xml <- function(path) {
  if (is.null(path) || !requireNamespace("xml2", quietly = TRUE)) {
    return(NULL)
  }
  # From memory, as read_define_xml() reads, so a parse error cannot leave
  # the file open and locked on Windows.
  raw <- tryCatch(readBin(path, "raw", file.size(path)), error = function(e) NULL)
  doc <- tryCatch(xml2::read_xml(raw), error = function(e) {
    warning("could not read the study tagging file ", basename(path), ": ", conditionMessage(e),
            call. = FALSE)
    NULL
  })
  if (is.null(doc)) {
    return(NULL)
  }
  xml2::xml_ns_strip(doc)
  first_text <- function(xpath) {
    n <- xml2::xml_find_first(doc, xpath)
    if (inherits(n, "xml_missing")) NA_character_ else xml2::xml_text(n)
  }
  study_id <- first_text("//study-identifier/study-id")
  study_title <- first_text("//study-identifier/title")
  docs <- xml2::xml_find_all(doc, "//study-document//doc-content")
  rows <- lapply(seq_along(docs), function(i) {
    d <- docs[[i]]
    href <- xml2::xml_attr(d, "xlink:href")
    if (is.na(href)) href <- xml2::xml_attr(d, "href")
    tags <- xml2::xml_find_all(d, "./file-tag")
    data.table::data.table(
      study_id = study_id, study_title = study_title, doc_index = i,
      document_title = xml2::xml_text(xml2::xml_find_first(d, "./title")),
      document_href = href,
      file_tag_name = if (length(tags)) xml2::xml_attr(tags, "name") else NA_character_,
      file_tag_info_type = if (length(tags)) xml2::xml_attr(tags, "info-type") else NA_character_
    )
  })
  if (!length(rows)) {
    return(data.table::data.table(study_id = character(0), file_tag_name = character(0)))
  }
  data.table::rbindlist(rows)
}

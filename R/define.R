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
  up <- toupper(domain)
  dom_col <- dataset$data[["DOMAIN"]]
  if (!is.null(dom_col) && length(dom_col) > 0) {
    first <- as.character(dom_col[1])
    if (!is.na(first) && nzchar(first)) {
      return(toupper(first))
    }
  }
  # A SUPP/SQ dataset has no DOMAIN of its own; it names its parent in
  # RDOMAIN, so SUPPLBAE unsplits to SUPPLB.
  rdom <- dataset$data[["RDOMAIN"]]
  if (grepl("^(SUPP|SQ)", up) && !is.null(rdom) && length(rdom) > 0) {
    first <- as.character(rdom[1])
    if (!is.na(first) && nzchar(first)) {
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
  # A study directory can legitimately contain other XML (a stylesheet, an
  # annotated CRF); match the conventional define*.xml naming first and
  # only fall back to a lone .xml file.
  define <- files[grepl("^define", basename(files), ignore.case = TRUE)]
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
#' @return `list(datasets, variables)`, each a [data.table::data.table()], or
#'   `NULL` if `xml2` is unavailable or the file cannot be parsed. `datasets`
#'   has one row per `ItemGroupDef`; `variables` one row per
#'   (dataset, variable) pair.
#' @noRd
read_define_xml <- function(path) {
  if (!define_xml_available() || is.null(path) || !file.exists(path)) {
    return(NULL)
  }
  # Read the bytes first and parse from memory. xml2::read_xml(<path>) hands
  # libxml2 the filename and lets it open the file itself, and on a parse
  # error that descriptor is not released - a malformed define.xml therefore
  # left an open handle behind, which on Windows keeps the file locked and
  # makes a later unlink() of the study folder fail. Reading first means R
  # owns and closes the connection whatever the parser then does.
  raw <- tryCatch(readBin(path, "raw", file.size(path)), error = function(e) NULL)
  if (is.null(raw)) {
    return(NULL)
  }
  doc <- tryCatch(xml2::read_xml(raw), error = function(e) NULL)
  if (is.null(doc)) {
    return(NULL)
  }
  xml2::xml_ns_strip(doc)

  groups <- xml2::xml_find_all(doc, "//ItemGroupDef")
  items <- xml2::xml_find_all(doc, "//ItemDef")
  if (length(groups) == 0) {
    return(NULL)
  }

  datasets <- data.table::data.table(
    define_dataset_name = xml_attr_any(groups, c("Name", "SASDatasetName")),
    define_dataset_label = xml_translated_text(groups),
    define_dataset_domain = xml2::xml_attr(groups, "Domain"),
    define_dataset_class = xml_attr_any(groups, "Class"),
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
    define_variable_label = xml_translated_text(items),
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
    # Matched by local-name(): `def:Origin` keeps its namespace for XPath
    # purposes even after xml_ns_strip(), so a plain "./Origin" finds
    # nothing. The unprefixed ODM elements (./ItemRef above) are unaffected.
    define_variable_origin_type = xml2::xml_attr(
      xml2::xml_find_first(items, "./*[local-name()='Origin']"), "Type"
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

  list(datasets = datasets, variables = variables, ct_standards = ct_standards)
}

#' The bundled CT package a study's define.xml declares, or `NULL`
#'
#' Parallel to [ct_package_from_ts()]: the study says which terminology it
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

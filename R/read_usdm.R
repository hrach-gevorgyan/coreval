# Turning a USDM study document into the per-entity tables the rules are
# written against.
#
# USDM is a graph, and 157 rules are written as ordinary Record Data checks
# over tables of it. CDISC's own harness publishes those tables as CSVs, but no
# user has them: a real study is one JSON document. This is the port of the
# step that gets from one to the other (usdm_data_service.py), and it is a port
# rather than a fresh design because the record numbers a finding carries
# depend on the order the traversal visits nodes in, which is not a free
# choice.
#
# Verified against the reference itself: tests/conformance/dump_usdm_tables.py
# runs CDISC's own service over a document and writes the tables it produces,
# and tests/conformance/compare_usdm_reader.R diffs these against those.

#' Which entity a USDM key or class name belongs to
#'
#' CDISC's own mapping, extracted at build time from `USDM.yaml`. A key like
#' `epochId` names a `StudyEpoch`, and the pseudo-key `` `this` `` names the
#' document wrapper. Five of its entries map to a nested table rather than a
#' name; those are not usable as an entity name and the reference falls back to
#' the key itself, so only the plain ones are bundled and a lookup miss returns
#' its own argument.
#'
#' @return A named character vector, or `NULL` if not installed.
#' @noRd
usdm_entities <- function() {
  if (is.null(.coreval_env$usdm_entities)) {
    path <- system.file("extdata", "usdm_entities.rds", package = "coreval")
    if (!nzchar(path)) {
      return(NULL)
    }
    .coreval_env$usdm_entities <- readRDS(path)
  }
  .coreval_env$usdm_entities
}

#' Look one key up in the entity map
#'
#' `entities[[key]]` raises "subscript out of bounds" for a name a named
#' character vector does not carry, rather than returning `NULL`, so every
#' lookup goes through `match()`. Most keys in a real document are not in the
#' map, which is the ordinary case rather than an error: the reference's own
#' lookups are `get(key, key)`.
#'
#' @param entities The bundled map.
#' @param key A key or class name.
#' @return The mapped entity, or `NA_character_`.
#' @noRd
entity_lookup <- function(entities, key) {
  if (length(key) != 1L || is.na(key)) {
    return(NA_character_)
  }
  at <- match(key, names(entities))
  if (is.na(at)) NA_character_ else unname(entities[[at]])
}

#' Is this parsed JSON value an object rather than an array?
#'
#' `jsonlite` reads a JSON object as a named list and an array as an unnamed
#' one, which is the only thing that separates `{}` from `[]` once both are
#' empty lists.
#'
#' @param x A parsed value.
#' @return `TRUE` for a JSON object.
#' @noRd
is_json_object <- function(x) is.list(x) && !is.null(names(x))

#' Is this parsed JSON value an array?
#' @param x A parsed value.
#' @return `TRUE` for a JSON array.
#' @noRd
is_json_array <- function(x) is.list(x) && is.null(names(x))

#' Every node the reference's traversal visits, in its order
#'
#' The reference walks the document with the JSONPath query `$..*`. In that
#' library `*` matches an object's KEYS and matches nothing on an array, while
#' `..` descends through objects and arrays alike. So each node contributes its
#' own object children first, and then each child's own results in turn: not
#' breadth-first and not depth-first, but a level of each subtree at a time.
#'
#' The order is not cosmetic. It fixes the order of the records in each entity's
#' table, which fixes the record number a finding is reported against, so a
#' plainer walk would produce right findings against wrong records.
#'
#' Each node also carries the object that ENCLOSES it, which is the parent the
#' reference means. It derives that parent from the path, by dropping the last
#' dotted segment, so the parent of `a.b[0]` is `a` and not the array `a.b`.
#' The enclosing object is the same thing and the walk already has it, which
#' saves re-walking the document from the root once per record: on a real study
#' that alone was most of the time this takes.
#'
#' @param doc The parsed document.
#' @return A list of `list(path, value, key, parent)`, `key` being the trailing
#'   path segment with any `[i]` removed.
#' @noRd
usdm_traversal <- function(doc) {
  out <- vector("list", 1024L)
  n <- 0L
  push <- function(path, value, key, parent) {
    n <<- n + 1L
    if (n > length(out)) {
      length(out) <<- 2L * length(out)
    }
    out[[n]] <<- list(path = path, value = value, key = key, parent = parent)
  }
  walk <- function(node, path, enclosing) {
    if (is_json_object(node)) {
      keys <- names(node)
      child_paths <- if (nzchar(path)) paste0(path, ".", keys) else keys
      for (i in seq_along(keys)) {
        push(child_paths[[i]], node[[i]], keys[[i]], node)
      }
      for (i in seq_along(keys)) {
        walk(node[[i]], child_paths[[i]], node)
      }
    } else if (is_json_array(node)) {
      # An array is not a path segment of its own, so its elements keep the
      # array's own enclosing object as their parent.
      for (i in seq_along(node)) {
        walk(node[[i]], paste0(path, "[", i - 1L, "]"), enclosing)
      }
    }
  }
  walk(doc, "", NULL)
  length(out) <- n
  out
}

#' Every object in the document that carries an `id`, keyed by it
#'
#' A USDM document is a graph written as a tree: a key ending in `Id` or `Ids`
#' holds another object's id rather than the object. Resolving one is what makes
#' a record a `reference` rather than a `definition`.
#'
#' @param doc The parsed document.
#' @return A named list of objects.
#' @noRd
usdm_id_lookup <- function(doc) {
  found <- new.env(parent = emptyenv(), hash = TRUE)
  stack <- list(doc)
  while (length(stack) > 0) {
    current <- stack[[length(stack)]]
    stack[[length(stack)]] <- NULL
    if (is_json_object(current)) {
      id <- current[["id"]]
      if (is.character(id) && length(id) == 1L && !is.na(id)) {
        assign(id, current, envir = found)
      }
      stack <- c(stack, unname(current))
    } else if (is_json_array(current)) {
      stack <- c(stack, current)
    }
  }
  found
}

#' The entity a value belongs to
#'
#' An object says so itself in `instanceType`; where it does not, the key that
#' held it is used instead. A primitive is named after its own type, which is
#' why a real USDM document produces entities called `str` and `NoneType`
#' alongside `Organization`. Those are the reference's own, not an artefact:
#' rules scope to the named entities and the rest are simply never selected.
#'
#' @param value The node's value.
#' @param key The key that held it.
#' @param entities The bundled entity map.
#' @return An entity name.
#' @noRd
usdm_entity_name <- function(value, key, entities) {
  api_type <- if (is_json_object(value)) {
    instance <- value[["instanceType"]]
    if (is.character(instance) && length(instance) == 1L) instance else key
  } else if (is.null(value)) {
    "NoneType"
  } else if (is.logical(value)) {
    "bool"
  } else if (is.character(value)) {
    "str"
  } else if (is.numeric(value)) {
    if (is.integer(value)) "int" else "float"
  } else {
    "str"
  }
  mapped <- entity_lookup(entities, api_type)
  if (is.na(mapped)) api_type else mapped
}

#' A path's JSON Pointer form
#'
#' `study.versions[0].organizations[1]` is `/study/versions/0/organizations/1`.
#' @param path A dotted path.
#' @return A JSON Pointer.
#' @noRd
usdm_pointer <- function(path) {
  pointer <- gsub(".", "/", path, fixed = TRUE)
  pointer <- gsub("\\[([0-9]+)\\]", "/\\1", pointer)
  paste0("/", pointer)
}

#' The path of a path's parent
#' @param path A dotted path.
#' @return The parent's path, or `NA` when there is none.
#' @noRd
usdm_parent_path <- function(path) {
  parts <- strsplit(path, ".", fixed = TRUE)[[1]]
  if (length(parts) < 2L) NA_character_ else paste(parts[-length(parts)], collapse = ".")
}

#' Flatten one record's own values
#'
#' Dotted column names for nested objects, and a nested object or array becomes
#' a single boolean saying whether it holds anything. Arrays are not descended
#' into; objects are. A record that is not an object at all has one column,
#' `value`.
#'
#' @param value The record's value.
#' @param prefix Column-name prefix for a nested object.
#' @return A named list of scalars.
#' @noRd
usdm_record_data <- function(value, prefix = "") {
  if (!is_json_object(value)) {
    return(stats::setNames(list(usdm_scalar(value)), "value"))
  }
  out <- list()
  keys <- names(value)
  for (i in seq_along(keys)) {
    child <- value[[i]]
    name <- paste0(prefix, keys[[i]])
    out[[name]] <- if (is.list(child)) length(child) > 0L else usdm_scalar(child)
    if (is_json_object(child)) {
      out <- c(out, usdm_record_data(child, paste0(name, ".")))
    }
  }
  out
}

#' One cell's value, as a length-one atom
#' @param x A parsed scalar.
#' @return A length-one vector.
#' @noRd
usdm_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) NA_character_ else x[[1]]
}

#' Build every entity table in a USDM document
#'
#' @param doc The parsed document.
#' @return A named list of `list(data, meta, label)` entries.
#' @noRd
usdm_datasets <- function(doc) {
  entities <- usdm_entities()
  if (is.null(entities)) {
    stop("the bundled USDM entity map is not installed with this build of the ",
         "package", call. = FALSE)
  }
  lookup <- usdm_id_lookup(doc)
  nodes <- usdm_traversal(doc)

  # A node whose value is an array contributes its ELEMENTS, not itself: the
  # reference's traversal never yields an array's elements, so they are added
  # here, in place, which is what keeps them in traversal order.
  records <- vector("list", length(nodes))
  count <- 0L
  add <- function(value, key, path, parent) {
    kind <- "definition"
    if (is.character(value) && length(value) == 1L && !is.na(value) &&
          nzchar(value) && (endsWith(key, "Id") || endsWith(key, "Ids"))) {
      # mget(), not exists()/get(): an id is arbitrary text from the document
      # and `exists("")` is an error rather than FALSE.
      definition <- mget(value, envir = lookup, ifnotfound = list(NULL),
                         inherits = FALSE)[[1]]
      if (!is.null(definition)) {
        value <- definition
        kind <- "reference"
      }
    }
    count <<- count + 1L
    if (count > length(records)) {
      length(records) <<- 2L * length(records)
    }
    records[[count]] <<- list(value = value, key = key, path = path,
                              kind = kind, parent = parent)
  }
  for (node in nodes) {
    if (is_json_array(node$value)) {
      for (i in seq_along(node$value)) {
        # An element's path-parent is the array's, not the array itself.
        add(node$value[[i]], node$key, paste0(node$path, "[", i - 1L, "]"),
            node$parent)
      }
    } else {
      add(node$value, node$key, node$path, node$parent)
    }
  }
  length(records) <- count

  entity_of <- vapply(records, function(r) {
    name <- usdm_entity_name(r$value, r$key, entities)
    # The reference folds any casing of "code" onto the one entity name.
    if (identical(tolower(name), "code")) "Code" else name
  }, character(1))

  wrapper <- entity_lookup(entities, "`this`")
  built <- lapply(split(seq_along(records), entity_of), function(idx) {
    rows <- lapply(idx, function(i) {
      r <- records[[i]]
      c(usdm_record_metadata(r, entities, wrapper), usdm_record_data(r$value))
    })
    build_dataset_from_records(rows)
  })
  # split() sorts its groups; traversal order within each entity is what
  # matters and is preserved, but the entity ORDER should be first-seen, the
  # way the reference's index has it.
  built <- built[unique(entity_of)]
  # Upper-cased, the way every other reader here names a dataset and the way
  # the rules' own scope matching and the answer sheets spell an entity.
  names(built) <- toupper(names(built))
  built
}

#' The parent columns every USDM record carries
#'
#' `parent_entity`, `parent_id` and `parent_rel` say what this record hangs off
#' and under which key, and `rel_type` says whether it was written out in place
#' or referenced by id. Rules read all four.
#'
#' @param record One record from [usdm_datasets()].
#' @param entities The entity map.
#' @param wrapper The entity name for a top-level attribute.
#' @return A named list of four values plus `_path`.
#' @noRd
usdm_record_metadata <- function(record, entities, wrapper) {
  parent_entity <- ""
  parent_id <- ""
  if (grepl(".", record$path, fixed = TRUE)) {
    parent <- record$parent
    if (is_json_object(parent)) {
      instance <- parent[["instanceType"]]
      if (is.character(instance) && length(instance) == 1L && nzchar(instance)) {
        mapped <- entity_lookup(entities, instance)
        parent_entity <- if (is.na(mapped)) instance else mapped
        id <- parent[["id"]]
        parent_id <- if (is.character(id) && length(id) == 1L) id else ""
      }
    }
  }
  without_index <- sub("\\[[0-9]+\\]$", "", record$path)
  parent_rel <- if (grepl(".", without_index, fixed = TRUE)) {
    sub("^.*\\.", "", without_index)
  } else {
    without_index
  }
  # A top-level attribute of the document hangs off the wrapper, not off an
  # entity.
  if (startsWith(record$path, "`this`") || !grepl(".", record$path, fixed = TRUE)) {
    parent_entity <- wrapper
  }
  if (!nzchar(parent_entity)) {
    by_kind <- entity_lookup(entities, record$kind)
    parent_entity <- if (!is.na(by_kind)) {
      by_kind
    } else {
      key <- if (grepl(".", record$path, fixed = TRUE)) {
        sub("^.*\\.", "", record$path)
      } else {
        record$path
      }
      mapped <- entity_lookup(entities, key)
      if (is.na(mapped)) key else mapped
    }
  }
  list(parent_entity = parent_entity, parent_id = parent_id,
       parent_rel = parent_rel, rel_type = record$kind,
       `_path` = usdm_pointer(record$path))
}

#' The value at a dotted path
#' @param doc The parsed document.
#' @param path A dotted path, with `[i]` for array positions.
#' @return The value, or `NULL` if the path does not resolve.
#' @noRd
usdm_at_path <- function(doc, path) {
  current <- doc
  for (part in strsplit(path, ".", fixed = TRUE)[[1]]) {
    index <- regmatches(part, regexpr("\\[[0-9]+\\]$", part))
    key <- sub("\\[[0-9]+\\]$", "", part)
    if (!is_json_object(current)) {
      return(NULL)
    }
    current <- current[[key]]
    if (length(index) == 1L) {
      position <- as.integer(gsub("[^0-9]", "", index)) + 1L
      if (!is.list(current) || position > length(current)) {
        return(NULL)
      }
      current <- current[[position]]
    }
  }
  current
}

#' Assemble records with differing keys into one dataset
#'
#' Columns are the union of every record's keys, in the order first seen, which
#' is what `from_records` gives the reference. A record missing a column gets a
#' blank rather than a dropped row.
#'
#' @param rows A list of named lists.
#' @return A `list(data, meta, label)` dataset entry.
#' @noRd
build_dataset_from_records <- function(rows) {
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  data <- data.table::as.data.table(stats::setNames(lapply(columns, function(column) {
    values <- lapply(rows, function(row) {
      if (is.null(row[[column]])) NA else row[[column]]
    })
    simplify_usdm_column(values)
  }), columns))
  list(data = data, meta = NULL, label = NA_character_)
}

#' Give a column the narrowest type its values allow
#'
#' Text stays text with `""` for blank, the convention every other reader here
#' follows. A column that is all logical or all numeric keeps that type, so a
#' rule comparing against a number is not comparing against its spelling.
#'
#' @param values A list of length-one values.
#' @return An atomic vector.
#' @noRd
simplify_usdm_column <- function(values) {
  present <- values[!vapply(values, function(v) length(v) == 0L || all(is.na(v)), logical(1))]
  if (length(present) == 0L) {
    return(rep("", length(values)))
  }
  if (all(vapply(present, is.logical, logical(1)))) {
    return(vapply(values, function(v) if (length(v) == 0L) NA else as.logical(v[[1]]), logical(1)))
  }
  if (all(vapply(present, function(v) is.numeric(v) && !is.logical(v), logical(1)))) {
    return(vapply(values, function(v) if (length(v) == 0L) NA_real_ else as.numeric(v[[1]]), numeric(1)))
  }
  vapply(values, function(v) {
    if (length(v) == 0L || all(is.na(v))) "" else as.character(v[[1]])
  }, character(1))
}

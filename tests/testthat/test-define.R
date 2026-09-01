# A minimal but structurally real Define-XML 2.1 document: the namespace
# declarations, ItemGroupDef/ItemRef/ItemDef nesting and Description/
# TranslatedText labelling all match a genuine define.xml. Written to a
# tempfile per the package's own "nothing outside tempdir()" rule.
define_xml_fixture <- function(def_ns = "http://www.cdisc.org/ns/def/v2.1") {
  path <- tempfile(fileext = ".xml")
  writeLines(sprintf('<?xml version="1.0" encoding="UTF-8"?>
<ODM xmlns="http://www.cdisc.org/ns/odm/v1.3" xmlns:def="%s" def:DefineVersion="2.1.0">
  <Study OID="ST.1">
    <MetaDataVersion OID="MDV.1">
      <ItemGroupDef OID="IG.VS" Name="VS" Domain="VS" SASDatasetName="VS"
                    def:Class="FINDINGS" def:Structure="One record per vital sign">
        <Description><TranslatedText xml:lang="en">Vital Signs</TranslatedText></Description>
        <ItemRef ItemOID="IT.VS.USUBJID" Mandatory="Yes" OrderNumber="1" Role="Identifier"/>
        <ItemRef ItemOID="IT.VS.VSTESTCD" Mandatory="Yes" OrderNumber="2" Role="Topic" def:HasNoData="Yes"/>
      </ItemGroupDef>
      <ItemGroupDef OID="IG.SE" Name="SE" Domain="SE" SASDatasetName="SE" def:HasNoData="Yes">
        <Description><TranslatedText xml:lang="en">Subject Elements</TranslatedText></Description>
        <ItemRef ItemOID="IT.SE.USUBJID" Mandatory="Yes" OrderNumber="1" Role="Identifier"/>
      </ItemGroupDef>
      <ItemDef OID="IT.VS.USUBJID" Name="USUBJID" DataType="text" Length="8">
        <Description><TranslatedText xml:lang="en">Unique Subject Identifier</TranslatedText></Description>
      </ItemDef>
      <ItemDef OID="IT.VS.VSTESTCD" Name="VSTESTCD" DataType="text" Length="8">
        <Description><TranslatedText xml:lang="en">Vital Signs Test Short Name</TranslatedText></Description>
      </ItemDef>
      <ItemDef OID="IT.SE.USUBJID" Name="USUBJID" DataType="text" Length="8">
        <Description><TranslatedText xml:lang="en">Unique Subject Identifier</TranslatedText></Description>
      </ItemDef>
    </MetaDataVersion>
  </Study>
</ODM>', def_ns), path)
  path
}

test_that("read_define_xml extracts dataset-level metadata including HasNoData", {
  skip_if_not(define_xml_available(), "xml2 not installed")
  path <- define_xml_fixture()
  on.exit(unlink(path))

  d <- read_define_xml(path)
  expect_equal(nrow(d$datasets), 2)
  expect_equal(d$datasets$define_dataset_name, c("VS", "SE"))
  expect_equal(d$datasets$define_dataset_label, c("Vital Signs", "Subject Elements"))
  expect_equal(d$datasets$define_dataset_class[1], "FINDINGS")
  # def:HasNoData is absent on VS (so FALSE - the dataset is expected to
  # carry data) and "Yes" on SE.
  expect_equal(d$datasets$define_dataset_has_no_data, c(FALSE, TRUE))
})

test_that("read_define_xml joins ItemRef to ItemDef, keeping per-dataset ordering", {
  skip_if_not(define_xml_available(), "xml2 not installed")
  path <- define_xml_fixture()
  on.exit(unlink(path))

  d <- read_define_xml(path)
  vs <- d$variables[d$variables$define_dataset_name == "VS", ]
  expect_equal(vs$define_variable_name, c("USUBJID", "VSTESTCD"))
  expect_equal(vs$define_variable_label, c("Unique Subject Identifier", "Vital Signs Test Short Name"))
  expect_equal(vs$define_variable_role, c("Identifier", "Topic"))
  # HasNoData lives on ItemRef (per-dataset), not on the shared ItemDef.
  expect_equal(vs$define_variable_has_no_data, c(FALSE, TRUE))

  # The same ItemDef name reused by another dataset stays scoped to its
  # own ItemGroupDef rather than leaking across datasets.
  se <- d$variables[d$variables$define_dataset_name == "SE", ]
  expect_equal(se$define_variable_name, "USUBJID")
})

test_that("read_define_xml handles Define-XML 2.0 as well as 2.1", {
  skip_if_not(define_xml_available(), "xml2 not installed")
  # Namespaces are stripped rather than matched by URI, so the 2.0 `def`
  # namespace parses through the identical code path - which is what lets
  # one reader cover both versions instead of the reference engine's
  # version-detecting factory.
  path <- define_xml_fixture(def_ns = "http://www.cdisc.org/ns/def/v2.0")
  on.exit(unlink(path))

  d <- read_define_xml(path)
  expect_equal(d$datasets$define_dataset_name, c("VS", "SE"))
  expect_equal(d$datasets$define_dataset_has_no_data, c(FALSE, TRUE))
})

test_that("read_define_xml returns NULL rather than erroring on a missing or unparseable file", {
  expect_null(read_define_xml(NULL))
  expect_null(read_define_xml(file.path(tempdir(), "does-not-exist.xml")))

  skip_if_not(define_xml_available(), "xml2 not installed")
  bad <- tempfile(fileext = ".xml")
  on.exit(unlink(bad))
  writeLines("this is not xml <<<", bad)
  expect_null(read_define_xml(bad))
})

test_that("find_define_xml prefers a define*.xml over other XML in the directory", {
  dir <- tempfile("coreval_define_")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE))

  expect_null(find_define_xml(dir))

  file.create(file.path(dir, "annotated-crf.xml"))
  # A lone .xml is used as a fallback...
  expect_equal(basename(find_define_xml(dir)), "annotated-crf.xml")
  # ...but a conventionally-named define file wins once present.
  file.create(file.path(dir, "define_2_1.xml"))
  expect_equal(basename(find_define_xml(dir)), "define_2_1.xml")
})

test_that("build_variable_metadata_dataset joins define labels, preserving variable order", {
  skip_if_not(define_xml_available(), "xml2 not installed")
  path <- define_xml_fixture()
  on.exit(unlink(path))
  define <- read_define_xml(path)

  real <- list(
    data = data.table::data.table(USUBJID = "S1", VSTESTCD = "SYSBP", EXTRA = "x"),
    meta = data.table::data.table(
      variable = c("USUBJID", "VSTESTCD", "EXTRA"),
      label = c("Unique Subject Identifier", "WRONG LABEL", "Not in define"),
      type = c("Char", "Char", "Char")
    )
  )
  built <- build_variable_metadata_dataset(real, define, "VS")

  # Row order is the dataset's own variable order - that IS the Record
  # number a Variable Metadata Check reports against.
  expect_equal(built$data$variable_name, c("USUBJID", "VSTESTCD", "EXTRA"))
  expect_equal(
    built$data$define_variable_label,
    c("Unique Subject Identifier", "Vital Signs Test Short Name", NA_character_)
  )
  # A label disagreeing with define.xml is exactly what CORE-000507 flags.
  mismatch <- built$data$variable_label != built$data$define_variable_label
  expect_equal(mismatch, c(FALSE, TRUE, NA))
})

test_that("evaluate_rule refuses a define.xml rule when the study has no define.xml", {
  # Not a blanket refusal by rule type any more: with a define.xml present
  # the rule runs. Without one, refusing beats evaluating against absent
  # columns, which the "not a real column -> literal text" fallback would
  # turn into a fabricated finding for every variable.
  rule <- list(
    rule_type = "Variable Metadata Check against Define XML",
    check = list(all = list(list(
      name = "variable_label", operator = "not_equal_to", value = "define_variable_label"
    )))
  )
  study <- list(
    datasets = list(VS = list(
      data = data.table::data.table(USUBJID = "S1"),
      meta = data.table::data.table(variable = "USUBJID", label = "Unique Subject Identifier", type = "Char")
    )),
    define = NULL
  )
  expect_error(evaluate_rule(rule, study, "VS"), "define.xml", fixed = TRUE)
})

test_that("a rule referencing CDISC Library pseudo-columns is refused, not fabricated", {
  # `library_variable_role` and friends have no bundled data, so the
  # "not a real column -> literal text" fallback would make
  # `define_variable_role != "library_variable_role"` true for EVERY
  # variable, in the compliant and non-compliant case alike. Exactly 5
  # bundled rules reference a library_* pseudo-column (CORE-000398, 494,
  # 903, 1081, 1082); all must report as unevaluable rather than flagging
  # everything. The guard tests the BUILT dataset, so adding real Library
  # metadata as columns later disables it automatically.
  rule <- list(
    rule_type = "Variable Metadata Check",
    check = list(all = list(list(
      name = "variable_label", operator = "not_equal_to", value = "library_variable_label"
    )))
  )
  dataset <- list(data = data.table::data.table(variable_label = "Study Identifier"), meta = NULL)
  expect_error(
    assert_referenced_metadata_available(rule, dataset),
    "CDISC Library"
  )

  # Once the column is genuinely present, the guard stands aside.
  dataset$data$library_variable_label <- "Study Identifier"
  expect_silent(assert_referenced_metadata_available(rule, dataset))
})

test_that("library_* columns are omitted for a CUSTOM domain, but present for a known one", {
  # A custom domain (one no standard defines) has nothing to be judged
  # against: comparing its variables to the generic Model would flag every
  # sponsor-specific variable as the wrong type. The reference draws the
  # same distinction explicitly. Confirmed against CORE-001082, whose XY
  # fixture expects no findings at all.
  meta <- data.table::data.table(
    variable = c("STUDYID", "XYFOO"),
    label = c("Study Identifier", "Sponsor Thing"),
    type = c("Char", "Char")
  )
  real <- list(data = data.table::data.table(STUDYID = "S", XYFOO = "x"), meta = meta)
  study <- list(standard = list(product = "SDTMIG", version = "3-4"))

  custom <- build_variable_metadata_dataset(real, NULL, "XY", study)
  expect_false("library_variable_data_type" %in% names(custom$data))

  # A known domain gets the columns, and a variable the IG doesn't
  # enumerate still resolves through the SDTM Model.
  lb_meta <- data.table::data.table(
    variable = c("LBSEQ", "LBCHENDY"),
    label = c("Sequence Number", "Change End Study Day"),
    type = c("Num", "Num")
  )
  lb <- list(data = data.table::data.table(LBSEQ = 1, LBCHENDY = 2), meta = lb_meta)
  known <- build_variable_metadata_dataset(lb, NULL, "LB", study)
  expect_true("library_variable_data_type" %in% names(known$data))
  # LBSEQ from the IG, LBCHENDY from the Model's --CHENDY template.
  expect_equal(known$data$library_variable_data_type, c("Num", "Num"))
})

test_that("def:Origin is read, and is_collected follows the Define-XML version's spelling", {
  # Two bugs at once. (1) def:Origin keeps its namespace for XPath purposes
  # even after xml_ns_strip(), so a plain "./Origin" found nothing and every
  # variable's origin came back NA. (2) "collected on the CRF" is spelled
  # "Collected" in Define-XML 2.1 and "CRF" in 2.0; both are accepted, since
  # no version uses both and the other Origin types are shared.
  skip_if_not_installed("xml2")
  path <- tempfile(fileext = ".xml")
  on.exit(unlink(path), add = TRUE)
  writeLines(c(
    '<ODM xmlns="http://www.cdisc.org/ns/odm/v1.3" xmlns:def="http://www.cdisc.org/ns/def/v2.1">',
    '<Study><MetaDataVersion>',
    '<ItemGroupDef OID="IG.CM" Name="CM" Domain="CM" Repeating="Yes">',
    '<Description><TranslatedText>Con Meds</TranslatedText></Description>',
    '<ItemRef ItemOID="IT.CM.CMTRT" OrderNumber="1" Mandatory="Yes"/>',
    '<ItemRef ItemOID="IT.CM.CMSEQ" OrderNumber="2" Mandatory="Yes"/>',
    '<ItemRef ItemOID="IT.CM.CMDOSE" OrderNumber="3" Mandatory="No"/>',
    '</ItemGroupDef>',
    '<ItemDef OID="IT.CM.CMTRT" Name="CMTRT" DataType="text">',
    '<def:Origin Source="Investigator" Type="Protocol"/></ItemDef>',
    '<ItemDef OID="IT.CM.CMSEQ" Name="CMSEQ" DataType="integer">',
    '<def:Origin Type="Collected" Source="Investigator"/></ItemDef>',
    '<ItemDef OID="IT.CM.CMDOSE" Name="CMDOSE" DataType="float"/>',
    '</MetaDataVersion></Study></ODM>'
  ), path)

  define <- read_define_xml(path)
  v <- as.data.frame(define$variables)
  got <- function(name, col) v[[col]][v$define_variable_name == name]

  expect_equal(got("CMTRT", "define_variable_origin_type"), "Protocol")
  expect_false(got("CMTRT", "define_variable_is_collected"))
  expect_true(got("CMSEQ", "define_variable_is_collected"))
  # No def:Origin at all is not the same as declaring a non-collected one.
  expect_true(is.na(got("CMDOSE", "define_variable_is_collected")))
})

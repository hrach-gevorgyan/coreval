# Regenerates inst/extdata/sdtm_model_variables.rds: for each SDTM
# observation class, the full set of variable names the abstract SDTM Model
# allows for that class (including inherited base-class variables), used by
# the `get_model_column_order` Operations type ("is a variable name allowed
# for this domain's class at all") - contrast with sdtm_domain_classes.rds,
# which maps a DOMAIN to its class name, not a class to its variables.
#
# Like domain_classes.R, this is NOT extracted from cdisc-org/cdisc-open-rules
# (that repo has no model data, only the CORE rules themselves). It's
# machine-extracted from cdisc-org/cdisc-rules-engine's own bundled cache
# (resources/cache/standards_models.pkl, key "models/sdtm/2-1" - the newest
# available Model version, used as a superset per the same simplification
# domain_classes.R already documents), which that MIT-licensed,
# CDISC-published repository commits directly to git. It ultimately
# originates from the CDISC Library API's SDTM Model metadata. Rows below
# are in the pickle's own per-class `classVariables` order (each class's own
# variables listed together, in the Model's own ordinal order) - regenerate
# from a fresh clone of cdisc-rules-engine if ever needed, never at package
# build or install time (this script's OUTPUT, the .rds, is what ships).
#
# Variable names here can be "--"-prefixed templates (e.g. "--SEQ") exactly
# like a rule's own `check.name` - resolve_var_name() already handles this,
# so no extra normalization is needed downstream.

class_own <- data.frame(
  class = c(
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "General Observations", "General Observations",
    "General Observations", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Interventions",
    "Interventions", "Interventions", "Interventions", "Interventions", "Events", "Events",
    "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events",
    "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events",
    "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events",
    "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events",
    "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events",
    "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events", "Events",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings", "Findings", "Findings", "Findings",
    "Findings", "Findings", "Findings", "Findings About", "Associated Persons",
    "Associated Persons", "Associated Persons", "Associated Persons"
  ),
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "POOLID", "SPDEVID", "SPTOBID", "IGDCMPID", "STOCONID",
    "NHOID", "FETUSID", "FOCID", "--SEQ", "--GRPID", "--REFID", "--RECID", "--SPID", "--LNKID",
    "--LNKGRP", "--BEATNO", "VISITNUM", "VISIT", "VISITDY", "TAETORD", "EPOCH", "RPHASE",
    "RPPLDY", "RPPLSTDY", "RPPLENDY", "--DTC", "--STDTC", "--ENDTC", "--DY", "--STDY",
    "--ENDY", "--NOMDY", "--NOMLBL", "--RPDY", "--RPSTDY", "--RPENDY", "--XDY", "--XSTDY",
    "--XENDY", "--CHDY", "--CHSTDY", "--CHENDY", "--DUR", "--TPT", "--TPTNUM", "--ELTM",
    "--TPTREF", "--RFTDTC", "--STRF", "--ENRF", "--EVLINT", "--EVINTX", "--STRTPT", "--STTPT",
    "--ENRTPT", "--ENTPT", "MIDS", "RELMIDS", "MIDSDTC", "--STINT", "--ENINT", "--DETECT",
    "--PTFL", "--PDUR", "--TRT", "--MODIFY", "--DECOD", "--MOOD", "--CAT", "--SCAT", "--PRESP",
    "--OCCUR", "--REASOC", "--STAT", "--REASND", "--CNTMOD", "--EPCHGI", "--INDC", "--CLAS",
    "--CLASCD", "--DOSE", "--DOSTXT", "--DOSU", "--TDOSD", "--FTDOSD", "--DOSFRM", "--DOSFRQ",
    "--DOSTOT", "--DOSRGM", "--ROUTE", "--LOT", "--LOC", "--METHOD", "--LAT", "--DIR",
    "--PORTOT", "--FAST", "--PSTRG", "--PSTRGU", "--TRTV", "--VAMT", "--VAMTU", "--ADJ",
    "--RSDISC", "--USCHFL", "--RSTIND", "--RSTMOD", "--TERM", "--MODIFY", "--LLT", "--LLTCD",
    "--DECOD", "--EVDTYP", "--PTCD", "--HLT", "--HLTCD", "--HLGT", "--HLGTCD", "--CAT",
    "--SCAT", "--PRESP", "--OCCUR", "--REASOC", "--STAT", "--REASND", "--BODSYS", "--BDSYCD",
    "--SOC", "--SOCCD", "--CNTMOD", "--EPCHGI", "--LOC", "--LAT", "--DIR", "--PORTOT",
    "--PARTY", "--PRTYID", "--SEV", "--SER", "--ACN", "--ACNOTH", "--ACNDEV", "--REL",
    "--RLDEV", "--RELNST", "--PATT", "--OUT", "--SCAN", "--SCONG", "--SDISAB", "--SDTH",
    "--SHOSP", "--SLIFE", "--SOD", "--SMIE", "--SINTV", "--UNANT", "--RLPRT", "--RLPRC",
    "--CONTRT", "--TOX", "--TOXGR", "--USCHFL", "--TESTCD", "--TEST", "--SBMRKS", "--CELSTA",
    "--CSMRKS", "--CNTMOD", "--EPCHGI", "--TSTCND", "--CNDAGT", "--BDAGNT", "--ABCLID",
    "--MRKSTR", "--GATE", "--GATDEF", "--TSTOPO", "--MSCBCE", "--AGENT", "--CONC", "--CONCU",
    "--MODIFY", "--TSTDTL", "--SPTSTD", "--CAT", "--SCAT", "--TSTPNL", "--POS", "--BODSYS",
    "--ORRES", "--ORRESU", "--CELLEV", "--RESSCL", "--RESTYP", "--COLSRT", "--ORNRLO",
    "--ORNRHI", "--ORREF", "--LLOD", "--STRESC", "--IMPLBL", "--STRESN", "--STRESU",
    "--STNRLO", "--STNRHI", "--STNRC", "--STREFC", "--STREFN", "--NRIND", "--RESCAT",
    "--INHERT", "--GENREF", "--CHROM", "--SYM", "--SYMTYP", "--GENLOC", "--GENSR", "--SEQID",
    "--PVRID", "--COPYID", "--CHRON", "--DISTR", "--RESLOC", "--STAT", "--REASND", "--XFN",
    "--NAM", "--LOINC", "--SPEC", "--ANTREG", "--SPCCND", "--SPCUFL", "--LOC", "--LAT",
    "--DIR", "--PORTOT", "--METHOD", "--RUNID", "--ANMETH", "--TMTHSN", "--LEAD", "--CSTATE",
    "--LOBXFL", "--BLFL", "--FAST", "--DRVFL", "--EVAL", "--EVALID", "--ACPTFL", "--TOX",
    "--TOXGR", "--SEV", "--CLSIG", "--DTHREL", "--LLOQ", "--ULOQ", "--REASPF", "--EXCLFL",
    "--REASEX", "--USCHFL", "--REPNUM", "--RSTIND", "--RSTMOD", "--OBJ", "APID", "RSUBJID",
    "RDEVID", "SREL"
  ),
  stringsAsFactors = FALSE
)

stopifnot(nrow(class_own) == 272)

# Class inheritance (confirmed from the same pickle's `_links.parentClass`):
# Interventions/Events/Findings inherit General Observations; Findings About
# inherits Findings (which inherits General Observations). A domain's full
# allowed-variable set is its own class's variables UNION every ancestor
# class's variables - resolved once here so the shipped .rds needs no
# parent-walk at runtime.
class_parent <- c(
  "Interventions" = "General Observations",
  "Events" = "General Observations",
  "Findings" = "General Observations",
  "Findings About" = "Findings"
)

resolve_class_variables <- function(class_name) {
  vars <- class_own$variable[class_own$class == class_name]
  parent <- unname(class_parent[class_name])
  if (!is.na(parent)) {
    vars <- c(vars, resolve_class_variables(parent))
  }
  unique(vars)
}

classes <- unique(class_own$class)
resolved <- lapply(classes, resolve_class_variables)
model_class_variables <- data.frame(
  class = rep(classes, lengths(resolved)),
  variable = unlist(resolved),
  stringsAsFactors = FALSE
)

stopifnot(!anyNA(model_class_variables), nrow(model_class_variables) > 0)

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(model_class_variables, file.path("inst", "extdata", "sdtm_model_variables.rds"))

cat(sprintf("Wrote %d (class, variable) rows across %d classes\n", nrow(model_class_variables), length(classes)))

# Regenerates inst/extdata/sdtm_domain_classes.rds: a static SDTMIG 3.4
# domain -> observation-class table, needed to resolve a rule's `Scope >
# Classes` (e.g. "FINDINGS") against an actual domain code (e.g. "LB").
#
# This is NOT extracted from cdisc-org/cdisc-open-rules - that repo has no
# domain/class model, only the CORE rules themselves. It's transcribed from
# cdisc-org/cdisc-rules-engine's own bundled cache
# (resources/cache/standards_details.pkl, key "standards/sdtmig/3-4"),
# which that MIT-licensed, CDISC-published repository commits directly to
# git (not downloaded on demand) - i.e. CDISC's own official rules engine
# ships this exact table as redistributable, offline reference data. It
# ultimately originates from the CDISC Library API's SDTM-IG 3.4 model
# metadata.
#
# Newer SDTMIG versions only add domains (plus one removal: MO, present in
# 3.2/3.3, dropped in 3.4) relative to older ones - see the version comment
# below. Using the 3.4 (superset) table for all Classes matching, regardless
# of which SDTMIG version a specific rule targets, is a known simplification
# for now: it can only under-match (an old-version-only rule scoped to a
# domain not yet in the model) or over-match a handful of newly-introduced
# domains, never misclassify a domain into the wrong class.

domain_classes <- data.frame(
  domain = c(
    "AE", "AG", "BE", "BS", "CE", "CM", "CO", "CP", "CV", "DA", "DD", "DM",
    "DS", "DV", "EC", "EG", "EX", "FA", "FT", "GF", "HO", "IE", "IS", "LB",
    "MB", "MH", "MI", "MK", "ML", "MS", "NV", "OE", "OI", "PC", "PE", "PP",
    "PR", "QS", "RE", "RELREC", "RELSPEC", "RELSUB", "RP", "RS", "SC", "SE",
    "SM", "SR", "SS", "SU", "SUPPQUAL", "SV", "TA", "TD", "TE", "TI", "TM",
    "TR", "TS", "TU", "TV", "UR", "VS"
  ),
  class = c(
    "EVENTS", "INTERVENTIONS", "EVENTS", "FINDINGS", "EVENTS", "INTERVENTIONS",
    "SPECIAL PURPOSE", "FINDINGS", "FINDINGS", "FINDINGS", "FINDINGS",
    "SPECIAL PURPOSE", "EVENTS", "EVENTS", "INTERVENTIONS", "FINDINGS",
    "INTERVENTIONS", "FINDINGS ABOUT", "FINDINGS", "FINDINGS", "EVENTS",
    "FINDINGS", "FINDINGS", "FINDINGS", "FINDINGS", "EVENTS", "FINDINGS",
    "FINDINGS", "INTERVENTIONS", "FINDINGS", "FINDINGS", "FINDINGS",
    "STUDY REFERENCE", "FINDINGS", "FINDINGS", "FINDINGS", "INTERVENTIONS",
    "FINDINGS", "FINDINGS", "RELATIONSHIP", "RELATIONSHIP", "RELATIONSHIP",
    "FINDINGS", "FINDINGS", "FINDINGS", "SPECIAL PURPOSE", "SPECIAL PURPOSE",
    "FINDINGS ABOUT", "FINDINGS", "INTERVENTIONS", "RELATIONSHIP",
    "SPECIAL PURPOSE", "TRIAL DESIGN", "TRIAL DESIGN", "TRIAL DESIGN",
    "TRIAL DESIGN", "TRIAL DESIGN", "FINDINGS", "TRIAL DESIGN", "FINDINGS",
    "TRIAL DESIGN", "FINDINGS", "FINDINGS"
  ),
  stringsAsFactors = FALSE
)

stopifnot(length(domain_classes$domain) == 63, !anyDuplicated(domain_classes$domain))

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(domain_classes, file.path("inst", "extdata", "sdtm_domain_classes.rds"))

cat(sprintf("Wrote %d domain-class rows\n", nrow(domain_classes)))

# Regenerates inst/extdata/sdtm_domain_classes.rds: a static domain ->
# observation-class table (SDTMIG 3.4 plus SENDIG 3.1's SEND-specific
# domains), needed to resolve a rule's `Scope > Classes` (e.g. "FINDINGS")
# against an actual domain code (e.g. "LB").
#
# This is NOT extracted from cdisc-org/cdisc-open-rules - that repo has no
# domain/class model, only the CORE rules themselves. It's transcribed from
# cdisc-org/cdisc-rules-engine's own bundled cache
# (resources/cache/standards_details.pkl, keys "standards/sdtmig/3-4" and
# "standards/sendig/3-1"), which that MIT-licensed, CDISC-published
# repository commits directly to git (not downloaded on demand) - i.e.
# CDISC's own official rules engine ships this exact table as
# redistributable, offline reference data. It ultimately originates from
# the CDISC Library API's model metadata.
#
# Newer SDTMIG versions only add domains (plus one removal: MO, present in
# 3.2/3.3, dropped in 3.4) relative to older ones - see the version comment
# below. Using the 3.4 (superset) table for all Classes matching, regardless
# of which SDTMIG version a specific rule targets, is a known simplification
# for now: it can only under-match (an old-version-only rule scoped to a
# domain not yet in the model) or over-match a handful of newly-introduced
# domains, never misclassify a domain into the wrong class.
#
# SEND (SENDIG 3.1) domains: confirmed zero class conflicts against every
# domain code SDTM and SEND share (DM, CO, SE, EX, DS, LB, VS, EG, CV, DD,
# MI, PC, PP, RE, SC, RELREC, SUPPQUAL, TA, TE, TS all resolve to the SAME
# class in both standards) - so these are merged into one shared table
# rather than keeping a second, standard-specific one. Ten domains below
# (BW, BG, CL, FW, MA, OM, PM, TF, TX, POOLDEF) are SEND-only additions with
# no SDTM equivalent at all (TX - "Trial Sets" - included).

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

send_only_domains <- data.frame(
  domain = c("BW", "BG", "CL", "FW", "MA", "OM", "PM", "TF", "TX", "POOLDEF"),
  class = c(
    "FINDINGS", "FINDINGS", "FINDINGS", "FINDINGS", "FINDINGS", "FINDINGS",
    "FINDINGS", "FINDINGS", "TRIAL DESIGN", "RELATIONSHIP"
  ),
  stringsAsFactors = FALSE
)
domain_classes <- rbind(domain_classes, send_only_domains)

# SEND's extension standards (SENDIG-DART for developmental/reproductive
# toxicology, SENDIG-AR for animal rule/medical countermeasures, SENDIG-
# GENETOX for genetic toxicology - same source pickle, keys
# "standards/sendig/dart-1-1", "standards/sendig/ar-1-0",
# "standards/sendig/genetox-1-0") add a further 8 domains with no SDTM or
# base-SENDIG equivalent at all. Confirmed zero class conflicts, both
# against the existing table and across the three extension standards
# themselves, before merging.
send_extension_domains <- data.frame(
  domain = c("SJ", "IC", "PY", "FM", "FX", "TT", "TP", "AC", "GV"),
  class = c(
    "SPECIAL PURPOSE", "FINDINGS", "FINDINGS", "FINDINGS", "FINDINGS",
    "TRIAL DESIGN", "TRIAL DESIGN", "TRIAL DESIGN", "FINDINGS"
  ),
  stringsAsFactors = FALSE
)
domain_classes <- rbind(domain_classes, send_extension_domains)

stopifnot(length(domain_classes$domain) == 82, !anyDuplicated(domain_classes$domain))

dir.create(file.path("inst", "extdata"), recursive = TRUE, showWarnings = FALSE)
saveRDS(domain_classes, file.path("inst", "extdata", "sdtm_domain_classes.rds"))

cat(sprintf("Wrote %d domain-class rows\n", nrow(domain_classes)))

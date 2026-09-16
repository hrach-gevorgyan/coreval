# Controlled Terminology packages coreval bundles

Which version of CDISC's Controlled Terminology a study follows decides
whether a value is a legal term, and the answer changes between
releases - `SEX` gained `INTERSEX` and lost `UNDIFFERENTIATED`. So
coreval never picks one for you: pass the one your study declares as
`check_study(ct_package =)` and this is the list to pick from.

## Usage

``` r
list_ct_packages(family = NULL)
```

## Arguments

- family:

  Optional prefix to narrow to one terminology family, e.g. `"sdtm"` or
  `"send"`.

## Value

A character vector of package names, oldest first.

## Details

Only what a conformance rule can ask about is bundled - each codelist's
submission value and C-code, its terms' submission values and C-codes,
and whether it is extensible. Definitions and synonyms are not, which is
how 438 MB of CDISC's own caches becomes half a megabyte here.

## Examples

``` r
head(list_ct_packages("sdtm"))
#> [1] "sdtmct-2014-09-26" "sdtmct-2014-12-19" "sdtmct-2015-03-27"
#> [4] "sdtmct-2015-06-26" "sdtmct-2015-09-25" "sdtmct-2015-12-18"
```

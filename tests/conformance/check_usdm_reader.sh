#!/usr/bin/env bash
# Dump the reference's tables for a spread of USDM documents and diff coreval's
# reader against every one of them.
#
#   bash tests/conformance/check_usdm_reader.sh [n]
#
# `n` is how many documents to sample (default 20), taken evenly across the
# JSONata fixtures, which are the only ones that ship a USDM document at all.
# Each document costs a run of CDISC's engine, so a full sweep of all 258 is
# hours; a spread is the usual check and the full set is worth running before a
# release that touches read_usdm.R.
#
# Prints one line per document and a final count. Dev tooling only.
set -u

n="${1:-20}"
root="data-raw/upstream/cdisc-open-rules/Published"
out="${TMPDIR:-/tmp}/coreval-usdm-ref"
mkdir -p "$out"

mapfile -t docs < <(find "$root" -name "*.json" -path "*/data/*" | sort)
total="${#docs[@]}"
if [ "$total" -eq 0 ]; then
  echo "no USDM documents under $root" >&2
  exit 1
fi
step=$(( total / n ))
[ "$step" -lt 1 ] && step=1

ok=0
bad=0
for (( i = 0; i < total; i += step )); do
  doc="${docs[$i]}"
  # Rule id, polarity and case number all three: without the rule id every
  # rule's negative/01 lands in one directory and each document is compared
  # against another rule's tables.
  case_dir="$(dirname "$(dirname "$doc")")"
  label="$(basename "$(dirname "$(dirname "$case_dir")")")/$(basename "$(dirname "$case_dir")")/$(basename "$case_dir")"
  ref="$out/$(echo "$label" | tr '/' '_')"
  if ! python tests/conformance/dump_usdm_tables.py "$doc" "$ref" >/dev/null 2>&1; then
    echo "SKIP  $label  (the reference could not read it)"
    continue
  fi
  result="$(Rscript tests/conformance/compare_usdm_reader.R "$doc" "$ref" 2>&1 | tail -2 | tr -d '\r')"
  if echo "$result" | grep -q "0 with differences, 0 only on one side"; then
    ok=$(( ok + 1 ))
    echo "ok    $label  $(echo "$result" | grep -o '[0-9]* entities compared')"
  else
    bad=$(( bad + 1 ))
    echo "DIFF  $label"
    Rscript tests/conformance/compare_usdm_reader.R "$doc" "$ref" 2>&1 | grep -vE "^$" | tail -8
  fi
done

echo
echo "$ok document(s) identical, $bad with differences"

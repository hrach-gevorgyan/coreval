"""Dump CDISC's USDM key-to-entity map for data-raw/usdm_entities.R.

    python data-raw/dump_usdm_entities.py

Reads resources/schema/USDM.yaml from the pinned engine clone and writes
data-raw/usdm_entities.csv, one row per mapping.

The file answers "which entity does this key hold": `epochId` holds a
StudyEpoch, `activities` holds Activities, and the pseudo-key `this` holds the
document wrapper. Reading a USDM document into tables needs it, because an
object that does not declare its own instanceType is named after the key that
held it.

Five of the 115 entries map to a nested table keyed by the parent's class
rather than to a single name. The reference cannot use those as an entity name
either: it checks that the mapping is a string and falls back to the key
itself. They are dropped here, which makes a lookup miss and a nested entry
behave the same way, as they already do there.
"""

import csv
import io
import os
import sys

import yaml

SRC = os.path.join("data-raw", "upstream", "cdisc-rules-engine",
                   "resources", "schema", "USDM.yaml")
OUT = os.path.join("data-raw", "usdm_entities.csv")


def main():
    if not os.path.isfile(SRC):
        sys.exit("No USDM.yaml at %s; clone the engine into data-raw/upstream first." % SRC)
    with io.open(SRC, encoding="utf-8") as fh:
        mapping = yaml.safe_load(fh)
    plain = {k: v for k, v in mapping.items() if isinstance(v, str)}
    nested = sorted(k for k, v in mapping.items() if not isinstance(v, str))
    with io.open(OUT, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=["key", "entity"])
        writer.writeheader()
        for key in sorted(plain):
            writer.writerow({"key": key, "entity": plain[key]})
    print("wrote %s: %d mappings (%d nested entries dropped: %s)"
          % (OUT, len(plain), len(nested), ", ".join(nested)))


if __name__ == "__main__":
    main()

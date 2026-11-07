"""Dump the SDTM Model of each SDTMIG version to CSV for data-raw/model_versions.R.

CORE 1.0 reads the SDTM Model that an Implementation Guide links to (its
`_links.model`): SDTMIG 3.2 uses Model 1.4, 3.3 uses 1.7 and 3.4 uses 2.0.
sdtm_model_variables.rds holds Model 2.1 alone, which let a 3.2 study use a
variable the Model added later (AERLPRC, CORE-000550).

Reads the offline, MIT-licensed cache Verisian's engine commits to git
(resources/cache/standards_models.pkl and standards_details.pkl), the engine
the CORE 1.0 rules run under. No CDISC API is contacted.

    python data-raw/dump_model_versions.py

Writes data-raw/model_versions_classes.csv, model_versions_datasets.csv and
model_versions_map.csv. Build time only.
"""

import csv
import os
import pickle
import sys

CACHE_DIR = os.path.join("data-raw", "upstream", "verisian-engine", "resources", "cache")
GUIDES = ["standards/sdtmig/3-2", "standards/sdtmig/3-3", "standards/sdtmig/3-4"]


def load(name):
    path = os.path.join(CACHE_DIR, name)
    if not os.path.exists(path):
        sys.exit("Cache not found: %s\nClone verisianHQ/cdisc-rules-engine into "
                 "data-raw/upstream/verisian-engine first." % path)
    with open(path, "rb") as fh:
        return pickle.load(fh)


def write(path, fields, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def variable_row(var):
    return {
        "variable": var.get("name", ""),
        "label": var.get("label", "") or "",
        "role": var.get("role", "") or "",
        "type": var.get("simpleDatatype", "") or "",
        "ordinal": var.get("ordinal", "") or "",
    }


def main():
    models = load("standards_models.pkl")
    details = load("standards_details.pkl")

    mapping = []
    for guide in GUIDES:
        href = ((details[guide].get("_links") or {}).get("model") or {}).get("href", "")
        version = href.rstrip("/").split("/")[-1]
        if not version:
            sys.exit("No Model link for %s" % guide)
        mapping.append({"ig_version": guide.split("/")[-1].replace("-", "."), "model_version": version})

    classes, datasets = [], []
    for version in sorted({m["model_version"] for m in mapping}):
        model = models.get("models/sdtm/%s" % version)
        if model is None:
            sys.exit("Model %s not in the cache" % version)
        for cls in model.get("classes") or []:
            for var in cls.get("classVariables") or []:
                row = variable_row(var)
                if row["variable"]:
                    classes.append(dict(model_version=version, **{"class": cls.get("name", "")}, **row))
        for ds in model.get("datasets") or []:
            for var in ds.get("datasetVariables") or []:
                row = variable_row(var)
                if row["variable"] and ds.get("name"):
                    datasets.append(dict(model_version=version, domain=ds["name"], **row))

    base = ["variable", "label", "role", "type", "ordinal"]
    write(os.path.join("data-raw", "model_versions_map.csv"), ["ig_version", "model_version"], mapping)
    write(os.path.join("data-raw", "model_versions_classes.csv"), ["model_version", "class"] + base, classes)
    write(os.path.join("data-raw", "model_versions_datasets.csv"), ["model_version", "domain"] + base, datasets)
    print("map:", mapping)
    print("classes: %d rows, datasets: %d rows" % (len(classes), len(datasets)))


if __name__ == "__main__":
    main()

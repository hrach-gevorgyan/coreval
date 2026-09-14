"""Flatten a USDM JSON document with CDISC's own service and write the tables.

    python tests/conformance/dump_usdm_tables.py <study.json> <out-dir>

Writes one CSV per entity, plus `_datasets.csv`, in the same layout a CORE test
case uses. That makes the reference's answer available as files, so coreval's
own USDM reader can be compared against it rather than against a reading of the
source.

Why this exists: CDISC publishes the USDM Record Data fixtures only as
flattened per-entity CSVs and the JSONata fixtures only as JSON documents, so
not one fixture pairs a document with the tables it should produce. Without
that pairing a reader could be written, could look right, and could be wrong in
a way nothing would catch. This produces the pairing.

Dev tooling only. Not part of the package, not run by R CMD check, and
Rbuildignored with the rest of tests/conformance. Needs the engine venv; see
tests/conformance/compare_engine.py for the setup.
"""

import csv
import io
import os
import subprocess
import sys
import textwrap

ENGINE = os.path.join("data-raw", "upstream", "cdisc-rules-engine")

# Runs inside the engine's own interpreter and working directory, because
# USDMDataService reads resources/schema/USDM.yaml by a relative path.
DRIVER = textwrap.dedent(
    """
    import csv, io, json, os, sys
    from cdisc_rules_engine.services.data_services.usdm_data_service import USDMDataService
    from cdisc_rules_engine.services.cache.in_memory_cache_service import InMemoryCacheService
    from cdisc_rules_engine.config import config

    document, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    USDMDataService._instance = None
    service = USDMDataService.get_instance(
        cache_service=InMemoryCacheService(), config=config, dataset_path=document
    )

    # The content index too: which paths each entity is built from, and whether
    # each is a definition or a reference. That is the traversal's own answer,
    # ahead of any flattening, so a port can be compared one stage at a time.
    with io.open(os.path.join(out_dir, "_content_index.json"), "w", encoding="utf-8") as fh:
        json.dump(service.dataset_content_index, fh, indent=1, sort_keys=True)

    def blank_if_missing(v):
        if v is None:
            return ""
        if isinstance(v, float) and v != v:
            return ""
        return v

    manifest = []
    for entry in service.dataset_content_index:
        name = entry["dataset_name"]
        frame = service.get_dataset(dataset_name=name)
        records = frame.data.to_dict("records")
        columns = list(frame.data.columns)
        path = os.path.join(out_dir, name + ".csv")
        with io.open(path, "w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=columns)
            writer.writeheader()
            for row in records:
                # A pandas NaN is not None and str()s to "nan", which on the
                # far side reads as the literal text. Both mean "this record
                # has no value here", so both are written blank.
                writer.writerow({k: blank_if_missing(v) for k, v in row.items()})
        manifest.append({"Filename": name, "Dataset Name": name, "Label": name,
                         "Rows": len(records), "Columns": len(columns)})

    with io.open(os.path.join(out_dir, "_datasets.csv"), "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=["Filename", "Dataset Name", "Label", "Rows", "Columns"])
        writer.writeheader()
        for row in sorted(manifest, key=lambda r: r["Filename"]):
            writer.writerow(row)

    print("%d entities, %d records" % (len(manifest), sum(r["Rows"] for r in manifest)))
    """
)


def engine_python():
    for rel in (("Scripts", "python.exe"), ("bin", "python")):
        path = os.path.join(ENGINE, ".venv", *rel)
        if os.path.isfile(path):
            return path
    sys.exit("No engine venv. See the setup block in compare_engine.py.")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    document, out_dir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    run = subprocess.run(
        [engine_python(), "-c", DRIVER, document, out_dir],
        cwd=ENGINE, capture_output=True, text=True, timeout=1800,
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    sys.stdout.write(run.stdout)
    if run.returncode != 0:
        sys.stderr.write(run.stderr)
        sys.exit(run.returncode)


if __name__ == "__main__":
    main()

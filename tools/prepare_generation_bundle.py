"""Package verified archived generations for local preservation or authorized sharing.

Keeps id, label and predict exactly as decoded from the original JSONL. Prompt
text is omitted. This operation does not anonymize records or authorize release.
No network operation is performed.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import zipfile


def pack(code, manifest_path, destination):
    rows = list(csv.DictReader(manifest_path.open(encoding="utf-8")))
    if len(rows) != 580 or len({(r["variant"], r["file"]) for r in rows}) != 580:
        raise ValueError("Use the complete verified 580-file generation manifest")
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("Choose an empty destination to preserve existing archives")
    destination.mkdir(parents=True, exist_ok=True)
    groups = {}
    for row in rows:
        variant, name = row["variant"], row["file"]
        model = name.removeprefix("nosft_").split("__prompt_", 1)[0]
        matches = list((code / "data/llm_outputs/outcome" / variant).rglob(name))
        if len(matches) != 1:
            raise ValueError(f"Expected one original file: {variant}/{name}")
        groups.setdefault((variant, model), []).append((row, matches[0]))
    result = dict(schema_version=1, fields=["id", "label", "predict"],
                  original_prompt_included=False, records_anonymized=False,
                  redistribution_permission="Not determined by this packaging tool",
                  archives=[], files=[])
    for (variant, model), members in sorted(groups.items()):
        name = f"{variant}__{model}.zip"
        temporary = destination / (name + ".partial")
        archive_records = 0
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for row, source in sorted(members, key=lambda member: member[0]["file"]):
                relative = f"data/llm_outputs/outcome/{variant}/{model}/{source.name}"
                original_digest, packed_digest = hashlib.sha256(), hashlib.sha256()
                records, original_bytes, packed_bytes = 0, 0, 0
                with source.open("rb") as handle, archive.open(relative, "w", force_zip64=True) as target:
                    for line in handle:
                        original_digest.update(line)
                        original_bytes += len(line)
                        item = json.loads(line)
                        record = {key: item[key] for key in result["fields"]}
                        encoded = (json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
                        target.write(encoded)
                        packed_digest.update(encoded)
                        packed_bytes += len(encoded)
                        records += 1
                if records != int(row["records"]) or original_digest.hexdigest() != row["sha256"]:
                    raise ValueError(f"Source changed since the verified input audit: {source.name}")
                result["files"].append(dict(path=relative, archive=name, records=records,
                    original_sha256=original_digest.hexdigest(), sha256=packed_digest.hexdigest(),
                    original_bytes=original_bytes, bytes=packed_bytes))
                archive_records += records
        final = destination / name
        temporary.rename(final)
        result["archives"].append(dict(file=name, bytes=final.stat().st_size,
            sha256=hashlib.sha256(final.read_bytes()).hexdigest(), records=archive_records))
        print(f"Packed {name}: {len(members)} files, {archive_records:,} records", flush=True)
    result["total_records"] = sum(row["records"] for row in result["files"])
    result["total_files"] = len(result["files"])
    (destination / "generation_bundle_manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Complete: {result['total_files']} files and {result['total_records']:,} records", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--code-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    pack(args.code_dir.resolve(), args.manifest.resolve(), args.output_dir.resolve())

"""Validate the complete thesis generation design without exposing respondent data.

Reads local prompt manifests and JSONL only. Extras from historical waves are
listed separately. Every expected file, ID, reference label and unique key is
checked before analysis; removed grouped parsing failures remain a later step.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import math

CODE = Path(__file__).resolve().parents[2]
MODELS = (
    "Mistral-7B-Instruct-v0_3", "Qwen2_5-7B-Instruct-GPTQ-Int4",
    "Qwen2_5-32B-Instruct", "Qwen2_5-72B-Instruct", "Llama-3_3-70B-Instruct",
)
WAVES = {
    "1290": (10, 11, 14, 15, 22, 23, 25, 26),
    "1290_original_scale": (10, 11, 14, 15, 22, 23, 25, 26),
    "1500": (10, 14, 15, 22, 23, 25, 26),
    "1500_original_scale": (10, 14, 15, 22, 23, 25, 26),
}


def respondent_id(value):
    number = float(value)
    if not math.isfinite(number) or not number.is_integer():
        raise ValueError("Respondent identifiers must be finite integers")
    return str(int(number))


def reference(value):
    return " ".join(str(value).split())


def validate_generation(path, expected):
    seen = set()
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for line_number, line in enumerate(handle, 1):
            digest.update(line)
            row = json.loads(line)
            if not {"id", "label", "predict"} <= row.keys():
                raise ValueError(f"{path.name}:{line_number}: required fields are absent")
            key = respondent_id(row["id"])
            if key in seen:
                raise ValueError(f"{path.name}:{line_number}: duplicate ID")
            if key not in expected:
                raise ValueError(f"{path.name}:{line_number}: ID absent from prompt manifest")
            if reference(row["label"]) != expected[key]:
                raise ValueError(f"{path.name}:{line_number}: reference label differs from prompt")
            seen.add(key)
    if seen != expected.keys():
        raise ValueError(f"{path.name}: {len(expected.keys() - seen)} prompt records have no output")
    return len(seen), digest.hexdigest()


def audit(code=CODE, files_only=False):
    output_root = code / "data/llm_outputs/outcome"
    rows, extras, errors = [], [], []
    for variant, waves in WAVES.items():
        files = list((output_root / variant).rglob("nosft_*.jsonl"))
        paths = {}
        for path in files:
            if path.name in paths:
                errors.append(f"{variant}: duplicate basename {path.name}")
            paths[path.name] = path
        expected_files = set()
        for wave in waves:
            suffixes = ("", "_baseline_notime", "_tanchored")
            if wave != waves[0]:
                suffixes += ("_trajectory",)
            for suffix in suffixes:
                stem = f"prompt_w{wave}{suffix}"
                manifest = code / "outputs/prompts" / variant / (stem + ".json")
                names = [f"nosft_{model}__{stem}.jsonl" for model in MODELS]
                expected_files.update(names)
                for name in names:
                    if name not in paths:
                        errors.append(f"{variant}: missing {name}")
                if not manifest.is_file():
                    errors.append(f"{variant}: missing prompt {manifest.name}")
                    continue
                if files_only:
                    continue
                records = json.loads(manifest.read_text(encoding="utf-8-sig"))
                expected = {respondent_id(row["id"]): reference(row["output"]) for row in records}
                if not expected or len(expected) != len(records):
                    errors.append(f"{variant}: empty or duplicate-ID prompt {manifest.name}")
                    continue
                for name in names:
                    if name not in paths:
                        continue
                    try:
                        count, sha256 = validate_generation(paths[name], expected)
                        rows.append(dict(variant=variant, file=name, records=count, sha256=sha256))
                    except (ValueError, TypeError, KeyError) as error:
                        errors.append(f"{variant}: {error}")
        extras.extend(f"{variant}/{name}" for name in sorted(paths.keys() - expected_files))
        print(f"Checked {variant}; {len(errors)} errors so far.", flush=True)
    destination = code / "outputs/evaluation/manuscript/audits"
    destination.mkdir(parents=True, exist_ok=True)
    result = dict(status="failed" if errors else "passed", files_only=files_only,
                  checked_files=len(rows), checked_records=sum(row["records"] for row in rows),
                  historical_extra_files=extras, errors=errors)
    (destination / "generation_input_audit.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    if rows:
        with (destination / "generation_input_manifest.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    if errors:
        raise ValueError("Generation audit failed:\n" + "\n".join(errors[:25]))
    print(json.dumps(result), flush=True)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--files-only", action="store_true")
    args = parser.parse_args()
    audit(files_only=args.files_only)

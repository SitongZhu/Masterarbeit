"""Audit historical versus revised parsing; export only aggregates by default."""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import json
import re
import pandas as pd

CODE = Path(__file__).resolve().parents[2]
SCALES = {"1290_original_scale": 7, "1500_original_scale": 11}


def patterns(scale):
    values = "|".join(map(str, range(1, scale + 1)))
    return (re.compile(r"(?<![0-9])(?:" + values + r")(?![0-9])"),
            re.compile(r"(?<![\w.,+\-\u2212\u2013\u2014])(?:" + values
                       + r")(?![\w]|[.,][0-9])"))


def extract(pattern, text):
    hit = pattern.search(text)
    return hit.group() if hit else ""


def audit(code=CODE, raw_root=None, private_records=None, unique_predictions=None):
    summaries, oracles, changed_records = [], [], []
    input_hashes, raw_counts, expected_counts = {}, Counter(), Counter()
    for variant, scale in SCALES.items():
        historical, strict = patterns(scale)
        lookup = {}
        totals = []
        path = code / f"data/analysis_inputs/analyse_{variant}.csv"
        with path.open("rb") as handle:
            input_hashes[variant] = hashlib.file_digest(handle, "sha256").hexdigest()
        header = pd.read_csv(path, nrows=0).columns
        wave_column = "wave_id_from_list" if "wave_id_from_list" in header else "wave"
        cols = ["llm_model", "prompt_variant", wave_column, "label", "predict"]
        if private_records:
            cols.append("lfdn")
        for chunk in pd.read_csv(path, dtype=str, keep_default_na=False,
                                 chunksize=100000, usecols=cols):
            chunk = chunk.rename(columns={wave_column: "wave"})
            if chunk.predict.str.contains(r"<U\+[0-9A-Fa-f]{4,8}>", regex=True).any():
                raise RuntimeError("Unicode serialization artifacts remain; rebuild UTF-8 inputs first.")
            for value in chunk.predict.unique():
                if value not in lookup:
                    lookup[value] = (extract(historical, value), extract(strict, value))
            old = chunk.predict.map(lambda value: lookup[value][0])
            new = chunk.predict.map(lambda value: lookup[value][1])
            label = chunk.label.str.strip()
            changed = old.ne(new)
            if private_records and changed.any():
                records = chunk.loc[changed].copy()
                records.insert(0, "variant", variant)
                records["historical_category"] = old[changed]
                records["revised_category"] = new[changed]
                changed_records.append(records)
            if raw_root:
                for row in chunk[["llm_model", "prompt_variant", "label", "predict"]].itertuples(index=False, name=None):
                    expected_counts[(variant,) + row[:2] +
                                    (row[2].replace("\r\n", "\n"), row[3].replace("\r\n", "\n"))] += 1
            data = chunk[["llm_model", "prompt_variant", "wave"]].copy()
            data["records"] = 1
            data["historically_unparsed"] = old.eq("").astype(int)
            data["revised_unparsed"] = new.eq("").astype(int)
            data["changed_category"] = changed.astype(int)
            data["historical_correct_on_changed"] = (changed & old.eq(label)).astype(int)
            data["revised_correct_on_changed"] = (changed & new.eq(label)).astype(int)
            for name, expression in {
                "contains_signed_number": r"[+\-\u2212\u2013\u2014][0-9]",
                "contains_decimal_or_dotted_number": r"[0-9][.,][0-9]",
                "contains_scientific_number": r"[0-9][eE][+\-]?[0-9]",
            }.items():
                data[name] = chunk.predict.str.contains(expression, regex=True).astype(int)
            totals.append(data.groupby(["llm_model", "prompt_variant", "wave"], as_index=False).sum())
        summary = pd.concat(totals).groupby(["llm_model", "prompt_variant", "wave"], as_index=False).sum()
        summary.insert(0, "variant", variant)
        summaries.append(summary)
        if unique_predictions:
            oracles.extend({"variant": variant, "predict": value,
                            "historical_category": pair[0], "revised_category": pair[1]}
                           for value, pair in lookup.items())
        print(f"Audited {variant}: {summary.records.sum()} records; "
              f"{summary.changed_category.sum()} changed categories.", flush=True)

    raw_files = 0
    if raw_root:
        from audit_generation_inputs import MODELS, WAVES
        for variant in SCALES:
            files = list((Path(raw_root) / variant).rglob("nosft_*.jsonl"))
            by_name = {path.name: path for path in files}
            assert len(by_name) == len(files), "Duplicate raw-generation filename"
            for wave in WAVES[variant]:
                suffixes = ("", "_baseline_notime", "_tanchored")
                if wave != WAVES[variant][0]:
                    suffixes += ("_trajectory",)
                for suffix in suffixes:
                    condition = suffix[1:] if suffix else "baseline"
                    for model in MODELS:
                        path = by_name[f"nosft_{model}__prompt_w{wave}{suffix}.jsonl"]
                        with path.open(encoding="utf-8") as handle:
                            for line in handle:
                                row = json.loads(line)
                                key = (variant, model, condition, str(row["label"]).replace("\r\n", "\n"),
                                       str(row["predict"]).replace("\r\n", "\n"))
                                raw_counts[key] += 1
                        raw_files += 1
        if expected_counts != raw_counts:
            missing, extra = expected_counts - raw_counts, raw_counts - expected_counts
            if private_records:
                debug = dict(missing=[dict(key=k, count=v) for k, v in list(missing.items())[:10]],
                             extra=[dict(key=k, count=v) for k, v in list(extra.items())[:10]])
                Path(private_records).with_suffix('.raw_text_differences.json').write_text(
                    json.dumps(debug, ensure_ascii=False, indent=2), encoding='utf-8')
            raise AssertionError(f"Raw text comparison differs: {sum(missing.values())} analytical / "
                                 f"{sum(extra.values())} generation records")

    result = pd.concat(summaries, ignore_index=True)
    out = code / "outputs/evaluation/manuscript/audits"
    out.mkdir(parents=True, exist_ok=True)
    result.to_csv(out / "original_scale_parsing_by_wave.csv", index=False)
    report = dict(status="passed", analysis_input_sha256=input_hashes,
                  historical_digit_boundaries_replaced=True, records=int(result.records.sum()),
                  changed_categories={k: int(v) for k, v in result.groupby("variant").changed_category.sum().items()},
                  historical_correct_on_changed=int(result.historical_correct_on_changed.sum()),
                  revised_correct_on_changed=int(result.revised_correct_on_changed.sum()),
                  raw_generation_files_verified=raw_files,
                  raw_text_and_labels_match_analysis_inputs=bool(raw_root),
                  raw_comparison_normalization="CRLF to LF only; Windows CSV text connections add carriage returns")
    (out / "original_scale_parsing_audit.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if private_records:
        private = pd.concat(changed_records, ignore_index=True) if changed_records else pd.DataFrame()
        private.to_csv(private_records, index=False)
    if unique_predictions:
        pd.DataFrame(oracles).to_csv(unique_predictions, index=False)
    print(json.dumps(report, indent=2), flush=True)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--code-root", type=Path, default=CODE)
    parser.add_argument("--raw-root", type=Path)
    parser.add_argument("--private-records", type=Path)
    parser.add_argument("--unique-predictions", type=Path)
    args = parser.parse_args()
    audit(args.code_root, args.raw_root, args.private_records, args.unique_predictions)

"""Diagnose signed/decimal token sensitivity without changing thesis scoring.

The historical parser uses digit boundaries. The diagnostic parser also
excludes a numeric hit embedded in a signed or decimal token. This comparison
is not a replacement evaluation and does not require exact-answer formatting.
Only aggregated counts are exported.
"""
from pathlib import Path
import json
import re
import pandas as pd

CODE = Path(__file__).resolve().parents[2]


def audit():
    summaries = []
    unicode_artifacts = 0
    for variant, scale in [("1290_original_scale", 7), ("1500_original_scale", 11)]:
        values = "|".join(map(str, range(1, scale+1)))
        historical = re.compile(r"(?<![0-9])(?:"+values+r")(?![0-9])")
        diagnostic = re.compile(r"(?<![0-9.,+-])(?:"+values+r")(?![0-9]|[.,][0-9])")
        def extract(pattern, text):
            hit = pattern.search(text)
            return hit.group() if hit else ""
        totals = []
        path = CODE / f"data/analysis_inputs/analyse_{variant}.csv"
        for chunk in pd.read_csv(path, dtype=str, keep_default_na=False, chunksize=100000,
                                 usecols=["llm_model", "prompt_variant", "label", "predict"]):
            unique = chunk.predict.unique()
            unicode_artifacts += int(chunk.predict.str.contains(r"<U\+[0-9A-Fa-f]{4,8}>", regex=True).sum())
            old_map = {s: extract(historical, s) for s in unique}
            new_map = {s: extract(diagnostic, s) for s in unique}
            old, new = chunk.predict.map(old_map), chunk.predict.map(new_map)
            label = chunk.label.str.strip()
            chunk["records"] = 1
            chunk["historically_unparsed"] = old.eq("").astype(int)
            chunk["token_sensitive"] = old.ne(new).astype(int)
            chunk["historical_correct_on_sensitive"] = (old.ne(new) & old.eq(label)).astype(int)
            chunk["diagnostic_correct_on_sensitive"] = (old.ne(new) & new.eq(label)).astype(int)
            totals.append(chunk.groupby(["llm_model", "prompt_variant"], as_index=False)[[
                "records", "historically_unparsed", "token_sensitive",
                "historical_correct_on_sensitive", "diagnostic_correct_on_sensitive"]].sum())
        summary = pd.concat(totals).groupby(["llm_model", "prompt_variant"], as_index=False).sum()
        summary.insert(0, "variant", variant)
        summaries.append(summary)
    result = pd.concat(summaries, ignore_index=True)
    out = CODE / "outputs/evaluation/manuscript/audits"
    out.mkdir(parents=True, exist_ok=True)
    result.to_csv(out / "original_scale_token_sensitivity.csv", index=False)
    if unicode_artifacts:
        raise RuntimeError(f"Found {unicode_artifacts} predictions containing Unicode serialization artifacts. "
                           "Rebuild analysis inputs from the original JSONL with the UTF-8 writer; "
                           "digits inside these artifacts must not become scale responses.")
    counts = result.groupby("variant")["token_sensitive"].sum().to_dict()
    print(json.dumps(dict(diagnostic_only=True, historical_scoring_preserved=True,
                          token_sensitive_records=counts)), flush=True)
    return result


if __name__ == "__main__":
    audit()

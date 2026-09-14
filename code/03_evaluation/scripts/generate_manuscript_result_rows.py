#!/usr/bin/env python3

"""Generate LaTeX row fragments for manuscript result tables."""

from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
EVAL = ROOT / "outputs" / "evaluation"
OUT = EVAL / "publication" / "latex"
OUT.mkdir(parents=True, exist_ok=True)

TASK_ORDER = [
    "Climate-growth grouped",
    "Climate-growth original scale",
    "Left-right grouped",
    "Left-right original scale",
]
MODEL_ORDER = [
    "Mistral-7B",
    "Qwen2.5-7B",
    "Qwen2.5-32B",
    "Llama-3.3-70B",
    "Qwen2.5-72B",
]


def standard_task(value):
    return {
        "Climate-growth original": "Climate-growth original scale",
        "Left-right original": "Left-right original scale",
    }.get(value, value)


def tex_task(value):
    return standard_task(value)


def fmt3(value):
    return "--" if pd.isna(value) else f"{value:.3f}"


def fmt2(value):
    return "--" if pd.isna(value) else f"{value:.2f}"


def fmt_signed_math(value):
    if pd.isna(value):
        return "--"
    return f"${value:+.3f}$"


def fmt_math_2(value):
    if pd.isna(value):
        return "--"
    return f"${value:.2f}$" if value < 0 else f"{value:.2f}"


def fmt_int(value):
    return f"{int(value):,}"


def write_rows(filename, rows):
    path = OUT / filename
    path.write_text("\n".join(rows + [r"\hline"]) + "\n", encoding="utf-8")
    print(path)


def structural_rows():
    data = pd.read_csv(EVAL / "tables" / "structural_fidelity_summary.csv")
    data["task"] = data["task"].map(standard_task)
    data["task_order"] = data["task"].map({task: i for i, task in enumerate(TASK_ORDER)})
    data["prompt_order"] = data["prompt"].map({"No-time": 0, "Trajectory": 1})
    data["method_order"] = data["method"].map({"OLS": 0, "Ordinal probit": 1})
    data = data.sort_values(["task_order", "prompt_order", "method_order"])
    rows = []
    for row in data.itertuples(index=False):
        correlation = (
            f"{fmt_math_2(row.median_coefficient_correlation)} "
            f"({fmt_math_2(row.min_coefficient_correlation)}, "
            f"{fmt_math_2(row.max_coefficient_correlation)})"
        )
        agreement = (
            f"{fmt2(row.median_sign_agreement)} "
            f"({fmt2(row.min_sign_agreement)}, {fmt2(row.max_sign_agreement)})"
        )
        rows.append(
            f"{tex_task(row.task)} & {row.prompt} & {row.method} & "
            f"{correlation} & {agreement} \\\\"
        )
    write_rows("structural_fidelity_rows.tex", rows)


def ordinal_diagnostic_rows():
    data = pd.read_csv(EVAL / "tables" / "ordinal_probit_diagnostics_all.csv")
    data["task"] = data["task"].map(standard_task)
    data = data[data["ordinal_model"] != "not_estimated"].copy()
    baseline_order = {"covariates_only": 0, "lag_and_covariates": 1}
    task_order = {task: i for i, task in enumerate(TASK_ORDER)}
    rows = []
    for (baseline, task), group in data.groupby(["baseline", "task"], sort=False):
        rows.append(
            {
                "baseline_order": baseline_order[baseline],
                "task_order": task_order[task],
                "line": (
                    f"{'Covariates only' if baseline == 'covariates_only' else 'Lag and covariates'} & "
                    f"{tex_task(task)} & {int(group['n_classes'].max())} & {len(group)} & "
                    f"{fmt_int(group['n_train'].min())}--{fmt_int(group['n_train'].max())} & "
                    f"{int(group['predictor_count'].min())}"
                    f"{'--' + str(int(group['predictor_count'].max())) if group['predictor_count'].nunique() > 1 else ''} & "
                    f"{int((group['convergence_code'] == 0).sum())}/{len(group)} & "
                    f"{int(group['thresholds_strictly_ordered'].eq(True).sum())}/{len(group)} & "
                    f"{int(group['probability_rows_valid'].eq(True).sum())}/{len(group)} \\\\"
                ),
            }
        )
    rows = [item["line"] for item in sorted(rows, key=lambda item: (item["baseline_order"], item["task_order"]))]
    write_rows("ordinal_diagnostics_rows.tex", rows)


def main():
    structural_rows()
    ordinal_diagnostic_rows()


if __name__ == "__main__":
    main()

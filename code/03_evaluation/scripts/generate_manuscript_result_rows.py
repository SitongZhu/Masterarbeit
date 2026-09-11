#!/usr/bin/env python3

"""Generate LaTeX row fragments for manuscript result tables."""

from pathlib import Path

import numpy as np
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
    return standard_task(value).replace("Climate-growth", "Climate--growth").replace(
        "Left-right", "Left--right"
    )


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


def distance_metric_rows():
    rq1 = pd.read_csv(EVAL / "manuscript" / "tables" / "rq1_ordinal_covariates_only_comparison.csv")
    rq2 = pd.read_csv(EVAL / "manuscript" / "tables" / "rq2_ordinal_prior_state_comparison.csv")
    rows = []
    for task in ["Climate-growth original scale", "Left-right original scale"]:
        best = rq1[rq1["Task"].map(standard_task).eq(task)].sort_values(
            ["accuracy_prompt", "Model"], ascending=[False, True]
        ).iloc[0]
        rows.append(
            f"RQ1, no-time & {tex_task(task)} & {best['Model']} & {fmt3(best['prompt_mae'])} & "
            f"{fmt3(best['ordinal_mae'])} & {fmt3(best['prompt_within_one'])} & "
            f"{fmt3(best['ordinal_within_one'])} \\\\"
        )
    for task in ["Climate-growth original scale", "Left-right original scale"]:
        best = rq2[rq2["Task"].map(standard_task).eq(task)].sort_values(
            ["accuracy_trajectory", "Model"], ascending=[False, True]
        ).iloc[0]
        rows.append(
            f"RQ2, trajectory & {tex_task(task)} & {best['Model']} & {fmt3(best['trajectory_mae'])} & "
            f"{fmt3(best['ordinal_mae'])} & {fmt3(best['trajectory_within_one'])} & "
            f"{fmt3(best['ordinal_within_one'])} \\\\"
        )
    write_rows("ordinal_distance_metrics_rows.tex", rows)


def range_pp(values):
    rounded = sorted({round(value * 100, 1) for value in values if not pd.isna(value)})
    if len(rounded) == 1:
        return f"${rounded[0]:.1f}$"
    return f"${rounded[0]:.1f}$ to ${rounded[-1]:.1f}$"


def ordinal_multinomial_rows():
    cov = pd.read_csv(EVAL / "tables" / "ordinal_vs_multinomial_covariates_only.csv")
    lag = pd.read_csv(EVAL / "tables" / "ordinal_vs_multinomial_lag_covariates.csv")
    cov = cov[cov["Prompt"].eq("No-time baseline")].copy()
    cov["Task"] = cov["Task"].map(standard_task)
    lag["Task"] = lag["Task"].map(standard_task)
    rows = []
    for task in TASK_ORDER:
        rows.append(
            f"{tex_task(task)} & "
            f"{range_pp(cov.loc[cov['Task'].eq(task), 'ordinal_minus_multinomial'])} & "
            f"{range_pp(lag.loc[lag['Task'].eq(task), 'ordinal_minus_multinomial'])} \\\\"
        )
    write_rows("ordinal_multinomial_robustness_rows.tex", rows)


def model_summary_rows():
    data = pd.read_csv(EVAL / "figures" / "model_scale_robustness_summary.csv")
    data = data.sort_values("model_order")
    rows = [
        f"{row.Model} & {fmt3(row.mean_no_time_accuracy)} & "
        f"{fmt_signed_math(row.mean_trajectory_minus_carry_forward)} & "
        f"{fmt3(row.mean_changed_accuracy)} & {fmt3(row.mean_false_persistence)} \\\\"
        for row in data.itertuples(index=False)
    ]
    write_rows("model_scale_summary_rows.tex", rows)


def model_robustness_rows():
    rq1 = pd.read_csv(EVAL / "manuscript" / "tables" / "rq1_ordinal_covariates_only_comparison.csv")
    rq2 = pd.read_csv(EVAL / "manuscript" / "tables" / "rq2_ordinal_prior_state_comparison.csv")
    rq1["Task"] = rq1["Task"].map(standard_task)
    rq2["Task"] = rq2["Task"].map(standard_task)
    data = rq1.merge(
        rq2,
        on=["Task", "Model"],
        how="inner",
        suffixes=("_rq1", "_rq2"),
        validate="one_to_one",
    )
    data["task_order"] = data["Task"].map({task: i for i, task in enumerate(TASK_ORDER)})
    data["model_order"] = data["Model"].map({model: i for i, model in enumerate(MODEL_ORDER)})
    data = data.sort_values(["task_order", "model_order"])
    rows = []
    for row in data.itertuples(index=False):
        rows.append(
            f"{tex_task(row.Task)} & {row.Model} & {fmt3(row.accuracy_prompt)} & "
            f"{fmt3(row.accuracy_ordinal_rq1)} & {fmt3(row.accuracy_trajectory)} & "
            f"{fmt_signed_math(row.trajectory_minus_cf)} & {fmt3(row.accuracy_ordinal_rq2)} & "
            f"{fmt_signed_math(row.trajectory_minus_ordinal)} \\\\"
        )
    write_rows("model_robustness_details_rows.tex", rows)


def transition_rows():
    stable = pd.read_csv(EVAL / "tables" / "stable_changing_split_table.csv")
    dynamic = pd.read_csv(EVAL / "dynamic_validity_prior_state_summary.csv")
    stable["Task"] = stable["Task"].map(standard_task)
    dynamic["task"] = dynamic["task"].map(standard_task)
    dynamic = dynamic.rename(columns={"task": "Task", "model_short": "Model"})
    data = stable.merge(
        dynamic[
            [
                "Task",
                "Model",
                "a_previous",
                "ccr_anchor",
                "cda_anchor",
                "dccr_anchor",
            ]
        ],
        on=["Task", "Model"],
        how="left",
        validate="one_to_one",
    )
    data["task_order"] = data["Task"].map({task: i for i, task in enumerate(TASK_ORDER)})
    data["model_order"] = data["Model"].map({model: i for i, model in enumerate(MODEL_ORDER)})
    data = data.sort_values(["task_order", "model_order"])
    rows = []
    for _, row in data.iterrows():
        rows.append(
            f"{tex_task(row['Task'])} & {row['Model']} & {fmt3(row['Stable share'])} & "
            f"{fmt3(row['Acc. stable'])} & {fmt3(row['Acc. changed'])} & "
            f"{fmt3(row['Stable-change gap'])} & {fmt3(row['a_previous'])} & "
            f"{fmt3(1 - row['ccr_anchor'])} & {fmt3(row['ccr_anchor'])} & "
            f"{fmt3(row['cda_anchor'])} & {fmt3(row['dccr_anchor'])} \\\\"
        )
    write_rows("transition_diagnostics_details_rows.tex", rows)


def main():
    structural_rows()
    ordinal_diagnostic_rows()
    distance_metric_rows()
    ordinal_multinomial_rows()
    model_summary_rows()
    model_robustness_rows()
    transition_rows()


if __name__ == "__main__":
    main()

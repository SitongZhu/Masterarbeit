"""Recalculate the current thesis tables from unrounded, matched row predictions.

RQ1 and RQ2 use ordinal-available samples. RQ3 includes every retained
lag-available trajectory row; distance metrics use a joint parsed subset.
Default execution scores respondent records. --from-aggregates only re-exports
previously computed summaries; it does not repeat model fitting or scoring.
"""
from pathlib import Path
import argparse
import os
import numpy as np
import pandas as pd

CODE = Path(__file__).resolve().parents[2]
EVAL = Path(os.environ.get("THESIS_EVALUATION_ROOT", CODE / "outputs/evaluation")).resolve()
OUT = EVAL / "publication"
TASKS = {"1290": "Climate-growth grouped", "1290_original_scale": "Climate-growth original scale",
         "1500": "Left-right grouped", "1500_original_scale": "Left-right original scale"}
MODELS = ["Mistral-7B", "Qwen2.5-7B", "Qwen2.5-32B", "Llama-3.3-70B", "Qwen2.5-72B"]


def short(model):
    if "Mistral" in model:
        return MODELS[0]
    if "Llama" in model:
        return MODELS[3]
    return "Qwen2.5-" + ("72B" if "72B" in model else "32B" if "32B" in model else "7B")


def read(path):
    return pd.read_csv(path, dtype={key: str for key in (
        "lfdn", "wave", "label_cat", "predict_cat", "ordinal_pred_cat",
        "statistical_pred_cat", "vorwelle_label_cat")}, low_memory=False)


def transition_metrics(group):
    stable = group.label_cat.eq(group.vorwelle_label_cat)
    correct = group.predict_cat.notna() & group.predict_cat.eq(group.label_cat)
    parsed = group[group.predict_cat.notna()].copy()
    changed = parsed.label_cat.ne(parsed.vorwelle_label_cat)
    departed = parsed.predict_cat.ne(parsed.vorwelle_label_cat)
    # Grouped category scores preserve the ordering used by the R evaluator.
    category_scores = {"Links": -1, "Neutral": 0, "Rechts": 1,
                       "Vorrang_fuer_Bekaempfung_des_Klimawandels": -1,
                       "Mittelposition": 0, "Vorrang_fuer_Wirtschaftswachstum": 1}
    def numeric(series):
        return pd.to_numeric(series.map(lambda value: category_scores.get(value, value)))
    observed_delta = numeric(parsed.label_cat) - numeric(parsed.vorwelle_label_cat)
    predicted_delta = numeric(parsed.predict_cat) - numeric(parsed.vorwelle_label_cat)
    aligned = changed & departed & np.sign(observed_delta).eq(np.sign(predicted_delta))
    count_changed, count_captured = int(changed.sum()), int((changed & departed).sum())
    n, ns = len(group), int(stable.sum())
    acc_stable, acc_changed = correct[stable].mean(), correct[~stable].mean()
    assert np.isclose(correct.mean(), ns/n*acc_stable + (1-ns/n)*acc_changed)
    return dict(n=n, stable_n=ns, changed_n=n-ns, stable_share=ns/n,
                stable_accuracy=acc_stable, changed_accuracy=acc_changed,
                stable_change_gap=acc_stable-acc_changed, trajectory_accuracy=correct.mean(),
                correct_stable_share=correct[stable].sum()/correct.sum(),
                parsed_n=len(parsed), parsed_changed_n=count_changed,
                captured_n=count_captured, direction_aligned_n=int(aligned.sum()),
                previous_agreement=(~departed).mean(),
                false_persistence=(changed & ~departed).sum()/count_changed,
                ccr=count_captured/count_changed,
                cda=aligned.sum()/count_captured if count_captured else np.nan,
                dccr=aligned.sum()/count_changed)


def calculate():
    rq1 = read(EVAL / "manuscript/tables/rq1_ordinal_covariates_only_comparison.csv")
    rq2 = read(EVAL / "manuscript/tables/rq2_ordinal_prior_state_comparison.csv")
    comparisons, distances, transitions = [], [], []
    for variant, task in TASKS.items():
        directory = EVAL / f"analysis_{variant}/statistical_baselines"
        for rq, rowfile, prefix in [
            ("RQ1", "covariates_only_nontrajectory_row_comparison.csv", "covariates_only"),
            ("RQ2", "trajectory_baseline_row_comparison.csv", "lag_covariate")]:
            rows = read(directory / rowfile)
            prompt = "baseline_notime" if rq == "RQ1" else "trajectory"
            rows = rows[rows.prompt_variant.eq(prompt)].copy()
            assert not rows.duplicated(["lfdn", "wave", "model", "prompt_variant"]).any()
            op = read(directory / f"{prefix}_ordinal_probit_predictions.csv")
            mn = read(directory / f"{prefix}_multinomial_logit_predictions.csv")
            op = op[["lfdn", "wave", "label_cat", "ordinal_pred_cat"]].rename(columns={"label_cat": "op_label"})
            mn = mn[["lfdn", "wave", "label_cat", "statistical_pred_cat"]].rename(
                columns={"label_cat": "mn_label", "statistical_pred_cat": "multinomial_pred"})
            rows = rows.merge(op, on=["lfdn", "wave"], how="left", validate="many_to_one")
            rows = rows.merge(mn, on=["lfdn", "wave"], how="left", validate="many_to_one")
            for model, group in rows.groupby("model"):
                primary = group[group.ordinal_pred_cat.notna()]
                stored = (rq1 if rq == "RQ1" else rq2)
                stored = stored[stored.Task.eq(task) & stored.model.eq(model)].iloc[0]
                assert len(primary) == stored.n_total
                assert primary.label_cat.eq(primary.op_label).all()
                llm_acc = primary.predict_cat.eq(primary.label_cat).mean()
                op_acc = primary.ordinal_pred_cat.eq(primary.label_cat).mean()
                accuracy_name = "accuracy_prompt" if rq == "RQ1" else "accuracy_trajectory"
                assert np.isclose(llm_acc, stored[accuracy_name], rtol=0, atol=1e-12)
                assert np.isclose(op_acc, stored.accuracy_ordinal, rtol=0, atol=1e-12)
                joint = primary[primary.multinomial_pred.notna()]
                assert joint.label_cat.eq(joint.mn_label).all()
                accuracies = [joint[col].eq(joint.label_cat).mean() for col in
                              ["predict_cat", "ordinal_pred_cat", "multinomial_pred"]]
                comparisons.append(dict(Task=task, Model=short(model), Comparison=rq,
                    primary_N=len(primary), joint_N=len(joint), llm_accuracy=accuracies[0],
                    ordinal_accuracy=accuracies[1], multinomial_accuracy=accuracies[2],
                    llm_minus_ordinal=accuracies[0]-accuracies[1],
                    llm_minus_multinomial=accuracies[0]-accuracies[2],
                    ordinal_minus_multinomial=accuracies[1]-accuracies[2]))
                if "original_scale" in variant:
                    valid = primary.predict_cat.notna()
                    human = pd.to_numeric(primary.loc[valid, "label_cat"])
                    pred = pd.to_numeric(primary.loc[valid, "predict_cat"])
                    baseline = pd.to_numeric(primary.loc[valid, "ordinal_pred_cat"])
                    distances.append(dict(Task=task, Model=short(model), Comparison=rq,
                        primary_N=len(primary), parsed_N=int(valid.sum()),
                        llm_mae=(pred-human).abs().mean(), ordinal_mae=(baseline-human).abs().mean(),
                        llm_within_one=((pred-human).abs() <= 1).mean(),
                        ordinal_within_one=((baseline-human).abs() <= 1).mean()))
                if rq == "RQ2":
                    transitions.append(dict(Task=task, Model=short(model), **transition_metrics(group)))
        print(f"Rescored {task}", flush=True)
    return rq1, rq2, pd.DataFrame(comparisons), pd.DataFrame(distances), pd.DataFrame(transitions)


def fmt(value, digits=3):
    return "--" if pd.isna(value) else f"{value:.{digits}f}"


def signed(value, digits=3):
    return f"${value:+.{digits}f}$" if value else f"${value:.{digits}f}$"


def write_rows(name, rows):
    (OUT / "latex" / name).write_text("\n".join(rows + [r"\hline"]) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--from-aggregates", action="store_true")
    args = parser.parse_args()
    (OUT / "tables").mkdir(parents=True, exist_ok=True)
    (OUT / "latex").mkdir(parents=True, exist_ok=True)
    if args.from_aggregates:
        rq1 = read(EVAL / "manuscript/tables/rq1_ordinal_covariates_only_comparison.csv")
        rq2 = read(EVAL / "manuscript/tables/rq2_ordinal_prior_state_comparison.csv")
        spec = read(OUT / "tables/matched_specification_comparison.csv")
        distance = read(OUT / "tables/matched_distance_metrics.csv")
        transition = read(OUT / "tables/transition_diagnostics_exact.csv")
        print("Exporting existing aggregates; respondent records are not rescored.", flush=True)
    else:
        rq1, rq2, spec, distance, transition = calculate()
    for name, table in [("matched_specification_comparison", spec), ("matched_distance_metrics", distance),
                        ("transition_diagnostics_exact", transition)]:
        table.to_csv(OUT / "tables" / f"{name}.csv", index=False)
    best1 = rq1.sort_values(["accuracy_prompt", "Model"], ascending=[False, True]).groupby("Task", sort=False).head(1)
    best2 = rq2.sort_values(["accuracy_trajectory", "Model"], ascending=[False, True]).groupby("Task", sort=False).head(1)
    dist_rows = []
    for rq, selected in [("RQ1", best1), ("RQ2", best2)]:
        for task in TASKS.values():
            if "original scale" not in task:
                continue
            model = selected.loc[selected.Task.eq(task), "Model"].iloc[0]
            row = distance[distance.Task.eq(task) & distance.Model.eq(model) & distance.Comparison.eq(rq)].iloc[0]
            values = [row.llm_mae, row.ordinal_mae, row.llm_within_one, row.ordinal_within_one]
            dist_rows.append(f"{rq} & {task} & {model} & {row.parsed_N:,} & " + " & ".join(map(fmt, values)) + r" \\")
    write_rows("reviewed_distance_rows.tex", dist_rows)
    specification_rows, selected_rows, model_rows, accuracy_rows, capture_rows = [], [], [], [], []
    for task in TASKS.values():
        differences = []
        for rq in ["RQ1", "RQ2"]:
            values = spec.loc[spec.Task.eq(task) & spec.Comparison.eq(rq), "ordinal_minus_multinomial"] * 100
            rounded = sorted(set(round(value, 2) for value in values))
            differences.append(signed(rounded[0], 2) if len(rounded) == 1 else
                               f"{signed(min(values), 2)} to {signed(max(values), 2)}")
        specification_rows.append(f"{task} & " + " & ".join(differences) + r" \\")
        selected_model = best2.loc[best2.Task.eq(task), "Model"].iloc[0]
        selected = spec[spec.Task.eq(task) & spec.Model.eq(selected_model) & spec.Comparison.eq("RQ2")].iloc[0]
        selected_rows.append(f"{task} & {selected_model} & {selected.joint_N:,} & "
                             f"{signed(100*selected.llm_minus_ordinal, 2)} & {signed(100*selected.llm_minus_multinomial, 2)}" + r" \\")
        for target, columns in [(model_rows, 9), (accuracy_rows, 7), (capture_rows, 10)]:
            target.append(r"\hline\multicolumn{" + str(columns) + r"}{l}{\textit{" + task + r"}} \\")
        for model in MODELS:
            a = rq1[rq1.Task.eq(task) & rq1.Model.eq(model)].iloc[0]
            b = rq2[rq2.Task.eq(task) & rq2.Model.eq(model)].iloc[0]
            t = transition[transition.Task.eq(task) & transition.Model.eq(model)].iloc[0]
            model_rows.append(f"{model} & {a.n_total:,} & {fmt(a.accuracy_prompt)} & {fmt(a.accuracy_ordinal)} & "
                f"{b.n_total:,} & {fmt(b.accuracy_trajectory)} & {signed(100*b.trajectory_minus_cf)} & "
                f"{fmt(b.accuracy_ordinal)} & {signed(100*b.trajectory_minus_ordinal)}" + r" \\")
            accuracy_rows.append(f"{model} & {t.stable_n:,} & {t.changed_n:,} & " +
                " & ".join(fmt(t[c]) for c in ["stable_share", "stable_accuracy", "changed_accuracy", "stable_change_gap"]) + r" \\")
            capture_rows.append(f"{model} & {t.parsed_n:,} & {t.parsed_changed_n:,} & {t.captured_n:,} & {t.direction_aligned_n:,} & " +
                " & ".join(fmt(t[c]) for c in ["previous_agreement", "false_persistence", "ccr", "cda", "dccr"]) + r" \\")
    for name, rows in [("reviewed_ordinal_multinomial_rows", specification_rows),
                       ("reviewed_selected_specification_rows", selected_rows),
                       ("reviewed_model_comparison_rows", model_rows),
                       ("reviewed_transition_accuracy_rows", accuracy_rows),
                       ("reviewed_transition_capture_rows", capture_rows)]:
        write_rows(name + ".tex", rows)
    stability = read(EVAL / "tables/covariates_only_iteration_stability_summary.csv")
    rows = []
    for row in stability.itertuples(index=False):
        task = "Climate-growth" if row.task.startswith("Climate") else "Left-right"
        rows.append(f"{task} & {row.iteration_limit:,} & {row.converged_fits}/{row.estimated_fits} & "
            f"{100*row.min_prediction_agreement_with_final:.2f}\\% & "
            f"{100*row.max_accuracy_abs_diff_from_final:.3f} & {100*row.max_deviance_relative_diff_from_final:.4f}" + r" \\")
    write_rows("iteration_stability_rows.tex", rows)


if __name__ == "__main__":
    main()

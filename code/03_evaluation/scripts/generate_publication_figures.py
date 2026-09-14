"""Regenerate thesis figures with publication-facing labels.

The script reads archived CSV outputs only. It does not refit any model or alter an
estimand. Outputs stay in outputs/evaluation/publication; no manuscript checkout is required.
"""

from __future__ import annotations

import re
import shutil
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.lines import Line2D
from matplotlib.ticker import PercentFormatter


SCRIPT = Path(__file__).resolve()
CODE = SCRIPT.parents[2]
RESULT = CODE.parent
EVAL = Path(os.environ.get("THESIS_EVALUATION_ROOT", CODE / "outputs" / "evaluation")).resolve()
PAPER_PICS = EVAL / "publication" / "figures"
CURATED = EVAL / "publication" / "curated"

EN = "-"  # Hyphens in compound figure labels.
TASK_DIRS = {
    "Climate-growth grouped": "analysis_1290",
    "Climate-growth original scale": "analysis_1290_original_scale",
    "Left-right grouped": "analysis_1500",
    "Left-right original scale": "analysis_1500_original_scale",
}
TASK_LABELS = {
    "Climate-growth grouped": f"Climate{EN}growth, grouped",
    "Climate-growth original": f"Climate{EN}growth, original scale",
    "Climate-growth original scale": f"Climate{EN}growth, original scale",
    "Left-right grouped": f"Left{EN}right, grouped",
    "Left-right original": f"Left{EN}right, original scale",
    "Left-right original scale": f"Left{EN}right, original scale",
    "1290": f"Climate{EN}growth, grouped",
    "1290_original_scale": f"Climate{EN}growth, original scale",
    "1500": f"Left{EN}right, grouped",
    "1500_original_scale": f"Left{EN}right, original scale",
}
TASK_ORDER = [
    f"Climate{EN}growth, grouped",
    f"Climate{EN}growth, original scale",
    f"Left{EN}right, grouped",
    f"Left{EN}right, original scale",
]
PROMPT_LABELS = {
    "baseline_notime": "No-time",
    "baseline": "Date-bounded",
    "tanchored": "Context-anchored",
    "trajectory": "Trajectory",
    "No-time baseline": "No-time",
    "Date baseline": "Date-bounded",
    "Context-anchored prompt": "Context-anchored",
}
PROMPT_ORDER = ["No-time", "Date-bounded", "Context-anchored", "Trajectory"]
MODEL_ORDER = [
    "Mistral-7B",
    "Qwen2.5-7B (4-bit)",
    "Qwen2.5-32B",
    "Qwen2.5-72B",
    "Llama-3.3-70B",
]
MODEL_COLORS = {
    "Mistral-7B": "#4C78A8",
    "Qwen2.5-7B (4-bit)": "#F58518",
    "Qwen2.5-32B": "#54A24B",
    "Qwen2.5-72B": "#B279A2",
    "Llama-3.3-70B": "#E45756",
}
PROMPT_COLORS = {
    "No-time": "#4C78A8",
    "Date-bounded": "#F58518",
    "Context-anchored": "#72B7B2",
    "Trajectory": "#B279A2",
}
METRIC_COLORS = {
    "Modal, designated preceding wave": "#7F7F7F",
    "Covariates-only ordinal probit": "#54A24B",
    "Trajectory accuracy": "#B279A2",
    "Information-condition accuracy": "#4C78A8",
    "Carry-forward accuracy": "#F58518",
    "Lag-and-covariates ordinal probit": "#72B7B2",
}


def setup_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 10,
            "axes.titlesize": 11,
            "axes.labelsize": 10,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.edgecolor": "#B8B8B8",
            "grid.color": "#E6E6E6",
            "grid.linewidth": 0.8,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
        }
    )


def short_model(value: object) -> str:
    text = str(value)
    norm = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")
    if "mistral" in norm:
        return "Mistral-7B"
    if "qwen2_5" in norm and "7b" in norm:
        return "Qwen2.5-7B (4-bit)"
    if "qwen2_5" in norm and "32b" in norm:
        return "Qwen2.5-32B"
    if "qwen2_5" in norm and "72b" in norm:
        return "Qwen2.5-72B"
    if "llama" in norm and "70b" in norm:
        return "Llama-3.3-70B"
    return text.replace("_", " ")


def task_label(value: object, representation: object | None = None) -> str:
    text = str(value)
    if text in TASK_LABELS:
        return TASK_LABELS[text]
    if representation is not None:
        key = text if str(representation) == "grouped" else f"{text}_original_scale"
        if key in TASK_LABELS:
            return TASK_LABELS[key]
    text = text.replace("Climate-growth", f"Climate{EN}growth")
    text = text.replace("Left-right", f"Left{EN}right")
    return text


def latest_common_run() -> Path:
    canonical = EVAL / "common_sample_accuracy" / "runs" / "run_manuscript"
    if (canonical.joinpath("common_sample_accuracy_overall.csv").exists()):
        return canonical
    candidates = sorted(
        p
        for p in (EVAL / "common_sample_accuracy" / "runs").glob("run_*")
        if (p / "common_sample_accuracy_overall.csv").exists()
    )
    if not candidates:
        raise FileNotFoundError("No common-sample run with archived CSVs was found")
    return candidates[-1]


def save_figure(fig: plt.Figure, paper_name: str, curated_relative: str) -> None:
    paper_path = PAPER_PICS / paper_name
    curated_path = CURATED / curated_relative
    paper_path.parent.mkdir(parents=True, exist_ok=True)
    curated_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(paper_path, dpi=180, bbox_inches="tight", facecolor="white")
    shutil.copy2(paper_path, curated_path)
    plt.close(fig)


def percent_axis(ax: plt.Axes, upper: float = 1.0) -> None:
    ax.set_ylim(0, upper)
    ax.yaxis.set_major_formatter(PercentFormatter(1.0))
    ax.grid(axis="y")
    ax.set_axisbelow(True)


def figure_information_ladder() -> None:
    df = pd.read_csv(EVAL / "figures" / "information_ladder_selection_details.csv")
    df["task_publication"] = df["Task"].map(task_label)
    metrics = [
        ("Baseline:\nCovariates\nonly", "covariates_only"),
        ("LLM:\nBest\nno-time", "best_nontrajectory"),
        ("Baseline:\nPrior-wave\nmodal", "modal"),
        ("Baseline:\nCarry-\nforward", "carry_forward"),
        ("Baseline:\nLag +\ncovariates", "lag_covariates"),
        ("LLM:\nBest\ntrajectory", "best_trajectory"),
    ]
    colors = ["#54A24B", "#4C78A8", "#7F7F7F", "#F58518", "#72B7B2", "#B279A2"]
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), sharey=True)
    for ax, task in zip(axes.flat, TASK_ORDER):
        row = df.loc[df["task_publication"] == task].iloc[0]
        values = [float(row[col]) for _, col in metrics]
        x = np.arange(len(metrics))
        ax.plot(x[:2], values[:2], color="#777777", lw=1.4, zorder=1)
        ax.plot(x[2:], values[2:], color="#777777", lw=1.4, zorder=1)
        ax.scatter(x, values, s=85, c=colors, edgecolor="#333333", linewidth=0.8, zorder=2)
        ax.axvline(1.5, color="#B8B8B8", lw=1, ls="--")
        ax.set_xticks(x, [name for name, _ in metrics])
        ax.tick_params(axis="x", labelsize=9, pad=4)
        ax.set_title(task, fontweight="bold")
        percent_axis(ax)
    axes[0, 0].set_ylabel("Exact-match current-state accuracy")
    axes[1, 0].set_ylabel("Exact-match current-state accuracy")
    fig.suptitle("Exact-match current-state accuracy along the information ladder", x=0.06, ha="left", fontsize=18)
    fig.text(
        0.06,
        0.925,
        "The dashed divider separates conditions without and with prior-wave information.",
        ha="left",
        fontsize=11,
    )
    fig.tight_layout(rect=(0.03, 0.04, 1, 0.90))
    save_figure(fig, "Figure_1_information_ladder.png", "main_text/Figure_1_information_ladder.png")


def figure_trajectory_contrast() -> None:
    run = latest_common_run()
    df = pd.read_csv(run / "trajectory_vs_best_nontrajectory_common_sample.csv")
    df["task_publication"] = [task_label(v, r) for v, r in zip(df["variant"], df["representation"])]
    df["model_publication"] = df["model"].map(short_model)
    fig, ax = plt.subplots(figsize=(13, 7))
    width = 0.15
    x = np.arange(len(TASK_ORDER))
    for j, model in enumerate(MODEL_ORDER):
        sub = df.set_index(["task_publication", "model_publication"])
        vals = [sub.loc[(task, model), "trajectory_minus_best_non"] for task in TASK_ORDER]
        ax.bar(x + (j - 2) * width, vals, width=width, color=MODEL_COLORS[model], label=model)
    ax.axhline(0, color="#666666", lw=1, ls="--")
    ax.set_xticks(x, [t.replace(", ", "\n") for t in TASK_ORDER])
    ax.set_ylabel("Trajectory minus best non-trajectory accuracy")
    ax.yaxis.set_major_formatter(PercentFormatter(1.0))
    ax.grid(axis="y")
    ax.set_axisbelow(True)
    fig.suptitle("Trajectory contrast on common respondent-wave support", x=0.065, y=0.975, ha="left", fontsize=17)
    fig.text(
        0.065,
        0.925,
        "Each comparison uses identical records within a model configuration and task.",
        fontsize=11,
    )
    ax.legend(title="Model configuration", bbox_to_anchor=(1.01, 0.5), loc="center left", frameon=False)
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.89))
    save_figure(
        fig,
        "Figure_2_trajectory_advantage_vs_best_nontrajectory.png",
        "main_text/Figure_2_trajectory_advantage_vs_best_nontrajectory.png",
    )


def figure_stable_changing() -> None:
    df = pd.read_csv(EVAL / "tables" / "stable_changing_split_table.csv")
    df["model_publication"] = df["Model"].map(short_model)
    df["task_publication"] = df["Task"].map(task_label)
    panels = [
        ("Acc. stable", "A. Exact-match accuracy\namong stable transitions"),
        ("Acc. changed", "B. Exact-match accuracy\namong changing transitions"),
        ("False persistence among changers", "C. False persistence\namong changing transitions"),
    ]
    fig, axes = plt.subplots(1, 3, figsize=(16, 7), sharey=True)
    offsets = np.linspace(-0.22, 0.22, len(MODEL_ORDER))
    for ax, (column, title) in zip(axes, panels):
        for offset, model in zip(offsets, MODEL_ORDER):
            sub = df[df["model_publication"] == model].set_index("task_publication")
            vals = [sub.loc[task, column] for task in TASK_ORDER]
            ax.scatter(
                np.arange(4) + offset,
                vals,
                s=70,
                color=MODEL_COLORS[model],
                edgecolor="white",
                linewidth=0.7,
                label=model,
            )
        ax.set_xticks(np.arange(4), [t.replace(", ", "\n") for t in TASK_ORDER], rotation=0)
        ax.set_title(title, fontweight="bold")
        percent_axis(ax)
    axes[0].set_ylabel("Conditional proportion")
    fig.suptitle("Trajectory accuracy by observed transition status", x=0.055, ha="left", fontsize=18)
    handles = [Line2D([0], [0], marker="o", color="none", markerfacecolor=MODEL_COLORS[m], label=m, markersize=8) for m in MODEL_ORDER]
    fig.legend(handles=handles, title="Model configuration", loc="lower center", ncol=5, frameon=False)
    fig.tight_layout(rect=(0.02, 0.10, 1, 0.91))
    save_figure(fig, "Figure_3_stable_changing_split.png", "main_text/Figure_3_stable_changing_split.png")


def parse_heatmap_files(directory: Path) -> dict[tuple[int, str], pd.DataFrame]:
    pattern = re.compile(r"trajectory_delta_grid_ww(\d+)_(.+)\.csv$")
    result: dict[tuple[int, str], pd.DataFrame] = {}
    for path in directory.glob("trajectory_delta_grid_ww*.csv"):
        match = pattern.match(path.name)
        if not match:
            continue
        wave = int(match.group(1))
        model = short_model(match.group(2))
        frame = pd.read_csv(path)
        if "row_percent" not in frame:
            frame["row_percent"] = frame["count"] / frame.groupby("delta_H")["count"].transform("sum")
        result[(wave, model)] = frame
    return result


def heat_matrix(frame: pd.DataFrame, yvals: list[int], xvals: list[int]) -> np.ndarray:
    matrix = np.zeros((len(yvals), len(xvals)), dtype=float)
    yi = {v: i for i, v in enumerate(yvals)}
    xi = {v: i for i, v in enumerate(xvals)}
    for row in frame.itertuples(index=False):
        y = int(row.delta_H)
        x = int(row.delta_L)
        if y in yi and x in xi:
            matrix[yi[y], xi[x]] = float(row.row_percent)
    return matrix


GREEN_CMAP = LinearSegmentedColormap.from_list("publication_green", ["#F7FBF6", "#B8DCB3", "#238B45"])


def figure_main_anchor_heatmap() -> None:
    directory = EVAL / "analysis_1500" / "trajectory_heatmap" / "anchored_change"
    files = parse_heatmap_files(directory)
    pooled: dict[str, pd.DataFrame] = {}
    for model in MODEL_ORDER:
        parts = [frame for (wave, model_name), frame in files.items() if model_name == model]
        combined = pd.concat(parts, ignore_index=True).groupby(["delta_H", "delta_L"], as_index=False)["count"].sum()
        combined["row_percent"] = combined["count"] / combined.groupby("delta_H")["count"].transform("sum")
        pooled[model] = combined
    values = sorted(set().union(*(set(df["delta_H"].astype(int)) | set(df["delta_L"].astype(int)) for df in pooled.values())))
    fig, axes = plt.subplots(1, 5, figsize=(16, 5.3), sharex=True, sharey=True)
    for ax, model in zip(axes, MODEL_ORDER):
        matrix = heat_matrix(pooled[model], values, values)
        im = ax.imshow(matrix, origin="lower", cmap=GREEN_CMAP, vmin=0, vmax=1, aspect="auto")
        ax.set_title(model, fontweight="bold")
        step = max(1, len(values) // 6)
        ticks = np.arange(0, len(values), step)
        ax.set_xticks(ticks, [values[i] for i in ticks])
        ax.set_yticks(ticks, [values[i] for i in ticks])
        zero = values.index(0)
        ax.axvline(zero, color="#00796B", lw=1.2, ls="--")
        for iy, ix in np.argwhere(matrix >= 0.05):
            ax.text(ix, iy, f"{matrix[iy, ix]:.0%}", ha="center", va="center", fontsize=8)
    axes[0].set_ylabel("Observed response change")
    fig.supxlabel("Predicted change from the designated preceding response")
    fig.suptitle(f"Anchored-change distributions: left{EN}right, grouped", x=0.06, ha="left", fontsize=17)
    # Reserve a fixed right margin and place the colour bar in its own axis.
    # This prevents the final panel, tick labels, and colour-bar title from
    # competing for space when the figure is scaled in LaTeX.
    fig.subplots_adjust(left=0.06, right=0.89, bottom=0.14, top=0.82, wspace=0.16)
    cbar_ax = fig.add_axes([0.915, 0.17, 0.012, 0.62])
    cbar = fig.colorbar(im, cax=cbar_ax)
    cbar.ax.yaxis.set_major_formatter(PercentFormatter(1.0))
    cbar.ax.tick_params(pad=3)
    cbar.set_label("Row percentage", labelpad=8)
    save_figure(
        fig,
        "Figure_4_persistence_heatmap_left_right_grouped.png",
        "main_text/Figure_4_persistence_heatmap_left_right_grouped.png",
    )


def model_scale_data() -> pd.DataFrame:
    """Build configuration diagnostics from current results, without cached plot inputs."""
    if os.environ.get("THESIS_AGGREGATE_REPLAY") == "1":
        data = pd.read_csv(EVAL / "tables/model_scale_plot_data.csv")
        if len(data) != 20 or data.duplicated(["task", "Model"]).any():
            raise ValueError("Expected 20 aggregate task/configuration results")
        return data.sort_values(["model_order", "task"]).reset_index(drop=True)
    tables = EVAL / "manuscript" / "tables"
    rq1 = pd.read_csv(tables / "rq1_ordinal_covariates_only_comparison.csv")
    rq2 = pd.read_csv(tables / "rq2_ordinal_prior_state_comparison.csv")
    meta = {
        "Mistral-7B": ("Mistral", 7, 1),
        "Qwen2.5-7B (4-bit)": ("Qwen", 7, 2),
        "Qwen2.5-32B": ("Qwen", 32, 3),
        "Llama-3.3-70B": ("Llama", 70, 4),
        "Qwen2.5-72B": ("Qwen", 72, 5),
    }
    records = []
    for task, directory in TASK_DIRS.items():
        rows = pd.read_csv(
            EVAL / directory / "statistical_baselines" / "trajectory_baseline_row_comparison.csv",
            usecols=["model", "prompt_variant", "label_cat", "predict_cat", "vorwelle_label_cat"],
            dtype=str,
        )
        rows = rows.loc[rows["prompt_variant"].eq("trajectory")]
        for model, group in rows.groupby("model"):
            static = rq1.loc[rq1["Task"].eq(task) & rq1["model"].eq(model)]
            prior = rq2.loc[rq2["Task"].eq(task) & rq2["model"].eq(model)]
            if len(static) != 1 or len(prior) != 1:
                raise ValueError(f"Expected one current comparison for {task}, {model}")
            a, b = static.iloc[0], prior.iloc[0]
            if group[["label_cat", "vorwelle_label_cat"]].isna().any().any():
                raise ValueError(f"Missing observed transition for {task}, {model}")
            stable = group["label_cat"].eq(group["vorwelle_label_cat"])
            correct = group["predict_cat"].eq(group["label_cat"])
            parsed_changing = ~stable & group["predict_cat"].notna()
            repeated = group["predict_cat"].eq(group["vorwelle_label_cat"])
            name = short_model(model)
            family, size, order = meta[name]
            records.append({
                "task": task, "Model": name.replace(" (4-bit)", ""),
                "prompt": "No-time baseline",
                "nontrajectory_accuracy": a["accuracy_prompt"],
                "covariates_only_accuracy": a["accuracy_ordinal"],
                "trajectory_accuracy": b["accuracy_trajectory"],
                "carry_forward_accuracy": b["accuracy_cf"],
                "trajectory_minus_carry_forward": b["accuracy_trajectory"] - b["accuracy_cf"],
                "stable_share": stable.mean(),
                "stable_accuracy": correct.loc[stable].mean(),
                "changed_accuracy": correct.loc[~stable].mean(),
                "false_persistence": repeated.loc[parsed_changing].mean(),
                "family": family, "size_b": size, "model_order": order,
                "model_label": f"{family}\n{size}B",
            })
    df = pd.DataFrame(records)
    if len(df) != 20 or df.duplicated(["task", "Model"]).any():
        raise ValueError("Expected 20 unique task/configuration results")
    return df.sort_values(["model_order", "task"]).reset_index(drop=True)


def figure_model_scale() -> None:
    df = model_scale_data()
    path = CURATED / "appendix" / "G_model_scale_robustness" / "G1_model_scale_robustness_by_task.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False)
    df["task_publication"] = df["task"].map(task_label)
    df["model_publication"] = df["Model"].map(short_model)
    metrics = [
        ("nontrajectory_accuracy", "A. No-time\naccuracy", (0, 0.70)),
        ("trajectory_minus_carry_forward", "B. Trajectory minus\ncarry-forward", (-0.26, 0.03)),
        ("changed_accuracy", "C. Accuracy among\nchanging transitions", (0, 0.18)),
        ("false_persistence", "D. False persistence among\nchanging transitions", (0, 1.0)),
    ]
    fig, axes = plt.subplots(4, 4, figsize=(16, 11), sharex="col")
    family_colors = {"Mistral": "#4C78A8", "Qwen": "#54A24B", "Llama": "#E45756"}
    for col, task in enumerate(TASK_ORDER):
        sub = df[df["task_publication"] == task].copy().sort_values("model_order")
        for row, (metric, row_label, ylim) in enumerate(metrics):
            ax = axes[row, col]
            colors = [family_colors[f] for f in sub["family"]]
            ax.scatter(np.arange(len(sub)), sub[metric], s=62, c=colors, edgecolor="white", linewidth=0.6)
            ax.set_ylim(*ylim)
            ax.yaxis.set_major_formatter(PercentFormatter(1.0))
            ax.grid(axis="y")
            ax.set_axisbelow(True)
            if row == 0:
                ax.set_title(task, fontweight="bold")
                ax.axhline(float(sub["covariates_only_accuracy"].iloc[0]), color="#444444", ls="--", lw=1)
            if row == 1:
                ax.axhline(0, color="#444444", ls="--", lw=1)
            if col == 0:
                ax.set_ylabel(row_label, fontsize=10, labelpad=5)
            if row == 3:
                ax.set_xticks(np.arange(len(sub)), [m.replace(" (4-bit)", "\n4-bit").replace("-", "\n", 1) for m in sub["model_publication"]], fontsize=8)
            else:
                ax.set_xticks([])
    fig.suptitle("Descriptive patterns across model configurations", x=0.06, ha="left", fontsize=18)
    handles = [Line2D([0], [0], marker="o", color="none", markerfacecolor=c, label=f, markersize=8) for f, c in family_colors.items()]
    fig.legend(handles=handles, title="Model family", loc="lower center", ncol=3, frameon=False)
    fig.text(0.5, 0.055, "Model configuration (ordered by nominal parameter count)", ha="center")
    fig.tight_layout(rect=(0.06, 0.09, 1, 0.93), h_pad=1.3, w_pad=1.1)
    save_figure(fig, "Figure_5_model_scale_robustness.png", "main_text/Figure_5_model_scale_robustness.png")


def appendix_common_sample() -> None:
    df = pd.read_csv(latest_common_run() / "common_sample_accuracy_overall.csv")
    df["task_publication"] = [task_label(v, r) for v, r in zip(df["variant"], df["representation"])]
    df["model_publication"] = df["model"].map(short_model)
    df["prompt_publication"] = df["prompt_variant"].map(PROMPT_LABELS)
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), sharey=True)
    for ax, task in zip(axes.flat, TASK_ORDER):
        sub = df[df["task_publication"] == task]
        for model in MODEL_ORDER:
            line = sub[sub["model_publication"] == model].set_index("prompt_publication").reindex(PROMPT_ORDER)
            ax.plot(PROMPT_ORDER, line["accuracy"], marker="o", lw=1.6, color=MODEL_COLORS[model], label=model)
        ax.set_title(task, fontweight="bold")
        percent_axis(ax)
        ax.tick_params(axis="x", rotation=18)
    axes[0, 0].set_ylabel("Exact-match current-state accuracy")
    axes[1, 0].set_ylabel("Exact-match current-state accuracy")
    handles = [Line2D([0], [0], marker="o", color=MODEL_COLORS[m], label=m) for m in MODEL_ORDER]
    fig.legend(handles=handles, title="Model configuration", loc="lower center", ncol=5, frameon=False)
    fig.suptitle("Common-sample accuracy across information conditions", x=0.055, ha="left", fontsize=18)
    fig.tight_layout(rect=(0.02, 0.10, 1, 0.93))
    save_figure(
        fig,
        "appendix/A1_common_sample_accuracy_overall.png",
        "appendix/A_common_sample/A1_common_sample_accuracy_overall.png",
    )


def baseline_frames() -> tuple[pd.DataFrame, pd.DataFrame]:
    publication_tables = EVAL / "manuscript" / "tables"
    # The RQ1 publication table is intentionally restricted to the primary
    # no-time comparison. Appendix B1--B4 display all non-trajectory prompt
    # conditions, so they read the full ordinal source table instead.
    cov = pd.read_csv(
        EVAL / "tables" / "ordinal_covariates_only_statistical_baseline_comparison.csv"
    ).rename(
        columns={
            "prompt_label": "Prompt",
            "accuracy_majority": "PreviousWaveModal",
            "accuracy_ordinal": "CovariatesOnly",
            "accuracy_prompt": "LLMPrompt",
        }
    )
    stat = pd.read_csv(
        publication_tables / "rq2_ordinal_prior_state_comparison.csv"
    ).rename(
        columns={
            "accuracy_majority": "PreviousWaveModal",
            "accuracy_cf": "CarryForward",
            "accuracy_ordinal": "Statistical",
            "accuracy_trajectory": "Trajectory",
        }
    )
    for frame in (cov, stat):
        frame["task_publication"] = frame["Task"].map(task_label)
        frame["model_publication"] = frame["Model"].map(short_model)
    cov["prompt_publication"] = cov["Prompt"].map(PROMPT_LABELS)
    return cov, stat


def appendix_current_state_baselines() -> None:
    cov, stat = baseline_frames()
    file_names = [
        "B1_climate_growth_grouped_all_prompts_vs_covariates_only.png",
        "B2_climate_growth_original_all_prompts_vs_covariates_only.png",
        "B3_left_right_grouped_all_prompts_vs_covariates_only.png",
        "B4_left_right_original_all_prompts_vs_covariates_only.png",
    ]
    for task, file_name in zip(TASK_ORDER, file_names):
        fig, axes = plt.subplots(1, 3, figsize=(16, 7), sharex=True, sharey=True)
        task_cov = cov[cov["task_publication"] == task]
        task_stat = stat[stat["task_publication"] == task].set_index("model_publication")
        metrics = [
            ("Modal, designated preceding wave", "PreviousWaveModal"),
            ("Covariates-only ordinal probit", "CovariatesOnly"),
            ("Trajectory accuracy", "Trajectory"),
            ("Information-condition accuracy", "LLMPrompt"),
        ]
        for ax, prompt in zip(axes, PROMPT_ORDER[:3]):
            sub = task_cov[task_cov["prompt_publication"] == prompt].set_index("model_publication")
            y = np.arange(len(MODEL_ORDER))
            height = 0.18
            for j, (label, column) in enumerate(metrics):
                vals = task_stat.loc[MODEL_ORDER, column].to_numpy() if column == "Trajectory" else sub.loc[MODEL_ORDER, column].to_numpy()
                ax.barh(y + (j - 1.5) * height, vals, height=height, color=METRIC_COLORS[label], label=label)
            ax.set_title(prompt, fontweight="bold")
            ax.set_xlim(0, 1)
            ax.xaxis.set_major_formatter(PercentFormatter(1.0))
            ax.grid(axis="x")
            ax.set_axisbelow(True)
            ax.set_yticks(y, MODEL_ORDER)
            ax.invert_yaxis()
        handles, labels = axes[0].get_legend_handles_labels()
        fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(0.5, 0.012), ncol=4, frameon=False)
        fig.suptitle(f"Current-state comparisons for {task}", x=0.04, ha="left", fontsize=17)
        fig.supxlabel("Exact-match current-state accuracy", y=0.085)
        fig.tight_layout(rect=(0.02, 0.14, 1, 0.92))
        save_figure(fig, f"appendix/{file_name}", f"appendix/B_matched_baselines/{file_name}")


def appendix_prior_state_baselines() -> None:
    _, stat = baseline_frames()
    file_names = [
        "B5_climate_growth_grouped_trajectory_vs_nonllm_baselines.png",
        "B6_climate_growth_original_trajectory_vs_nonllm_baselines.png",
        "B7_left_right_grouped_trajectory_vs_nonllm_baselines.png",
        "B8_left_right_original_trajectory_vs_nonllm_baselines.png",
    ]
    metrics = [
        ("Trajectory accuracy", "Trajectory"),
        ("Carry-forward accuracy", "CarryForward"),
        ("Modal, designated preceding wave", "PreviousWaveModal"),
        ("Lag-and-covariates ordinal probit", "Statistical"),
    ]
    for task, file_name in zip(TASK_ORDER, file_names):
        sub = stat[stat["task_publication"] == task].set_index("model_publication")
        fig, ax = plt.subplots(figsize=(12, 7))
        y = np.arange(len(MODEL_ORDER))
        height = 0.18
        for j, (label, column) in enumerate(metrics):
            ax.barh(y + (j - 1.5) * height, sub.loc[MODEL_ORDER, column], height=height, color=METRIC_COLORS[label], label=label)
        ax.set_yticks(y, MODEL_ORDER)
        ax.invert_yaxis()
        ax.set_xlim(0, 1)
        ax.xaxis.set_major_formatter(PercentFormatter(1.0))
        ax.grid(axis="x")
        ax.set_axisbelow(True)
        ax.set_xlabel("Exact-match current-state accuracy")
        ax.set_title(f"Matched prior-state comparisons for {task}", loc="left", fontsize=17)
        ax.legend(loc="lower center", bbox_to_anchor=(0.5, -0.20), ncol=2, frameon=False)
        fig.tight_layout()
        save_figure(fig, f"appendix/{file_name}", f"appendix/B_matched_baselines/{file_name}")


def appendix_aggregate_distance() -> None:
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), sharey=True)
    for ax, (task_raw, directory) in zip(axes.flat, TASK_DIRS.items()):
        df = pd.read_csv(EVAL / directory / "aggregate_prediction" / "aggregate_distribution_distance_overall.csv")
        df["model_publication"] = df["model"].map(short_model)
        df["prompt_publication"] = df["prompt_variant"].map(PROMPT_LABELS)
        for model in MODEL_ORDER:
            sub = df[df["model_publication"] == model].set_index("prompt_publication").reindex(PROMPT_ORDER)
            ax.plot(PROMPT_ORDER, sub["total_variation_distance"], marker="o", color=MODEL_COLORS[model], lw=1.5)
        ax.set_title(task_label(task_raw), fontweight="bold")
        percent_axis(ax)
        ax.tick_params(axis="x", rotation=18)
    axes[0, 0].set_ylabel("Total variation distance")
    axes[1, 0].set_ylabel("Total variation distance")
    handles = [Line2D([0], [0], marker="o", color=MODEL_COLORS[m], label=m) for m in MODEL_ORDER]
    fig.legend(handles=handles, title="Model configuration", loc="lower center", ncol=5, frameon=False)
    fig.suptitle("Aggregate distributional alignment by information condition", x=0.055, ha="left", fontsize=18)
    fig.tight_layout(rect=(0.02, 0.10, 1, 0.93))
    save_figure(
        fig,
        "appendix/C0_aggregate_distribution_distance_overall.png",
        "appendix/C_aggregate_by_wave/C0_aggregate_distribution_distance_overall.png",
    )


def appendix_heatmap(task_raw: str, directory_name: str, mode: str, file_name: str) -> None:
    directory = EVAL / directory_name / "trajectory_heatmap" / mode
    files = parse_heatmap_files(directory)
    waves = sorted({wave for wave, _ in files})
    all_frames = list(files.values())
    values = sorted(set().union(*(set(df["delta_H"].astype(int)) | set(df["delta_L"].astype(int)) for df in all_frames)))
    nrows = len(waves)
    fig, axes = plt.subplots(nrows, len(MODEL_ORDER), figsize=(17, max(9, 2.2 * nrows)), sharex=True, sharey=True)
    axes = np.atleast_2d(axes)
    for r, wave in enumerate(waves):
        for c, model in enumerate(MODEL_ORDER):
            ax = axes[r, c]
            frame = files[(wave, model)]
            matrix = heat_matrix(frame, values, values)
            im = ax.imshow(matrix, origin="lower", cmap=GREEN_CMAP, vmin=0, vmax=1, aspect="auto")
            if r == 0:
                ax.set_title(model, fontweight="bold", fontsize=10)
            if c == 0:
                ax.set_ylabel(f"Wave {wave}\nObserved change")
            step = max(1, len(values) // 6)
            ticks = np.arange(0, len(values), step)
            ax.set_xticks(ticks, [values[i] for i in ticks], fontsize=7)
            ax.set_yticks(ticks, [values[i] for i in ticks], fontsize=7)
    task = task_label(task_raw)
    if mode == "anchored_change":
        title = f"Anchored-change heatmaps: {task}"
        xlabel = "Predicted change from the designated preceding response"
    else:
        title = f"Consecutive one-step prediction heatmaps: {task}"
        xlabel = "Change between consecutive one-step predictions"
    fig.suptitle(title, x=0.055, ha="left", fontsize=17)
    fig.supxlabel(xlabel)
    fig.subplots_adjust(left=0.07, right=0.90, bottom=0.06, top=0.93, wspace=0.10, hspace=0.18)
    # Reserve an independent colorbar axis outside all five model columns.
    cax = fig.add_axes([0.925, 0.38, 0.012, 0.24])
    cbar = fig.colorbar(im, cax=cax)
    cbar.ax.yaxis.set_major_formatter(PercentFormatter(1.0))
    cbar.set_label("Row percentage")
    save_figure(fig, f"appendix/{file_name}", f"appendix/D_dynamic_persistence/{file_name}")


def subgroup_label(row: pd.Series) -> str:
    sex = {"weiblich": "Female", "maennlich": "Male"}.get(str(row["sex"]), str(row["sex"]).replace("_", " ").title())
    income = {
        "low_income": "low income",
        "middle_income": "middle income",
        "high_income": "high income",
    }.get(str(row["income_band"]), str(row["income_band"]).replace("_", " "))
    education = {
        "before_university_track": "lower/medium education",
        "university_track_or_higher": "higher education",
    }.get(str(row["education_band"]), str(row["education_band"]).replace("_", " "))
    return f"{sex}, {income}, {education}"


def appendix_subgroup(task_raw: str, directory_name: str, file_name: str) -> None:
    df = pd.read_csv(EVAL / directory_name / "subgroup_analysis" / "subgroup_correctness_overall.csv")
    df["model_publication"] = df["model"].map(short_model)
    df["prompt_publication"] = df["prompt_variant"].map(PROMPT_LABELS)
    df["subgroup_publication"] = df.apply(subgroup_label, axis=1)
    order = (
        df.groupby("subgroup_publication", as_index=False)["accuracy"]
        .mean()
        .sort_values("accuracy", ascending=False)["subgroup_publication"]
        .tolist()
    )
    fig, axes = plt.subplots(2, 2, figsize=(15, 10), sharex=True, sharey=True)
    for ax, prompt in zip(axes.flat, PROMPT_ORDER):
        sub = df[df["prompt_publication"] == prompt]
        for model in MODEL_ORDER:
            model_df = sub[sub["model_publication"] == model].set_index("subgroup_publication").reindex(order)
            y = np.arange(len(order))
            valid = model_df["accuracy"].notna().to_numpy()
            ax.scatter(
                model_df.loc[valid, "accuracy"],
                y[valid],
                color=MODEL_COLORS[model],
                s=28,
                alpha=0.9,
                zorder=3,
            )
        ax.set_title(prompt, fontweight="bold")
        ax.set_xlim(0, 1)
        ax.xaxis.set_major_formatter(PercentFormatter(1.0))
        ax.grid(axis="x")
        ax.set_axisbelow(True)
        ax.set_yticks(np.arange(len(order)), order, fontsize=8)
        ax.invert_yaxis()
    task = task_label(task_raw)
    fig.suptitle(f"Exact-match accuracy across demographic intersections: {task}", x=0.035, ha="left", fontsize=17)
    fig.supxlabel("Exact-match current-state accuracy", y=0.080)
    handles = [Line2D([0], [0], marker="o", color=MODEL_COLORS[m], label=m) for m in MODEL_ORDER]
    fig.legend(handles=handles, title="Model configuration", loc="lower center", bbox_to_anchor=(0.5, 0.005), ncol=5, frameon=False)
    fig.tight_layout(rect=(0.02, 0.14, 1, 0.93))
    save_figure(fig, f"appendix/{file_name}", f"appendix/F_subgroups/{file_name}")


def main() -> None:
    setup_style()
    figure_information_ladder()
    figure_trajectory_contrast()
    figure_stable_changing()
    figure_main_anchor_heatmap()
    figure_model_scale()
    appendix_common_sample()
    appendix_current_state_baselines()
    appendix_prior_state_baselines()
    appendix_aggregate_distance()

    heatmaps = [
        ("Climate-growth grouped", "analysis_1290", "anchored_change", "D05_climate_growth_grouped_anchored_change_heatmap.png"),
        ("Climate-growth original scale", "analysis_1290_original_scale", "anchored_change", "D06_climate_growth_original_anchored_change_heatmap.png"),
        ("Left-right grouped", "analysis_1500", "anchored_change", "D07_left_right_grouped_anchored_change_heatmap.png"),
        ("Left-right original scale", "analysis_1500_original_scale", "anchored_change", "D08_left_right_original_anchored_change_heatmap.png"),
        ("Climate-growth grouped", "analysis_1290", "self_trajectory", "D09_climate_growth_grouped_self_trajectory_heatmap.png"),
        ("Climate-growth original scale", "analysis_1290_original_scale", "self_trajectory", "D10_climate_growth_original_self_trajectory_heatmap.png"),
        ("Left-right grouped", "analysis_1500", "self_trajectory", "D11_left_right_grouped_self_trajectory_heatmap.png"),
        ("Left-right original scale", "analysis_1500_original_scale", "self_trajectory", "D12_left_right_original_self_trajectory_heatmap.png"),
    ]
    for args in heatmaps:
        appendix_heatmap(*args)

    subgroups = [
        ("Climate-growth grouped", "analysis_1290", "F1_climate_growth_grouped_subgroup_correctness.png"),
        ("Climate-growth original scale", "analysis_1290_original_scale", "F2_climate_growth_original_subgroup_correctness.png"),
        ("Left-right grouped", "analysis_1500", "F3_left_right_grouped_subgroup_correctness.png"),
        ("Left-right original scale", "analysis_1500_original_scale", "F4_left_right_original_subgroup_correctness.png"),
    ]
    for args in subgroups:
        appendix_subgroup(*args)


if __name__ == "__main__":
    main()

"""Re-export the published aggregates as thesis tables and figures.

This does not fit models or rescore respondent records. It needs only the public
repository and its Python requirements, with no GLES inputs or LLM checkpoints.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
RESULTS = REPO / "results"


def verify_snapshot():
    manifest = json.loads((RESULTS / "manifest.json").read_text(encoding="utf-8"))
    for row in manifest["exporter_sources"]:
        path = (REPO / row["path"]).resolve()
        if REPO not in path.parents or hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError(f"Exporter differs from the verified snapshot: {row['path']}")
    for row in manifest["files"]:
        relative = PurePosixPath(row["path"])
        path = RESULTS.joinpath(*relative.parts).resolve()
        if relative.is_absolute() or ".." in relative.parts or RESULTS not in path.parents:
            raise ValueError("Invalid snapshot path")
        if hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError(f"Published file changed: {row['path']}")
    print(f"Verified {len(manifest['files'])} published files", flush=True)
    return manifest


def replay(output):
    manifest = verify_snapshot()
    if output.exists() and any(output.iterdir()):
        raise ValueError("Choose an empty --output-dir; existing results are preserved")
    output.mkdir(parents=True, exist_ok=True)
    inputs = RESULTS / "recomputed/aggregate_inputs"
    shutil.copytree(inputs, output, dirs_exist_ok=True)
    environment = dict(os.environ, THESIS_EVALUATION_ROOT=str(output), THESIS_AGGREGATE_REPLAY="1")
    scripts = REPO / "code/03_evaluation/scripts"
    commands = [
        ["build_thesis_result_tables.py", "--from-aggregates"],
        ["generate_manuscript_result_rows.py"],
        ["generate_publication_figures.py"],
        ["generate_readable_thesis_figures.py"],
        ["generate_readable_appendix_figures.py"],
        ["generate_subgroup_figures.py"],
        ["generate_framework_figure.py"],
    ]
    for script, *arguments in commands:
        print(f"Exporting {script}", flush=True)
        subprocess.run([sys.executable, str(scripts / script), *arguments],
                       cwd=REPO, env=environment, check=True)
    # The preparation-stage retention table is also available as aggregate CSV.
    import pandas as pd
    retention = pd.read_csv(output / "manuscript/tables/parsing_retention_summary.csv")
    if len(retention) != 16:
        raise ValueError("Expected 16 task/prompt retention summaries")
    rows = [f"{r.Task} & {r.Prompt} & {r.evaluation_n:,} & {r.parsed_n:,} & "
            f"{r.parsed_share:.5f} & {r.exact_match_accuracy:.3f} \\\\" for r in retention.itertuples()]
    (output / "publication/latex/parsing_retention_summary_rows.tex").write_text(
        "\n".join(rows + [r"\hline"]) + "\n", encoding="utf-8")
    differences = []
    for name in manifest["required_tables"]:
        actual = (output / "publication/latex" / name).read_text(encoding="utf-8")
        expected = (RESULTS / "recomputed/latex" / name).read_text(encoding="utf-8")
        if actual.split() != expected.split():
            differences.append(name)
    missing = [name for name in manifest["required_figures"]
               if not (output / "publication/figures" / name).is_file()]
    report = dict(mode="aggregate_export_only", models_refitted=False,
        respondent_records_rescored=False, tables_verified=len(manifest["required_tables"]),
        required_figures=len(manifest["required_figures"]), table_differences=differences,
        missing_figures=missing, status="passed" if not differences and not missing else "failed")
    (output / "aggregate_replay_audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if differences or missing:
        raise ValueError(f"Aggregate export check failed: {report}")
    print(json.dumps(report, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=REPO / "code/outputs/published_replay")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    if args.check_only:
        verify_snapshot()
    else:
        replay(args.output_dir.resolve())

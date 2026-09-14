# Thesis build and analysis definitions

Run analysis commands from `code/`. The full entry point is `run_03_full_evaluation.R`.

| Stage | Implementation | Main output |
| --- | --- | --- |
| Prompt generation, run separately before inference | `01_prompt_generation/scripts/build_*_prompts.R` | 116 JSON manifests, four wave-list RDS files, column metadata |
| Complete inference archive audit | `audit_generation_inputs.py` | Coverage, reference linkage, SHA-256 manifest; extra files reported |
| Join and clean | `run_02a_build_and_clean_analysis_inputs.R` | Four analysis CSVs; grouped retention counts |
| Check designated human/model lags | `audit_analysis_input_lag_linkage.R` | Linkage audit |
| Inspect original-scale token parsing | `audit_original_scale_parsing.py` | Signed/decimal sensitivity counts; reject Unicode serialization artifacts |
| Accuracy, aggregate distribution, subgroups, temporal diagnostics, multinomial baselines | `analyse_all_variants.R` | Per-task outputs under `analysis_<variant>/` |
| Multinomial convergence and iteration sensitivity | `summarise_statistical_baseline_diagnostics.R` | Convergence and iteration tables |
| Ordinal-probit primary baselines | `generate_ordinal_statistical_baselines.R` | Expanding-window predictions and matched comparisons |
| Ordinal diagnostics | `summarise_ordinal_statistical_baselines.R` | Fit, threshold, probability and parallel-slopes summaries |
| Main comparisons | `build_manuscript_publication_tables.R` | RQ1/RQ2 ordinal comparison tables |
| Temporal summaries | `summarize_dynamic_validity_results.R` | Stable/changed, capture, and anchored-change summaries |
| Structural fidelity | `generate_structural_fidelity_summary.R` | Paired OLS and ordinal fits on identical complete cases |
| Common sample and parsing | `common_sample_accuracy.R`, `generate_parsing_retention_summary.R` | Prompt intersections and parsing table |
| Exact thesis tables | `build_thesis_result_tables.py`, `generate_manuscript_result_rows.py` | Row-level matched distances/specifications and LaTeX fragments |
| Main and appendix graphics | `generate_*figures.py`, `generate_framework_figure.py` | Figures under `publication/figures/` |
| Result verification | `audit_thesis_results.py` | Identities, convergence, pooled TVD, table comparison and artifact coverage |

Evaluation scripts in the table reside in `03_evaluation/scripts/`. R figure
scripts also export supplementary figures earlier in the full build. Standalone
entry points for a subset of metrics remain useful for debugging; only the full
runner builds all thesis artifacts. Analysis errors propagate to a nonzero exit
instead of silently continuing to reuse older output files.

## Samples and estimands

| Analysis | Denominator |
| --- | --- |
| Grouped exact accuracy | Retained predictions after Jaro–Winkler matching (threshold 0.85; tokens at least four characters) |
| Original-scale exact accuracy | All eligible evaluation rows; an unparsed prediction is incorrect |
| RQ1 ordinal comparison | No-time rows with available covariates-only ordinal predictions |
| RQ2 prompt-condition contrast | Within-model intersection across prompt conditions with designated human lag available |
| RQ2 prior-state baseline comparison | Trajectory rows with available lag-and-covariates ordinal predictions |
| MAE, RMSE, within-one | Same jointly parsed original-scale records for the LLM and compared ordinal baseline |
| RQ3 accuracy decomposition | All retained trajectory rows with designated human lag available; does not require an ordinal prediction |
| RQ3 numeric change/capture diagnostics | Rows with the required human and generated categories parsed |
| Ordinal/multinomial sensitivity | Jointly available predictions from both specifications, rescored from records without using rounded table cells |
| Structural fidelity | Shared complete cases for human and LLM, six covariates plus wave fixed effects; retain all non-wave coefficients |
| Pooled TVD | Pool category counts across waves before calculating one-half the sum of absolute proportion differences |
| Subgroup diagnostics | Sex, income, education; minimum cell size 30 |

The designated prior is the previous selected survey wave. A missing generation
does not change that wave; human prior and generated prior are distinct columns.
First selected waves do not have trajectory prompts. Later waves without
eligible earlier training data do not get retrospective statistical predictions.

Statistical baselines train on earlier waves only. The historical full-input
screen of candidate covariates (excluding variables with more than 20 values)
is retained because it is stated in the thesis; this is not a strictly
training-only feature-selection protocol. Missingness becomes a factor level;
unseen test levels map to the training modal level. The full build includes
original-scale multinomial iteration checks at 200, 500, 1000, and 2000 iterations.

Evaluation definitions set `LC_COLLATE=C` and treatment contrasts. This fixes
the ordering of categorical reference levels independently of the host language;
UTF-8 character handling is configured separately. Structural coefficient
correlation and sign agreement depend on these stated reference levels.

## Execution and recovery

The fresh full build audits all inputs, rebuilds cleaned CSVs, fits models, and
exports results. Python is selected through `MANUSCRIPT_PYTHON` or PATH. Existing
skip environment variables are cleared for the full build and restored on exit.
Primary entry points initialize a UTF-8 R locale. The JSONL reader and CSV writer
also declare UTF-8 explicitly; do not reuse historical CSVs containing `<U+....>`
serialization artifacts. Correct Unicode can change scores previously computed
from digits embedded in those artifacts.

- `--skip-input-rebuild`: reuse matching cleaned analysis CSVs and recompute analyses.
- `--resume-ordinal-models`: resume after per-task/multinomial analyses.
- `--resume-ordinal-tables`: reuse existing ordinal predictions and regenerate later tables/analyses.
- `--resume-publication-figures`: rebuild final Python tables/graphics from existing R outputs.

Choose only one resume stage. Resume modes require complete outputs from the
same input data and source version; they do not establish independent replication.
The in-place grouped cleaner should normally be invoked by the build-and-clean
runner, after raw joins have been regenerated, so retention counts describe the
attempted predictions rather than an already filtered input.

Run `python 03_evaluation/scripts/audit_thesis_results.py --compare-thesis` to
require exact agreement with the ten formatted reference table fragments. The
ordinary full-build audit reports differences without suppressing valid new
experiment results. The reference fixture contains aggregate table values and
figure filenames, not respondent records. Figure coverage checks existence;
figure exporters separately check their plotted values and text placement.

## Re-exporting the public aggregate snapshot

From the repository root, `python tools/reproduce_published_results.py` verifies
the hashes in `results/manifest.json`, copies its aggregate inputs into a fresh
output directory, and runs the maintained table and figure exporters. It checks
all ten formatted tables against the corrected snapshot and verifies coverage
of the 35 analytical figures. The exporters also check plotted values and bounds.
No respondent scoring, inference, or statistical fitting takes place in this mode.

The wrapper sets `THESIS_EVALUATION_ROOT` and `THESIS_AGGREGATE_REPLAY` only in
its child processes. Normal evaluation continues to calculate model-scale
diagnostics from respondent records. `build_thesis_result_tables.py
--from-aggregates` is an explicit export mode; the default still scores matched
records. See [REPRODUCING_RESULTS.md](REPRODUCING_RESULTS.md).

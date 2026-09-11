# Script map

## Main pipeline (working directory: code/)

| Purpose | Entry point or implementation |
| --- | --- |
| All four task representations | `run_01_generate_prompts.R` |
| GLES selection, harmonization, profile construction, four prompt conditions | `01_prompt_generation/scripts/build_*_prompts.R` |
| Read JSONL and join survey waves | `02_build_analysis_inputs/scripts/build_analysis_inputs_from_jsonl.R` |
| Normalize textual grouped predictions | `02_build_analysis_inputs/scripts/fuzzy_match_predictions.R` |
| Basic evaluation | `run_02b_evaluate_existing_analysis_inputs.R` |
| All-variant metrics and model fitting | `03_evaluation/scripts/analyse_all_variants.R` |
| Left-right dynamic chains | `03_evaluation/scripts/analyse_1500_dynamic_chains.R` |
| Primary ordinal-probit baselines | `03_evaluation/scripts/generate_ordinal_statistical_baselines.R` |
| Consolidate ordinal diagnostics | `03_evaluation/scripts/summarise_ordinal_statistical_baselines.R` |
| Publication comparison tables | `03_evaluation/scripts/build_manuscript_publication_tables.R` |
| Multinomial robustness baselines | `03_evaluation/scripts/generate_statistical_baselines_only.R` |
| Structural fidelity | `03_evaluation/scripts/generate_structural_fidelity_summary.R` |
| Prior-state benchmark | `03_evaluation/scripts/generate_prior_state_persistence_only.R` |
| Dynamic summaries | `03_evaluation/scripts/summarize_dynamic_validity_results.R` |
| Common-sample accuracy | `run_03_common_sample_accuracy.R` |
| Same-database robustness | `run_03_evaluate_same_database.R` |
| Full thesis result build | `run_03_full_evaluation.R` |

The full build preserves the stage order of the workspace's manuscript runner:
coverage audit; input preparation; lag-linkage audit; dynamic and all-variant
evaluation; ordinal baselines and publication tables; dynamic and structural
summaries; common-sample analysis; parsing retention; R figures; Python tables
and figures. Dedicated robustness entry points remain available separately.

Outputs are located under `code/outputs/evaluation/`, notably
`analysis_<variant>/`, `tables/`, `manuscript/tables/`, `figures/`,
`organized_analysis_pngs/`, and `publication/`. The `manuscript` directory
contains result tables, not the thesis source. Python figure exports use
`publication/figures/` and `publication/curated/`; LaTeX fragments use
`publication/latex/`.

The basic evaluation includes legacy diagnostic outputs. For thesis-facing
baseline comparisons, use the explicitly named **ordinal** publication tables.
`run_03_full_evaluation.R` checks the original design of four tasks and five
model configurations; a partial or different model experiment should use the
individual analysis runners and adapt its publication summaries explicitly.

The designated prior is the previous *selected survey wave*, not the previous
available model-output row. Missing generations therefore do not silently
change the lag used in evaluation. Preserve wave-list RDS files from the
same prompt-generation run as the JSONL files.

Some original task-level runners catch per-variant errors and issue warnings.
Always inspect warnings and expected output coverage; a successful process exit
alone is not proof that every task/module completed.

The grouped prediction cleaner removes rows whose predictions remain missing
after normalization. Original-scale inputs bypass that fuzzy-cleaning step.
Use the parsing-retention summaries and the documented denominators when
comparing results; the cleaned grouped CSVs are not the full set of attempted
generations.

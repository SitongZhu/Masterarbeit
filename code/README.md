# Main prompt and evaluation pipeline — V11

The final paper's numerical values and baseline names are listed in
[V11_RESULTS.md](../docs/V11_RESULTS.md). RQ1 uses **covariates-only ordinal probit**;
RQ2 uses the **preceding-wave modal rule**, **carry-forward**, and
**lag-and-covariates ordinal probit**. **Multinomial logit** is a supplementary
robustness specification. The internal `majority` columns mean the designated
preceding-wave modal rule, not a mode calculated on the target evaluation wave.
`analyse_all_variants.R` exports the auxiliary multinomial comparisons;
`run_03_full_evaluation.R` also builds the primary ordinal comparisons and final assets.
The fixed final-paper package is `results-v11-2026-09-15`.

Run all main `Rscript` commands from this directory. Begin with
`Rscript check_project_setup.R` and follow the [root README](../README.md).

- Prompt construction: `run_01_generate_prompts.R`.
- External LLM calls: [AlignSurvey](https://github.com/PiLab-ZJU/AlignSurvey),
  with the [documented file interface](../docs/INFERENCE.md).
- Output preparation: `run_02a_build_and_clean_analysis_inputs.R`.
- Evaluate cleaned inputs: `run_02b_evaluate_existing_analysis_inputs.R`.
- Prepare inputs and evaluate: `run_02_build_inputs_and_evaluate.R`.
- Full thesis evaluation, tables, and figures: `run_03_full_evaluation.R`.

Research inputs are supplied separately; see [data/README.md](data/README.md).
All generated results remain under `outputs/`. This source release does not
compile the thesis PDF or synchronize any Overleaf project.

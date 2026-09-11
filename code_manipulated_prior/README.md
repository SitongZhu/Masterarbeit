# Manipulated-prior robustness experiment

This additional experiment starts from the main pipeline's trajectory prompts.
LLM inference uses [AlignSurvey](https://github.com/PiLab-ZJU/AlignSurvey), as
in the main experiment; see [the interface](../docs/INFERENCE.md).

| Condition | Supplied prior |
| --- | --- |
| `correct_prior` | The respondent's recorded preceding response |
| `shuffled_prior` | Another respondent's preceding response within the same task and target wave |
| `incorrect_prior` | A different grouped category, or a randomly selected adjacent original-scale value |

Shuffling uses a derangement: donor and recipient identifiers always differ,
and the marginal prior distribution is preserved. Their answer values may
still coincide. Seeds and actual supplied priors are recorded in the manifest.

After generating the main prompts, run from `code_manipulated_prior/`:

```sh
Rscript run_01_generate_manipulated_prior_prompts.R
```

The default source is `../code/outputs/prompts`; override it with
`SOURCE_PROMPT_ROOT` if needed. Tasks are named `1290_grouped`,
`1290_original_scale`, `1500_grouped`, and `1500_original_scale`.
Run the resulting prompt JSON through AlignSurvey and save the results under
`data/llm_outputs/outcome/<task>/`:

```text
nosft_<model>__prompt_w14_trajectory_correct_prior.jsonl
nosft_<model>__prompt_w14_trajectory_shuffled_prior.jsonl
nosft_<model>__prompt_w14_trajectory_incorrect_prior.jsonl
```

Then run:

```sh
Rscript run_02_build_manipulated_prior_inputs.R
Rscript run_03_evaluate_manipulated_prior.R
Rscript analyze_manipulated_prior_results.R
```

`MANIPULATED_PRIOR_LLM_OUTPUT_ROOT` can override the external-output location.
Keep `data/prompt_manifests/manipulated_prior_manifest.csv` from the exact
prompt run: it is the evaluation's source of true and supplied priors.

Key outputs include `prior_condition_metrics_*.csv`,
`paired_prior_induced_change_*.csv`, and `accuracy_degradation_*.csv` under
`outputs/evaluation/`. Accuracy degradation is `accuracy_correct -
accuracy_manipulated` on paired respondents. The analysis also measures
supplied-prior agreement and conditional manipulated-prior following.

For data-independent validation, run `Rscript tests/smoke_manipulated_prior.R`
from the repository root. The older checks inside this subdirectory's `tests/`
expect already generated prompts/manifests and can be run locally afterward.

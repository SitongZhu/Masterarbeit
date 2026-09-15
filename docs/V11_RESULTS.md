# Final V11 numerical and baseline reference

Use the fixed [`results-v11-2026-09-15` release](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-v11-2026-09-15)
and its `results/recomputed/` assets. The [version record](submission/v11_20260915/README.md)
identifies the exact reviewed and release-linked PDFs. Values below are taken
from the public aggregate tables and checked by `tools/audit_v11_results.py`.
Historical releases, `results/submitted/`, and dated review reports retain their
original numbers and must not be treated as the final reference.

## Main results and denominators

| V11 result | Value | Comparison records / source |
| --- | --- | --- |
| Covariates-only ordinal probit exceeds no-time LLM accuracy | 20/20 | Matched RQ1 records; [ordinal comparison](../results/recomputed/aggregate_inputs/manuscript/tables/rq1_ordinal_covariates_only_comparison.csv) |
| Trajectory gain over strongest non-trajectory prompt | 11.9–52.6 percentage points; 20/20 positive | Common records across all four prompts; [common-sample gains](../results/recomputed/aggregate_inputs/common_sample_accuracy/runs/run_manuscript/trajectory_vs_best_nontrajectory_common_sample.csv) |
| Trajectory exceeds preceding-wave modal / lag-and-covariates ordinal probit | 20/20 / 8/20 | Matched RQ2 records; [prior-state comparison](../results/recomputed/aggregate_inputs/manuscript/tables/rq2_ordinal_prior_state_comparison.csv) |
| Trajectory versus carry-forward | 17 lower, 1 equal, 2 gains below 0.01 percentage points | Same matched RQ2 records; comparisons use unrounded values |
| Selected trajectory versus supplementary multinomial logit | Lower in 3/4 tasks | Same selected configurations and matched records; [specification comparison](../results/recomputed/aggregate_inputs/publication/tables/matched_specification_comparison.csv) |
| Highest exact-match accuracy on changing transitions | **16.3%** | All 20 task/configuration combinations; retained changing records, unresolved outputs count as errors |
| **Grouped** false persistence | **76.3%–100.0%** | Ten grouped task/configuration combinations; **parsed changing records** |
| False persistence across both grouped and original scales | 49.3%–100.0% | All 20 combinations; parsed changing records; this broader range must not be labeled “grouped” |
| Highest change capture / directional change capture | 50.7% / 36.5% | Parsed changing records; [exact transition diagnostics](../results/recomputed/aggregate_inputs/publication/tables/transition_diagnostics_exact.csv) |
| Figure 4, Qwen2.5-72B, observed change +2 | 58/126 = approximately 46% exact recovery | Grouped left-right parsed trajectory records; every heatmap row reports its own n |

The earlier **16.7%** maximum changed-transition accuracy belongs to the
pre-correction manuscript. It is retained only in explicitly historical material.
Percentages and percentage-point differences are distinct. Display rounding
can make slightly different accuracies appear equal, including the two tiny
carry-forward gains; the comparison counts above use unrounded aggregates.

## Figure 2 selected configurations and accuracy (%)

| Task | No-time configuration | No-time LLM | Covariates-only ordinal probit |
| --- | --- | ---: | ---: |
| Climate-growth grouped | Qwen2.5-72B | 45.6 | 53.6 |
| Climate-growth original | Qwen2.5-32B | 28.4 | 31.3 |
| Left-right grouped | Qwen2.5-7B, 4-bit | 58.6 | 63.2 |
| Left-right original | Qwen2.5-72B | 23.5 | 32.0 |

| Task | Trajectory configuration | Trajectory LLM | Carry-forward | Lag-and-covariates ordinal probit |
| --- | --- | ---: | ---: | ---: |
| Climate-growth grouped | Llama-3.3-70B | 68.4 | 68.4 | 66.2 |
| Climate-growth original | Qwen2.5-32B | 46.8 | 46.8 | 42.4 |
| Left-right grouped | Qwen2.5-7B, 4-bit | 84.1 | 84.1 | 83.6 |
| Left-right original | Qwen2.5-32B | 52.5 | 55.6 | 46.8 |

The two blocks can select different configurations and use different records.
Subtracting them does not give the common-sample prompt gain. Use Figures A.1/A.2
and the common-sample gain table for that comparison. Figure filenames retain
their historical exporter names; [the figure map](submission/v11_20260915/figure_mapping.json)
identifies their locations and checksums in the final manuscript.

## Statistical baseline terminology

| Name in the final paper | Role | Code / stored field |
| --- | --- | --- |
| Covariates-only ordinal probit | Primary RQ1 statistical comparator | `generate_ordinal_statistical_baselines.R`; RQ1 `accuracy_ordinal` |
| Preceding-wave modal rule | RQ2 reference; same category for all target respondents, based on the designated preceding wave | `accuracy_majority`, `PreviousWaveModal`; “majority” is an internal alias |
| Carry-forward | RQ2 individual persistence reference; repeats the observed preceding answer | `accuracy_cf` |
| Lag-and-covariates ordinal probit | Primary RQ2 statistical comparator | `generate_ordinal_statistical_baselines.R`; RQ2 `accuracy_ordinal` |
| Multinomial logit | Supplementary robustness specification, with covariates-only and lag-and-covariates variants | Auxiliary outputs of `analyse_all_variants.R`; matched specification tables |
| OLS and ordinal probit for structural fidelity | Supplementary human/LLM association diagnostics | `generate_structural_fidelity_summary.R`; separate from predictive accuracy baselines |

The full runner builds both primary ordinal and supplementary multinomial
results. Generic `statistical` names in auxiliary outputs do not change the
primary baseline. `Qwen2.5-7B` in compact legacy tables denotes the evaluated
four-bit configuration; Figure 2 and this reference spell that out.

## Verification and scope

`python tools/audit_v11_results.py` verifies the counts and ranges above,
transition identities, 20 pooled TVD comparisons, 240 subgroup comparisons,
and structural-correlation medians from public aggregates. With PyMuPDF
installed, `--pdf PATH` additionally matches all 112 numeric table rows.
TVD and subgroup comparisons use condition-specific records.

The training-window audit found unchanged effective predictors in all 48
estimable windows and agreement with all 96 archived fit diagnostics.
See [the eligibility audit](TRAINING_WINDOW_ELIGIBILITY.md).
The V11 alignment checks do not rerun LLM inference, respondent scoring or
model fitting. [Release verification](RESULTS_RELEASE.md) documents attachment
integrity, table regeneration and figure rendering checks separately.

# Thesis alignment audit — 2026-09-14

Reviewed against the 87-page supplied thesis PDF, SHA-256
`028d8fb0cb338a61f16344126d862f6547564052affac152bc6f5bd616bc6b35`.
The starting public source revision was `9ad880d` in `SitongZhu/Masterarbeit`.

## Correctness and reproducibility changes

- Fix native-encoding corruption: explicitly read/write UTF-8 and initialize a UTF-8 R locale. Historical `<U+....>` artifacts introduced false numeric responses, primarily for Mistral's original-scale left-right task. The corrected rerun therefore changes some thesis numbers; the original table fixture is retained so this discrepancy remains visible.
- Correct both multinomial baselines' unseen-level handling. Full-input factor levels are not evidence that a category occurred in training; test values absent from the actual training sample now map to the training modal level as stated in the thesis.
- Fix `LC_COLLATE=C` and treatment contrasts when loading evaluation definitions. Host-language sorting had changed factor reference categories and coefficient-fidelity comparisons; character encoding remains UTF-8. The fixed order matches the archived treatment-reference ordering.
- Reject incomplete generation archives, duplicate/non-numeric identifiers, missing JSONL fields, and reference labels that disagree with prompt manifests or survey intermediates.
- Report and exclude historical files outside the task's selected waves.
- Stop prompt construction when a configured survey input is missing; fix metadata extraction to call `labelled::val_labels`.
- Preserve aggregate attempted/retained/removed counts for grouped prediction cleaning; diagnose signed/decimal token ambiguity without silently changing the historical parsing rule.
- Propagate core task/module errors so failed builds cannot appear successful.
- Compare original-scale LLM and ordinal distances on identical parsed records, without changing exact-accuracy denominators.
- Rescore ordinal/multinomial sensitivity from jointly available row-level predictions; remove comparisons based on rounded or unmatched summaries.
- Include iteration sensitivity, final structural analyses, all current thesis table fragments, and the current main/appendix figure exporters in the full runner.
- Check result identities, convergence, pooled TVD and completeness; add aggregate reference tables for an explicit thesis regression comparison.
- Restore full-run environment variables on success or failure and validate resume arguments.

Prompt text, outcomes, wave selections, historical grouped/numeric parsing,
baseline specifications, and the distinction between RQ1/RQ2/RQ3 denominators
are retained. The original numerical parser remains the thesis's permissive
first-valid-number parser; the audit does not silently replace it with a new
measurement rule. Exact reproduction of new model generations remains limited
by the missing historical inference runner/configuration.

## Removed obsolete code

- `code_manipulated_prior/` and its root smoke test: experiment absent from the supplied thesis.
- `run_03_evaluate_same_database.R` and `build_common_sample_analysis_inputs.R`: separate sample-harmonization experiment absent from the thesis; the maintained common-sample RQ analysis remains.
- `analyse_1500_dynamic_chains.R`: used available-row lags and was superseded by designated-wave temporal diagnostics.
- `audit_trajectory_output_coverage.R`: replaced by the complete archive audit, including all four prompt conditions.
- Unused legacy regression, coefficient-difference, ordinal-regression, and subgroup outcome-distribution modules inside `analyse_all_variants.R`: superseded by the dedicated final structural-fidelity and subgroup analyses.

Recover deleted source from Git revision `9ad880d`; no history was rewritten.
Research data, real prompts and generation archives were not deleted. The local
audit also preserves a source-only ZIP of the starting revision. Original
2026-09-11 packaging provenance is retained in `source_manifest.json`; it is a
historical manifest, not a claim that the audited implementation is unchanged.
`audit_manifest_20260914.json` records source hashes and deletions at the
completed statistical audit commit `ecc2284`.

The public tree now also includes the reviewed aggregate result snapshot and
all thesis figures under `results/`. See [RESULTS_RELEASE.md](RESULTS_RELEASE.md)
for this addition, [VALIDATION.md](VALIDATION.md) for the
checks actually completed and [INFERENCE.md](INFERENCE.md) for missing records
needed to reproduce model execution from scratch.

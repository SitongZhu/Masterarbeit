# Release notes

## Final V11 alignment — 2026-09-15

`results-v11-2026-09-15` pins the maintained code, all final figures and tables,
the eligibility audit and the [V11 PDF/version record](submission/v11_20260915/README.md).
[V11_RESULTS.md](V11_RESULTS.md) defines the current numerical and baseline reference.
Historical releases retain their original tag targets and attachment bytes.

## Historical revision following the V5 review — 2026-09-15

The original-scale parser now accepts complete unsigned integer categories
and rejects numeric fragments within signed values, decimals, scientific
notation and alphanumeric tokens. Both evaluation entry points use the same
boundary definition. An audit of 2,842,635 original-scale outputs found 174
changed categories, all in Mistral left-right outputs, and no changed climate
categories. The associated calculations and manuscript assets are updated in
the current result snapshot. See [VALIDATION_V5.md](VALIDATION_V5.md).

The original 2026-09-14 aggregate reference and release remain available.
`--compare-thesis` uses `thesis_current.json`; `--reference` selects an older
reference explicitly. No original generated answer is edited by this change.

## Historical thesis alignment audit — 2026-09-14

Reviewed against the 87-page supplied thesis PDF, SHA-256
`028d8fb0cb338a61f16344126d862f6547564052affac152bc6f5bd616bc6b35`.
The starting public source revision was `9ad880d` in `SitongZhu/Masterarbeit`.

## Historical correctness and reproducibility changes — 2026-09-14

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

At the 2026-09-14 audit stage, prompt text, outcomes, wave selections,
baseline specifications and RQ1/RQ2/RQ3 denominators were retained, including
the then-permissive numeric parser. The V5 correction described above superseded
that parsing rule. V11 uses strict original-scale numeric boundaries.

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
checks actually completed and [INFERENCE.md](INFERENCE.md) for the available
inference documentation.

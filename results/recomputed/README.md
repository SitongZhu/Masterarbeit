# Final V11 thesis results

These assets match the final reviewed V11 manuscript. Exact PDF identifiers
and the relationship to the fixed `results-v11-2026-09-15` release are recorded
in [the V11 version record](../../docs/submission/v11_20260915/README.md) and
`../manifest.json`. Use [V11_RESULTS.md](../../docs/V11_RESULTS.md) for numerical
values, denominators and baseline terminology.

- [Figures](figures/): all 35 analytical figure files, including final Figure 1/2/4 annotations.
- [LaTeX rows](latex/): all ten exported table fragments, 112 numeric rows.
- [Aggregate inputs](aggregate_inputs/): 268 CSV files for public replay.
- [Main claim checks](paper_claims.json): numeric counts and ranges, unchanged since the V5 scoring correction.
- [Table changes](table_changes.diff): historical differences against the 2026-09-14 manuscript.
- [Statistical result audit](result_audit.json) and [earlier aggregate replay audit](aggregate_replay_audit.json): dated provenance; the new V11 replay is recorded in the V11 version directory.

Maximum accuracy on changing transitions is 16.3%; grouped false persistence
is 76.3%–100.0%; maximum directional change capture is 36.5%. Ordinal probit
exceeds the no-time LLM in 20/20 comparisons; trajectory exceeds lag-and-covariates
ordinal probit in 8/20. Multinomial logit is a supplementary robustness baseline.

The V11 alignment does not change these estimates. The prior scoring corrections
and their scope remain documented in [the V5 audit](../../docs/VALIDATION_V5.md).
The manuscript imports these ten fragments and 35 figure files. After full
evaluation, `audit_thesis_results.py --compare-thesis` checks the current reference.

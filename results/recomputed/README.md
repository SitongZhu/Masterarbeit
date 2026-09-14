# Corrected thesis results

These results match the revised thesis dated 2026-09-15. The original-scale
outputs were re-scored using strict numeric boundaries, and all dependent
comparison tables and figures were regenerated. Source and PDF hashes are in
`../manifest.json`; the prior release remains available for comparison.

- [Figures](figures/): all 35 analytical figure files required by the thesis.
- [LaTeX rows](latex/): all ten exported table fragments.
- [Aggregate inputs](aggregate_inputs/): 268 CSV files for public figure/table replay.
- [Main claim checks](paper_claims.json): recomputed counts and ranges quoted in the text.
- [Table changes](table_changes.diff): differences against the submitted thesis.
- [Statistical result audit](result_audit.json) and [aggregate replay audit](aggregate_replay_audit.json).

Eight table fragments changed. The maximum exact accuracy after an observed
transition is 16.3%, replacing 16.7% in the supplied PDF's abstract and RQ3 text
(PDF pages 2 and 22). The DCCR maximum remains 36.5%. The main comparison counts
also remain: ordinal exceeds the no-time LLM in 20/20 comparisons, and trajectory
exceeds the lag-and-covariates ordinal baseline in 8/20 comparisons.

The updates combine the documented UTF-8 and multinomial unknown-category
corrections with the numeric-boundary fix. The latter changes 174 original-scale
input classifications and four table fragments relative to the preceding
corrected release. C collation and treatment contrasts keep categorical references
consistent with the historical analysis. See [release notes](../../docs/RELEASE_NOTES.md).

The revised manuscript imports all ten generated table fragments, including
the iteration-stability table, and uses these 35 figure files. The current
reference check is `audit_thesis_results.py --compare-thesis` after evaluation.

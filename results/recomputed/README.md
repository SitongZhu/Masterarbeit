# Corrected thesis results

These results come from the completed full-data audit at source commit
`ecc228470d4f15e330946a723950f78b8e07b7df`.

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

The updates reflect the documented UTF-8 and multinomial unknown-category
corrections. C collation and treatment contrasts keep categorical references
consistent with the historical analysis. See [release notes](../../docs/RELEASE_NOTES.md).

For a manuscript update, replace corresponding figures and table fragments.
The originally handwritten iteration table can use
`\input{Appendix/generated/iteration_stability_rows}`; replace its eight body
rows and following `\hline`, since the fragment supplies that rule itself.
Revise the affected prose and recompile the manuscript.

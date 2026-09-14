# Validation following the V5 review — 2026-09-15

The review identified a real error in numeric token boundaries. The new parser
rejects `-1`, `3.5`, `3,5`, `3e2`, and embedded alphanumeric fragments, while
retaining the first independently valid integer in surrounding text. It is
shared by the main and common-sample evaluation scripts.

## Actual archive check

- 290 original-scale generation files, containing 2,842,635 records, were
  compared with the analytical inputs. Model, condition, reference label,
  prediction text and multiplicity agree after CRLF/LF normalization only.
  The full archive's prior ID/wave/prompt validation remains documented in
  `results/generation_archive/`.
- All 104,875 distinct original-scale prediction strings agree between the R
  production parser and the independent Python audit, including after the
  production whitespace normalization.
- Climate-growth: 0 changed categories in 1,566,855 records.
- Left-right: 174 changed categories in 1,275,780 records, all Mistral outputs:
  date-bounded 52, no-time 6, context-anchored 67, trajectory 49.
- Of these 174 records, 72 become unresolved; the remainder receive a later
  valid category. Historical parsing classified 2 correctly, revised parsing
  29. These counts cover all original-scale inputs, rather than any one RQ's
  restricted comparison sample.
- Actual counterexamples included digits from date strings and an explicit
  `-1` response. Such fragments are not valid survey answers.

Aggregate audit files are in [validation_20260915/](validation_20260915/).
The case list and complete generated strings remain local because they contain
individual survey information.

## Recalculation method

The new evaluation uses byte-identical, correctly decoded analytical inputs
from the preceding validated run. Both original-scale tasks are re-scored,
including their lagged predictions, transition, distribution, subgroup and
baseline-comparison calculations. Structural models and common-sample scores
are recomputed, followed by all publication tables and figures.

Human-only ordinal and multinomial baseline predictions are reused from the
verified fixed-collation run. Their input files and fitting definitions are
unchanged; each reused multinomial prediction table is checked against the
current human ID/wave/outcome rows. This reuse does not retain old LLM comparison
rows. The public full-build command still fits these baselines from scratch.

The original inference runner, exact checkpoint revisions, and complete
decoding settings remain unavailable. No new model inference is claimed.
The existing generation archive supports evaluation without these checkpoints.

## Completed checks

The evaluation and publication build completed successfully. The audit checks
40 primary comparisons, 20 transition configurations, 48 converged ordinal
and 48 converged multinomial baseline fits from the preceding run, and 40
newly recomputed structural metric rows. Reused baseline CSV values agree with
their originals within 1e-12; six files differ only in serialization.

The complete archive again passed the maintained input audit: 580 files and
5,685,270 records. Lag linkage passed for all four analytical tasks. The R
syntax check parsed 39 source files; parser boundary tests, regression
contracts, the 116-prompt/four-task smoke pipeline, and the two Python archive
audit tests passed.

The thesis now imports all ten generated table fragments and 35 figure files.
Eight fragments differ from the original thesis; four differ from the previous
corrected release specifically because of numeric boundaries. The maximum
changed-transition accuracy is 16.3%, compared with 16.7% in the old thesis;
this change combines the earlier encoding correction with this revision.
The principal conclusions remain: ordinal exceeds the no-time LLM in 20/20
comparisons, trajectory exceeds the lag-and-covariates ordinal baseline in
8/20, and trajectory is below carry-forward in 17/20. Stable records contribute
at least 76.95% of correct trajectory predictions.

The historical table reference is preserved. The current reference records
the revised manuscript's table text and compiled PDF hash; the evaluation
checks it independently of the historical snapshot.

The public aggregate-only replay also passed: all ten table fragments agree,
and all 35 figures are pixel-identical to the respondent-level export in the
validation environment. This path requires neither private data nor model
checkpoints. It reproduces exports, not model fitting or respondent scoring.

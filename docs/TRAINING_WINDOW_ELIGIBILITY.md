# Training-window predictor eligibility audit

The original baseline pipeline screens profile predictors on the full analytical
input, then fits each model using earlier waves. This audit checks whether moving
that screen inside the training window changes the baseline specification.

## Result

All **48 estimable task-by-baseline windows** retain the same effective predictors:
26 covariates-only windows and 22 lag-and-covariates windows across the four tasks.
The corresponding training-record counts, predictor sets, and predictor counts
match all **96 archived ordinal-probit and multinomial-logit fit diagnostics**.
No baseline requires refitting as a consequence of the eligibility screen.

Eligibility itself differs in two windows. In both climate-growth tasks, the
first lag-and-covariates fit targets wave 14 using 8,507 training records from
wave 11. `kp_020` is missing in every training record, so training-only screening
excludes it. The existing pipeline already removes this predictor through its
training-variation check. The remaining 46 windows have identical eligibility
sets. Restricting the original repeated analytical rows to earlier waves also
returns the original eligibility set in every checked window.

## Procedure and evidence

The audit uses the maintained selector with its existing thresholds: at least
30 observed values, at least 2% coverage, and 2–20 observed levels. It starts with
every candidate `kp_`/`pi_` profile column except the target outcome. It compares
both earlier-wave analytical rows and the deduplicated human records actually
eligible for each baseline's training set. The lag specification additionally
requires an observed preceding answer. The first target wave without a usable
training set is excluded from the 48 estimable windows.

The four inputs match the hashes recorded for the previous full-data evaluation.
The audit reads these local inputs and archived fit diagnostics; it exports only
variable-level counts and fit-level checks. It does not fit models, regenerate
LLM answers, or export respondent records.

- [Summary](audits/training_window_eligibility_summary.json)
- [Window-level comparisons](audits/training_window_eligibility.csv)
- [Feature counts and eligibility](audits/training_window_feature_counts.csv)
- [Archived fit comparisons](audits/training_window_reference_checks.csv)
- [Input and audit-source hashes](audits/training_window_input_source_hashes.json)

With the corresponding analytical inputs and completed baseline outputs, run
from `code/`:

```text
Rscript 03_evaluation/scripts/audit_training_window_eligibility.R INPUT_DIRECTORY OUTPUT_DIRECTORY REFERENCE_EVALUATION_DIRECTORY
```

This result addresses the eligibility-screening boundary for the evaluated
inputs. The manuscript retains its separate limitations concerning contemporaneous
information, retained samples, model selection, and generation variability.

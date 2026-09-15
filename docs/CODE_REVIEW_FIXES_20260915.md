# Code review maintenance fixes — 2026-09-15

The reviewed fixed archive is tag `results-2026-09-15` (commit `908254b`).
These maintenance changes follow that archive and preserve the historical tag.

The review branch is `fix/code-review-20260915`, based on `06efc8b`.
Its reviewed commit `e3d796f` is now merged into the default branch, `main`;
regular clones include all five code fixes and their regression tests.
The original archive and the earlier audit branch do not contain these changes. The
[machine-readable validation record](validation/code_review_20260915.json)
includes SHA-256 hashes for the source files that were validated.
The later documentation translation is recorded in the
[current source and documentation checks](validation/english_documentation_20260915.json).
The original review hashes remain tied to the reviewed commit.

## Changes

1. **SVG dependency:** include `svglite` in installation, setup checks and the
   validation environment record. The information-ladder export requires it.
2. **Auxiliary multinomial comparisons:** both lag-plus-covariates and
   covariates-only summaries now compare every method on rows with an available
   statistical prediction. Row-level exports retain all input records.
   `n_input` counts input rows; `n_comparison` and `n_total` count the common
   comparison rows. Counts of correct answers, accuracies, modal share and
   differences all refer to that comparison sample. Unparsed LLM answers remain
   incorrect on this sample. A wave with no statistical predictions has zero
   comparison rows and missing accuracies, rather than zero accuracies.
3. **Descriptive subgroup results:** retain row counts, correct counts,
   accuracy and accuracy gaps; add distinct `n_respondents` and `n_missing_lfdn`.
   Remove independent-binomial standard errors, confidence intervals,
   proportion tests and the grouped-binomial regression. Plots show point
   estimates. Reruns remove the three retired generated inference CSVs and write
   a note explaining the descriptive outputs. `min_n` still means row count.
   This does not introduce any new thesis significance analysis.
4. **Archive restoration:** require unique archive names and paths, exact
   coverage of referenced archives, consistent file and archive record totals,
   expected ZIP members and matching archive hashes before extraction. Before
   reporting success, verify every expected restored file, its hash and its
   actual JSONL record count. Conflicting existing files are preserved.
5. **Dynamic edge cases:** empty, all-stable, all-changed and unparsed samples
   retain counts and return `NaN` for unsupported conditional ratios. Accuracy
   remains zero when observations exist but no predictions are correct.
   The stable/changed decomposition is verified with integer correct counts.
6. **Version selection:** the repository homepage distinguishes the
   maintained code on `main` from the fixed thesis archives and provide clone
   and update commands. Both historical tags, `results-2026-09-14` and
   `results-2026-09-15`, remain at their original commits; the default branch
   includes these maintenance fixes.

## Published results and integrity checks

The ordinal main comparisons already filter unavailable predictions. Their
comparison logic is unchanged. The final subgroup figures use accuracy point
estimates, so removing the auxiliary intervals does not alter those estimates.

The current `results/manifest.json` updates the source hashes of the modified
table exporter and restore utility. Published aggregate, table and figure hashes are preserved.
This keeps aggregate replay's source-integrity check active for the maintained
exporter; the frozen tag retains its original manifest and code.

Validation commands from the repository root:

```sh
Rscript setup/install_packages.R
Rscript tests/check_syntax.R
Rscript tests/smoke_main_pipeline.R
Rscript tests/regression_contracts.R
Rscript tests/test_utf8_locale.R
Rscript tests/test_numeric_response_parser.R
Rscript tests/test_auxiliary_analysis.R
python -m unittest discover -s tests -p "test_*.py" -v
python tools/reproduce_published_results.py --output-dir code/outputs/review_replay
```

The synthetic tests fit small statistical models. Public replay checks the
stored aggregates and exports; it does not refit the full microdata models or
rescore all historical generated answers.

Validation completed with R 4.3.2, `svglite` 2.1.3 and Python 3.12.4: all six
R check entries and 16 Python tests passed. The standalone regression entry
now initializes UTF-8 using the same helper as the pipeline. Public replay
verified 402 published files, reproduced all ten table fragments without
differences and generated all 35 required analytical figures. The actual R
information-ladder PNG, PDF and SVG exports also completed successfully.

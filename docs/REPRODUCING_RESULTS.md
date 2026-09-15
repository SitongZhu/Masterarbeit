# Reproducing figures and reanalyzing saved model answers

Saved model answers can be reanalyzed without rerunning LLM inference.

## Public figure and table reproduction

The repository includes both the submitted thesis assets and corrected assets
under [results/](../results/README.md). The corrected snapshot contains 268
aggregate input files, ten LaTeX table fragments and 35 analytical figures.
The cover emblem is also available as a static asset.
The [results release](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-v11-2026-09-15)
provides the fixed source-and-results ZIP. Alternatively, check out tag
`results-v11-2026-09-15` to use the same published revision.

```sh
git clone --branch results-v11-2026-09-15 --depth 1 https://github.com/SitongZhu/Masterarbeit.git
cd Masterarbeit
```

The V11 fixed release includes the subsequent code fixes and final figure
annotations. The [V11 manuscript version record](submission/v11_20260915/README.md)
identifies both the reviewed PDF and the PDF whose appendix links to this release.
All 112 numeric rows in ten table fragments match the reviewed V11 PDF.
Historical releases and the V6 record remain available as dated records.

From the repository root:

```sh
python -m pip install -r requirements.txt
python tools/reproduce_published_results.py --check-only
python tools/reproduce_published_results.py
python tools/audit_v11_results.py
```

Outputs are written to `code/outputs/published_replay/`. Use `--output-dir PATH`
to choose another empty directory. Existing results are preserved. The command
verifies both analysis and exporter source-file hashes, re-exports the tables and figures, checks all ten
tables against the corrected snapshot, and records `aggregate_replay_audit.json`.
The figure exporters also check the plotted values and text bounds. The V11
release audit additionally compared all 35 rendered figure files against the
final manuscript assets. The ordinary replay command checks figure coverage;
it does not itself perform pixel comparison. `audit_v11_results.py` independently
checks the main comparison counts, ranges, transition identities and supporting
results from the public aggregates; see [the numerical reference](V11_RESULTS.md). PDF bytes
can differ because of timestamps or rendering-library versions.

This mode only re-exports aggregates. It does not independently reproduce the
survey joins, response scoring, statistical fits or their uncertainty. This
mode does not require R, GLES microdata or LLM inference.

## Full reanalysis with archived LLM outputs

Required materials:

1. The GLES releases listed in [DATA_AVAILABILITY.md](DATA_AVAILABILITY.md),
   obtained through the provider under the applicable access conditions.
2. The complete 580-file generation bundle, with 5,685,270 responses and its
   `generation_bundle_manifest.json`. See [archive availability](../results/generation_archive/README.md).
3. The R and Python dependencies documented in this repository.

Place the official survey files as documented in [code/data/README.md](../code/data/README.md).
From the repository root:

```sh
Rscript setup/install_packages.R
python -m pip install -r requirements.txt
python tools/restore_generation_bundle.py --bundle-dir PATH_TO_BUNDLE
cd code
Rscript check_project_setup.R
Rscript run_01_generate_prompts.R
python 03_evaluation/scripts/audit_generation_inputs.py
Rscript run_03_full_evaluation.R
```

The restore utility verifies archive coverage, archive and individual-file
hashes, and actual restored record counts. It preserves
existing files that differ, and restores the three fields consumed by the
pipeline: `id`, `label`, `predict`. The original generated text is retained
without truncation, replacement, fuzzy cleaning or numeric extraction. The
duplicated `prompt` field is omitted; prompts and reference wave lists are
rebuilt from the official survey releases. No inference step is required.

The full build then reconstructs analysis inputs, scores answers, fits the
baselines, and exports results. `audit_thesis_results.py --compare-thesis`
compares the exports with the revised thesis's aggregate reference,
`tests/reference/thesis_current.json`. The original supplied reference remains
in `tests/reference/thesis_20260914.json`; select it explicitly with
`--reference ../tests/reference/thesis_20260914.json` to examine historical
differences. The original release and `results/submitted/` are retained.

## Preparing or preserving a bundle locally

After a successful complete generation-input audit:

```sh
python tools/prepare_generation_bundle.py --code-dir code --manifest code/outputs/evaluation/manuscript/audits/generation_input_manifest.csv --output-dir PATH_TO_EMPTY_BUNDLE_DIRECTORY
```

The utility checks every original file against the audited hash and row count,
then writes twenty ZIP files grouped by task and model. It performs no upload.
The bundle still contains survey reference answers, linkage IDs, and generated
text that may repeat survey-derived information. Omitting prompts does not
establish permission to publish the remaining individual records.

Reproducing the original generations would additionally require the model
versions and inference settings used for those runs; see
[INFERENCE.md](INFERENCE.md).

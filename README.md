# LLM Survey Response Simulation: Thesis Code

## Final V11 manuscript and fixed results

The reviewed **V11** manuscript is linked to the fixed
[`results-v11-2026-09-15` release](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-v11-2026-09-15). It includes the maintained code fixes,
the final Figure 1/2/4 annotations, all current tables and figures, and the
training-window eligibility audit. See the [V11 version record](docs/submission/v11_20260915/README.md)
for exact PDF checksums and the [V11 numerical and baseline reference](docs/V11_RESULTS.md).

```sh
git clone --branch results-v11-2026-09-15 --depth 1 https://github.com/SitongZhu/Masterarbeit.git
cd Masterarbeit
```

For an existing clone, run `git fetch origin tag results-v11-2026-09-15` and
`git switch --detach results-v11-2026-09-15`. Use `main` for subsequent maintained changes.

The older tags `results-2026-09-14` and `results-2026-09-15` preserve historical
snapshots. They predate the later code fixes and final figure annotations.
Their `submitted/` figures and table rows are historical; use `recomputed/`
in the V11 release for final-paper values. The [release audit](docs/RESULTS_RELEASE.md)
explains the relationship and the checks performed on the downloaded attachments.

Source code for a master's thesis evaluating LLM-generated responses in the
German Longitudinal Election Study (GLES). The repository contains **prompt
construction**, **preparation of model outputs**, and **evaluation** for the
four tasks and three research questions in the final reviewed V11 thesis.

The maintained project is hosted at
[SitongZhu/Masterarbeit](https://github.com/SitongZhu/Masterarbeit).
Earlier task3 experiments remain in Git history; see
[the repository transition notes](docs/REPOSITORY_MIGRATION.md).

**LLM calls / inference use the code from the
[AlignSurvey GitHub repository](https://github.com/PiLab-ZJU/AlignSurvey).**
The thesis inference pipeline was adapted from AlignSurvey's infrastructure,
which uses LLaMA-Factory for model execution. This repository contains the
thesis-specific prompt and evaluation code; the external inference code is
referenced rather than copied. See [the inference interface](docs/INFERENCE.md).

## Published figures and numerical results

[Browse every V11 thesis figure](results/README.md), all ten table fragments,
and the aggregate plotting inputs. Historical figures are explicitly labeled. The 35 analytical figure files and the cover emblem are included.
[Download the result release](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-v11-2026-09-15)
for a fixed source-and-results snapshot.

To rebuild the corrected tables and figures from the public aggregates:

```sh
python -m pip install -r requirements.txt
python tools/reproduce_published_results.py
```

This path exports stored aggregate results without survey microdata or LLM
inference; it does not repeat respondent scoring or model fitting.
For full reanalysis using saved LLM answers, see
[the replication guide](docs/REPRODUCING_RESULTS.md).

## Repository structure

```text
code/
  01_prompt_generation/scripts/       # GLES preparation and prompt construction
  02_build_analysis_inputs/scripts/   # JSONL joins and prediction normalization
  03_evaluation/scripts/              # Metrics, baselines, diagnostics, figures
  run_01_generate_prompts.R
  run_02a_build_and_clean_analysis_inputs.R
  run_02b_evaluate_existing_analysis_inputs.R
  run_02_build_inputs_and_evaluate.R
  run_03_full_evaluation.R
  data/README.md                      # Required local input files
setup/install_packages.R
tests/                               # Synthetic checks and aggregate thesis references
examples/                            # Synthetic interface examples only
docs/                                # Workflow, attribution, release notes
environment/                         # Validation environment versions
results/                             # Thesis figures, tables, and aggregate inputs
tools/                               # Aggregate replay and generation archive utilities
requirements.txt                     # Python dependencies for the full thesis build
```

## Tasks and prompt conditions

| Variant directory | Outcome | Representation | Selected waves |
| --- | --- | --- | --- |
| `1290` | Climate protection versus economic growth | Three groups | 10, 11, 14, 15, 22, 23, 25, 26 |
| `1290_original_scale` | Climate protection versus economic growth | Original 1–7 scale | 10, 11, 14, 15, 22, 23, 25, 26 |
| `1500` | Left–right self-placement | Three groups | 10, 14, 15, 22, 23, 25, 26 |
| `1500_original_scale` | Left–right self-placement | Original 1–11 scale | 10, 14, 15, 22, 23, 25, 26 |

The historical `clustered` script names and bare `1290` / `1500` directories
mean **grouped outcomes**. Filenames are preserved for compatibility.

| Condition | Prompt filename | Information supplied |
| --- | --- | --- |
| No-time | `prompt_w14_baseline_notime.json` | Respondent profile and question |
| Date-bounded | `prompt_w14.json` | Profile, question, and survey field dates |
| Context-anchored | `prompt_w14_tanchored.json` | Profile, question, dates, and period context |
| Trajectory | `prompt_w14_trajectory.json` | Profile, question, dates, and designated preceding human response |

Trajectory prompts require a valid response in the designated preceding
selected wave. They are absent for the first selected wave. Stored `output`
is the current observed response for scoring, not an additional prompt field
to show to the model.

## Install and run

Validation used R 4.3.2 and Python 3.12.4. R is required for the analysis;
Python is required for the full build's input audits, tables, and figures.
See [environment/README.md](environment/README.md) for the tested versions.
Put `Rscript` on your PATH, or use its full executable path.

From the repository root:

```sh
Rscript setup/install_packages.R
python -m pip install -r requirements.txt
cd code
Rscript check_project_setup.R
```

Supply the files listed in [code/data/README.md](code/data/README.md), then:

```sh
Rscript run_01_generate_prompts.R
```

Run the generated prompt JSON files using **AlignSurvey**, following
[docs/INFERENCE.md](docs/INFERENCE.md), and place the resulting JSONL files in
`code/data/llm_outputs/outcome/<variant>/`. Then, from `code/`:

```sh
Rscript run_02a_build_and_clean_analysis_inputs.R
Rscript run_02b_evaluate_existing_analysis_inputs.R
```

Alternatively, `Rscript run_02_build_inputs_and_evaluate.R` performs both steps.
For the full thesis evaluation, including ordinal-probit baselines, publication
tables, diagnostics, and figures, run from `code/` after inference:

```sh
Rscript run_03_full_evaluation.R
python 03_evaluation/scripts/audit_thesis_results.py --compare-thesis
```

This full build uses the thesis's four tasks and five model configurations;
its input audit checks all 580 generation files and 116 prompt manifests. It
requires the generated prompts, intermediate RDS files, and complete archived
JSONL generations. It may take substantially longer than the basic evaluation.
`--skip-input-rebuild` reuses matching cleaned inputs. Use a fresh output directory
for independent replication. Set `MANUSCRIPT_PYTHON`
to the Python executable if necessary. No LaTeX installation or manuscript
checkout is needed: LaTeX row fragments and figures remain under
`code/outputs/evaluation/`. Final thesis assets are in `publication/latex/`
and `publication/figures/`; `publication/result_audit.json` records output
coverage and differences from the supplied thesis's aggregate reference tables.
The reference comparison is a regression check, not a statistical proof.

## Evaluation coverage

- Current-state accuracy, grouped prediction parsing, and ordinal-distance metrics.
- Aggregate distributional agreement and demographic subgroup diagnostics.
- Structural fidelity using parallel human/LLM regression specifications.
- Prior-state persistence, stable/changing transitions, anchored change, and self-trajectories.
- Expanding-window ordinal-probit baselines; multinomial-logit robustness baselines.
- Common-sample comparisons, model-configuration comparisons, tables, and figures.

See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the script map and denominator
definitions. Experimental manipulated-prior and same-database branches, the
obsolete dynamic-chain script, and superseded regression modules were removed
from the maintained tree; they remain recoverable in Git history.

## Validate without research data

From the repository root:

```sh
Rscript tests/check_syntax.R
Rscript tests/smoke_main_pipeline.R
Rscript tests/regression_contracts.R
Rscript tests/test_utf8_locale.R
Rscript tests/test_numeric_response_parser.R
python -m unittest discover -s tests -p "test_*.py"
```

The smoke checks use invented respondents and local temporary files. They do
not call an LLM or reproduce the thesis's numerical estimates. Full numerical
reproduction requires the separately supplied research data and archived model
outputs. See [docs/VALIDATION.md](docs/VALIDATION.md) for what was checked.

## Data and attribution

This release includes source, thesis figures, aggregate fitted results and table
fragments under `results/`. GLES microdata, real respondent prompts, individual
model generations and manuscript drafts are not bundled. `.gitignore` excludes
local research inputs and runtime outputs; the reviewed result snapshot is tracked.

This describes the current source tree and packaged release. Earlier commits
in this existing repository contain legacy experiment data, generations, logs,
and model artifacts. Replacing the current tree does not remove those historical
files; this update does not rewrite Git history.

**Get the raw data from the [official GLES data portal](https://www.gesis.org/en/gles/data-and-documentation),
not from this repository.** The main panel release is
[ZA6838, version 6.0.0](https://doi.org/10.4232/1.14114).
[Data availability and access](docs/DATA_AVAILABILITY.md) lists all nine
configured studies, their versions, official download entry points, and DOIs;
[the local input guide](code/data/README.md) gives the exact filenames.
Registration and the applicable GESIS access conditions apply.

Real respondent prompts and archived JSONL contain survey-derived information,
reference answers, and identifiers. They are excluded alongside raw microdata;
no public download link is currently provided for the original model outputs.
They may be retained locally under the documented ignored directories.
The original numerical results require the matching archived generations.

This release follows the thesis's statement that GLES data are not redistributed.
See the [GESIS usage regulations](https://www.gesis.org/fileadmin/user_upload/Usage_regulations.pdf)
and the release discussion in [DATA_AVAILABILITY.md](docs/DATA_AVAILABILITY.md).

Please acknowledge AlignSurvey when describing the inference infrastructure:

Lin, C., Yuan, W., Jiang, Z., Huang, B., Zhang, R., Ge, J., Xu, Y., & Yu, J.
(2026). *AlignSurvey: A Comprehensive Benchmark for Human Preferences
Alignment in Social Surveys*. Proceedings of the AAAI Conference on Artificial
Intelligence, 40, 38908–38916.
[Published article](https://doi.org/10.1609/aaai.v40i45.41236).

See [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md) for the BibTeX reference and
upstream links. No third-party source code or model weights are vendored here.

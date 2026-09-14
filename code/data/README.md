# Local research data

This source release does not contain GLES survey microdata, respondent-level
prompts, model generations, analysis CSVs, or generated experiment manifests.
Obtain the survey data separately from its provider and follow the conditions
attached to your dataset access. The source filenames and versions are preserved.

Download through the [official GLES portal](https://www.gesis.org/en/gles/data-and-documentation).
The [study/version/DOI table](../../docs/DATA_AVAILABILITY.md) links all configured
releases and explains access conditions and the treatment of respondent-level
model outputs. Select the listed version rather than automatically using the
newest release. A GESIS download entitlement does not itself authorize a public
mirror of the files.

Run `Rscript check_project_setup.R` from `code/` to create the local directories.
Place the following files **inside the directory**
`data/raw_survey/ZA6838_v6-0-0.dta/` (the directory itself ends in `.dta`):

```text
ZA6838_w1to9_sA_v6-0-0.dta
ZA6838_w10_sA_v6-0-0.dta
ZA6838_w11_sA_v6-0-0.dta
ZA6838_w12_sA_v6-0-0.dta
ZA6838_w13_sA_v6-0-0.dta
ZA6838_w14_sA_v6-0-0.dta
ZA6838_w15_sA_v6-0-0.dta
ZA6838_w16_sA_v6-0-0.dta
ZA6838_w17_sA_v6-0-0.dta
ZA6838_w18_sA_v6-0-0.dta
ZA6838_w19_sA_v6-0-0.dta
ZA6838_w20_sA_v6-0-0.dta
ZA6838_w21_sA_v6-0-0.dta
ZA7728_v1-0-0.dta
ZA7729_v1-0-0.dta
ZA7730_v1-0-0.dta
ZA7731_sA_v1-0-0.dta
ZA7732_sA_v1-0-0.dta
ZA7733_sA_v1-0-0.dta
ZA10117_w28_sA_v2-0-0.dta
ZA7961_wa5_sA_v1-0-0.dta
ZA6838_wa2_sA_v6-0-0.dta
```

The prompt builders load the configured wave files and supplementary personal
information files. Keep the named versions for thesis reproduction. Missing
configured files stop prompt generation before processing begins.

`run_01_generate_prompts.R` creates `outputs/prompts/<variant>/` and
`data/intermediate_hdata/wave_list_for_llm_join_<variant>.rds` together with
wave-column metadata. These artifacts are needed for later joins and audits.

After external LLM inference, place each generation file at:

```text
data/llm_outputs/outcome/<variant>/<optional-model-directory>/
  nosft_<model>__prompt_w<wave>[_<condition>].jsonl
```

The main builder expects `id`, `label`, and `predict` on every JSONL record.
`id` must remain the original numeric GLES `lfdn` identifier. `label` retains
the source prompt's `output`; `predict` contains only the generated answer.
Wave, model, and prompt condition are recovered from filenames; the task comes
from the variant directory. Do not concatenate different tasks into one file.
Repeated basenames or respondent/model/wave/condition keys are rejected.
The full build also checks that all expected records are present and that
identifiers and reference labels match their prompt manifests. The join checks
reference labels against the wave-list RDS before using them as outcomes.
Files from waves outside a task's selected wave set are reported and excluded.

The builder writes `data/analysis_inputs/analyse_<variant>.csv`; the cleaner
then normalizes grouped answer labels in place and drops rows whose predictions
remain unparseable. Original-scale inputs bypass that fuzzy-cleaning step.
All data directories except
this document, and all generated outputs, are excluded by `.gitignore`.

# External LLM inference: AlignSurvey

**LLM calls in this thesis use code from
[PiLab-ZJU/AlignSurvey](https://github.com/PiLab-ZJU/AlignSurvey).**
AlignSurvey's infrastructure uses LLaMA-Factory for model execution. The
thesis adapts this inference infrastructure to the GLES prompts built here.
The released instruction-tuned models were used without additional fine-tuning.
The upstream implementation is maintained separately.

The upstream [README](https://github.com/PiLab-ZJU/AlignSurvey#readme)
documents `LLaMA-Factory/data/dataset_info.json`, inference scripts under
`LLaMA-Factory/run/test/`, and API examples under `LLaMA-Factory/run/api/`.
Follow that repository for installation and execution settings. Register
the thesis JSON files as custom datasets and configure the model and template
in the external runner. Preserve each source record's identifier in its result.

## Input and output contract

Each `outputs/prompts/<variant>/prompt_w<NN>*.json` is a JSON array with:

| Field | Meaning |
| --- | --- |
| `instruction` | Respondent profile, question, and condition-specific information |
| `input` | Blank placeholder; the current builders write a single space (`" "`) |
| `output` | Observed response retained as a reference label |
| `id` | Original respondent identifier, corresponding to GLES `lfdn` |

The reference `output` must not be concatenated into the inference prompt.
Export results as JSONL, one object per line:

```json
{"id": 900001, "label": "Links", "predict": "Links"}
```

The example uses an invented respondent. `label` is copied from the source
record's `output`; `predict` is the generated answer. Extra fields are allowed.
If the runner drops `id`, restore it from a verified record mapping before
evaluation; identifiers must not be inferred from unchecked output order.
For the main pipeline, identifiers must be numeric-compatible because the
join casts them to match the survey `lfdn` field.

For main experiments, output names are:

```text
nosft_<model>__prompt_w14_baseline_notime.jsonl
nosft_<model>__prompt_w14.jsonl
nosft_<model>__prompt_w14_tanchored.jsonl
nosft_<model>__prompt_w14_trajectory.jsonl
```

Store them under `code/data/llm_outputs/outcome/<variant>/`. Model subfolders
are supported, but basenames must be unique within each task directory.
The maintained thesis design has 580 generation files: five model
configurations times 116 task/wave/prompt combinations. Run
`python 03_evaluation/scripts/audit_generation_inputs.py` from `code/` to check
coverage, record identifiers, reference labels, and file hashes before analysis.
Use `--files-only` for a quick existence check; it does not verify records.

## Reproduction records

Keep the exact AlignSurvey commit, any local runner modifications, model
identifier/revision, chat template, quantization, decoding parameters, seed,
and library versions with each new inference run. This repository does not
include a complete record of the original inference configuration or a verified
upstream commit. Current upstream defaults should not be treated as the
original experiment configuration.

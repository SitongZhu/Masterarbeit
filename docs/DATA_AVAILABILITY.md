# Data availability and access

## Official GLES sources

Obtain the original data through the
[GESIS GLES data and documentation portal](https://www.gesis.org/en/gles/data-and-documentation).
GESIS states that registration is required for GLES data use. Access and
redistribution depend on the relevant release conditions; registration and
download access do not themselves grant permission to republish the files.
See [GESIS data-access information](https://www.gesis.org/en/data-services/about-the-data-services/standards-and-workflows-data-services/data-access-access)
and the [usage regulations](https://www.gesis.org/fileadmin/user_upload/Usage_regulations.pdf).

The versions below match the filenames configured in the prompt builders.
Study pages may display newer releases; select the listed version when
reproducing this code's inputs.

| Study | Configured version | Role in this code | Official study page | Version DOI |
| --- | --- | --- | --- | --- |
| ZA6838, GLES Panel 2016–2021, waves 1–21 | 6.0.0 | Main selected waves 10, 11, 14, 15; earlier waves and profile A2 supply background data | [GESIS](https://search.gesis.org/research_data/ZA6838) | [10.4232/1.14114](https://doi.org/10.4232/1.14114) |
| ZA7728, wave 22 | 1.0.0 | Main target wave | [GESIS](https://search.gesis.org/research_data/ZA7728) | [10.4232/1.13970](https://doi.org/10.4232/1.13970) |
| ZA7729, wave 23 | 1.0.0 | Main target wave | [GESIS](https://search.gesis.org/research_data/ZA7729) | [10.4232/1.14064](https://doi.org/10.4232/1.14064) |
| ZA7730, wave 24 | 1.0.0 | Configured loader input; not a selected main target wave | [GESIS](https://search.gesis.org/research_data/ZA7730) | [10.4232/1.14141](https://doi.org/10.4232/1.14141) |
| ZA7731, wave 25 | 1.0.0 | Main target wave | [GESIS](https://search.gesis.org/research_data/ZA7731) | [10.4232/1.14242](https://doi.org/10.4232/1.14242) |
| ZA7732, wave 26 | 1.0.0 | Main target wave | [GESIS](https://search.gesis.org/research_data/ZA7732) | [10.4232/1.14349](https://doi.org/10.4232/1.14349) |
| ZA7733, wave 27 | 1.0.0 | Configured loader input; not a selected main target wave | [GESIS](https://search.gesis.org/research_data/ZA7733) | [10.4232/1.14425](https://doi.org/10.4232/1.14425) |
| ZA10117, wave 28 | 2.0.0 | Configured loader input; not a selected main target wave | [GESIS](https://search.gesis.org/research_data/ZA10117) | [10.4232/5.ZA10117.2.0.0](https://doi.org/10.4232/5.ZA10117.2.0.0) |
| ZA7961, profile wave A5 | 1.0.0 | Supplementary respondent-profile input | [GESIS](https://search.gesis.org/research_data/ZA7961) | [10.4232/1.14543](https://doi.org/10.4232/1.14543) |

Wave 11 is selected for outcome 1290 only. The additional configured waves
must not be interpreted as extra thesis target waves. The exact Stata
filenames, including sample suffixes, are in [code/data/README.md](../code/data/README.md).

The version references already cited in the thesis were retained. The
additional references were checked against the official documentation for
[wave 24](https://access.gesis.org/dbk/74552),
[wave 27](https://access.gesis.org/dbk/78240),
[wave 28](https://access.gesis.org/dbk/79665), and
[profile A5](https://access.gesis.org/dbk/79324).

## What is released

| Material | Public code package | Local replication role |
| --- | --- | --- |
| Prompt builders, evaluation scripts, documentation | Included | Main implementation |
| Invented examples and synthetic tests | Included | Validate interfaces without respondent records |
| Thesis figures, table fragments, aggregate plotting inputs | Included under `results/` | Re-export the published figures and tables without microdata or model weights |
| Original GLES Stata files | Official links only | Supply the documented versions under `code/data/raw_survey/` |
| Real respondent prompt JSON | Excluded | Generated locally; contains survey-derived profiles and reference answers |
| Archived model JSONL | Excluded; no public download URL is supplied | Needed for evaluation of the original generations |
| Wave-list RDS and analysis CSV | Excluded | Respondent-level intermediates created locally |
| Runtime/editor caches and logs | Excluded | Retain locally as needed; not required as published source |

The inspected main-experiment JSONL files contain `prompt`, `predict`, `label`,
and `id`. They therefore include observed reference answers and respondent
linkage in addition to generated text. A model-generated answer does not
make the entire record synthetic. Removing only the identifier would not
establish that the remaining profile and answers are suitable for release.

The public package includes aggregate results while retaining the thesis's
statement that GLES microdata are not redistributed. No separate authorization
for publishing the respondent-level source or derived files has been supplied.
The GESIS usage regulations, sections 3 and 4, distinguish authorized
redistribution and scientific aggregate reporting from publication of individual
cases. A license or written authorization covering the proposed generation
archive is needed before releasing it publicly.

The generation archive utilities retain `id`, `label` and `predict`, omitting
the repeated prompt field. This reduces size without changing the inputs used
by the evaluation. These files still contain reference answers and linkage;
packaging does not anonymize them. The public
[archive index](../results/generation_archive/README.md) describes availability.

## Local use and reproducibility limits

After obtaining authorized data access, run `Rscript check_project_setup.R`
from `code/`, place the listed files in the documented local directories,
and follow the [workflow](WORKFLOW.md). The same directories can hold the
researcher's authorized local copies; `.gitignore` excludes their contents.
Its rules do not protect files already tracked by Git or files manually
uploaded through a browser, so publish the supplied source ZIP rather than
an arbitrary archive of a populated working directory.

Runtime caches such as `__pycache__` can be rebuilt. Wave-list RDS files are
research intermediates, not interchangeable runtime
caches; preserve them with the prompts and generations to maintain correct
joins. Archived generations should be retained locally for result reproduction.

There is currently no public archive link for the thesis's original
respondent-linked model outputs. Access to GLES alone is insufficient to
reproduce the original numerical results without those generations. See
[INFERENCE.md](INFERENCE.md) for the available inference configuration records.

Links and release policy reviewed on 2026-09-14. For dataset-specific
redistribution questions, consult the applicable agreement and
[the GLES contact page](https://www.gesis.org/en/gles/contact).

# Validation

The reviewed V6 PDF uses the same verified results. Its distinct file hash,
87-page content comparison and independent aggregate checks are recorded in
[the V6 version record](submission/v6_20260915/README.md).

The 2026-09-15 revision replaces the permissive numeric boundary rule after
checking the actual generation archive. See [the current validation record](VALIDATION_V5.md).
The dated audit below documents the preceding version and is retained for provenance.

## Historical audit — 2026-09-14

Checked with R 4.3.2 and Python 3.12.4 on Windows. The supplied 87-page thesis
is identified by its SHA-256 in `tests/reference/thesis_20260914.json`.
The final analysis session, including R package versions, locale and contrasts,
is recorded in [VALIDATION_SESSION.txt](VALIDATION_SESSION.txt).

The statistical audit below describes commit `ecc2284`. The subsequent public
asset snapshot and aggregate replay are documented in
[RESULTS_RELEASE.md](RESULTS_RELEASE.md); the original audit hashes remain a
record of the tested statistical revision.

| Check | Result |
| --- | --- |
| Statistical-audit source syntax | All 37 R and 11 Python source files at `ecc2284` parsed |
| Main preparation smoke test | Four real prompt builders generated 116 files from invented survey records; joins, grouped cleaning and designated lags passed |
| Input and metric regressions | Missing fields, duplicate/non-numeric IDs, wrong reference labels, UTF-8 round trips, matched distance samples, future-only factor levels and host-independent treatment references passed |
| Legacy Windows character environment | The maintained UTF-8 initializer restored a UTF-8 locale before input/output regression tests |
| Complete prediction archive | 580 required JSONL files, 5,685,270 records, IDs and labels verified against 116 prompt manifests; 12 historical out-of-design files excluded |
| Logged prompt alignment | Every recorded instruction matched its prompt manifest; only template whitespace/assistant markers followed it |
| Real survey intermediates | All four rebuilt wave lists equal their archived counterparts, including attributes; corrected value-label metadata verified |
| Real prompt reconstruction | 116/116 files verified byte-identical to the historical prompts |
| Historical export regression | All 10 reference table fragments and 35 required figures reproduced from archived summaries; plotted values also checked |
| Corrected full statistical analysis | Passed: all four task analyses and all final stages completed |
| Comparison with supplied thesis numbers | 8 of 10 table fragments differ from the supplied thesis |

The real-data verification is staged: rebuild all four analysis inputs from
the original JSONL archive, run the four core analyses in independent R
processes, and fit ordinal baselines separately;
then use the maintained `--resume-ordinal-tables` entry to recompute comparisons,
run structural and common-sample analyses, and export all final tables and
figures. The public fresh-run command performs these stages
in sequence. Input reconstruction and archived-export regression alone are
not evidence of a successful statistical refit.

The final `publication/result_audit.json` checks 40 primary comparisons,
20 transition configurations, 48 ordinal and 48 final multinomial fits,
40 structural metric rows,
pooled TVD for all four tasks, and coverage of 10 table fragments and 35
required figures. Internal validity and agreement with the historical thesis
are separate fields. `audit_thesis_results.py --compare-thesis` intentionally
fails when corrected estimates differ from that unchanged reference.

The UTF-8 correction changes previously corrupted Mistral responses and some
thesis numbers. Both multinomial baselines now replace categories absent from
actual training observations with the training modal category. See
[RELEASE_NOTES.md](RELEASE_NOTES.md) for these changes. The numerical parser's
historical boundary rule is retained; its separate diagnostic flags 170
signed/decimal-sensitive left-right records and zero climate records in the
correctly decoded inputs. A stricter parser would be a further measurement
change, not a text-cleanup operation.

Evaluation definitions fix `LC_COLLATE=C` and treatment contrasts while
retaining UTF-8 character encoding. An intermediate English-collation rerun
changed treatment references and structural coefficient metrics; that run is
retained as diagnostic evidence and is superseded by the fixed-collation run.
For example, on identical Llama climate no-time records, OLS coefficient
correlation was 0.535838809 under English collation and 0.557298662 under C
collation; the latter reproduces the archived result. Coefficient fidelity
must be interpreted conditional on the stated contrasts/reference levels.

No new LLM inference was performed. Exact regeneration of model responses is
still limited by missing historical runner/checkpoint/decoding records, as
documented in [INFERENCE.md](INFERENCE.md). Real survey inputs, respondent
prompts and generated responses remain outside the public source tree.

Some installed R packages report that they were built under R 4.3.3; the checks
ran under R 4.3.2. Validation used a UTF-8 locale, and the public entry points
now initialize it themselves. Reusable synthetic checks are included under
`tests/`; the aggregate thesis reference contains no respondent records.

# Public thesis assets and aggregate replay — 2026-09-15

The current release contains the revised thesis figures and tables after the
V5 review, including strict original-scale numeric parsing. The archived
`submitted/` assets retain the earlier thesis; `recomputed/` matches the revised
manuscript. Its PDF hash is recorded in `tests/reference/thesis_current.json`.

- All 35 analytical figure files referenced by the active thesis source are
  included in both archived and current versions. The cover emblem is also
  included. Unused figures from an obsolete, unreferenced appendix are excluded.
- Ten table fragments are included in both versions. Eight changed after the
  combined correctness fixes documented in the statistical audits. Four differ
  from the preceding corrected release because of the numeric-boundary fix.
- 268 aggregate input CSV files supply the plotting values, comparison tables,
  transition count matrices, subgroup summaries and fitted-result summaries.
- A gallery provides previews and links to both versions. `results/manifest.json`
  records asset hashes, source figure references, aggregate schemas and exporter
  source hashes. No respondent-level records are part of this snapshot.

## Verification

The public aggregate replay completed with no survey inputs, prediction rows,
R model fitting or inference. It regenerated all ten tables and 35 analytical
figures. The ten tables matched the corrected snapshot at their exported
precision, and all 35 rendered figures were pixel-identical in the validation
environment. Plotting checks covered 264 main-figure/matrix comparisons, 340
appendix values and 960 subgroup points.

The default row-level table calculation was separately checked against the
completed full-data audit results. The three recalculated metric tables and the
20 model-scale diagnostics agreed within 1e-12. The optional aggregate export
mode does not alter default respondent scoring or statistical specifications.

## Archived model answers

The original 580 JSONL files were locally repackaged using only the three fields
consumed by the evaluation: `id`, `label`, `predict`. The generated strings were
preserved without truncation or normalization. Removing repeated prompts reduced
14,749,842,003 original bytes to 397,409,710 bytes of compact JSONL, compressed
into twenty ZIP files totaling 36,896,213 bytes.

All originals matched the preexisting audit hashes during packaging. Every ZIP
and restored file passed checksum verification. The restored files then passed
the maintained input audit against the original prompt manifests: 580 files,
5,685,270 records, no missing IDs or reference-label discrepancies.

The archive manifests and restoration audit are public. The individual records
are held locally pending applicable redistribution authorization, as explained
in [archive availability](../results/generation_archive/README.md). The utilities
make a permitted transfer ready to restore; they do not grant data-sharing rights.

Use [REPRODUCING_RESULTS.md](REPRODUCING_RESULTS.md) for both reproduction paths.
The original statistical audit remains tied to commit `ecc2284`. The current
source revision and asset hashes are recorded in `results/manifest.json`.
See [VALIDATION_V5.md](VALIDATION_V5.md) for the 174 affected input records,
recalculation scope, and explicitly reused human-only baseline predictions.

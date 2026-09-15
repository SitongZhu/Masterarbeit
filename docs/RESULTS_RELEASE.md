# Final V11 release and verification

The fixed [`results-v11-2026-09-15` release](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-v11-2026-09-15)
corresponds to the final reviewed V11 thesis. Its
[version record](submission/v11_20260915/README.md) identifies the exact reviewed
PDF and the PDF whose appendix points to this release. The two PDFs contain
the same numerical results. The release-linked revision changes the replication
paragraph and synchronizes the framework PDF bytes; the framework rendering is unchanged.

Use [V11_RESULTS.md](V11_RESULTS.md) for the final accuracy values, false-persistence
ranges, denominators and baseline names. `results/recomputed/` contains the
final assets. `results/submitted/` and the older tags preserve historical material.

## Included materials

- 35 analytical figure files, including the final Figure 1 prompt labels,
  Figure 2 selected configurations and Figure 4 row denominators.
- The cover emblem, ten table fragments with 112 numeric rows, and 268 aggregate CSV inputs.
- Maintained code, including the subsequent code-review fixes and the
  [training-window eligibility audit](TRAINING_WINDOW_ELIGIBILITY.md).
- PDF checksums, figure/table maps, aggregate verification reports and release provenance.

The public package contains 402 manifest-listed result assets. The manifest
checks 47 analysis/exporter source hashes. Four stale analysis-source hashes
in the maintained branch were refreshed to match the already-reviewed fixes;
the newly added training-window audit source is also recorded. These source
identifiers describe the V11 implementation. `statistical_results_commit`
separately identifies the lineage of the existing aggregate estimates.

## Checks against V11

- Font-aware comparison confirmed identical normalized text on all 87 pages
  between the downloaded V11 PDF and the local build before the release-link edit.
  Only the replication paragraph changes in the final build, on PDF page 40
  (printed page 35). All other 86 pages retain identical extracted text.
- All 112 numeric rows in ten exported tables match the reviewed V11 PDF.
  All ten fragments and 35 final figure files also match the active manuscript assets.
- Public replay regenerated all ten tables and 35 analytical figures.
  All table contents agree; all 35 figure renderings are pixel-identical in
  the recorded validation environment (PDFs rendered at 150 dpi).
- Plot exporters checked 264 main-figure comparisons/matrices, 340 appendix
  values and 960 subgroup points. Independent aggregate checks covered the
  primary comparison counts and ranges, transition identities, 20 pooled TVD
  comparisons and 240 trajectory/no-time subgroup comparisons.
- The final PDF has 87 pages, 44 references, 25 numbered equations and 301
  resolvable named internal links, with no recorded LaTeX overflow or reference warnings.
- All 16 Python tests passed. These use synthetic data and do not estimate thesis results.

See the [V11 verification files](submission/v11_20260915/README.md). The release
also provides `V11_RELEASE_MANIFEST.json`, linking the exact Git commit and PDF
checksums to both ZIP attachments, and `SHA256SUMS.txt`. The ZIPs were extracted
and verified before publication; the public downloads were then checked against
their recorded hashes. Use [the reproduction guide](REPRODUCING_RESULTS.md).

These checks export and validate existing aggregates. They do not rerun LLM
inference, rescore respondent records or re-estimate models from GLES microdata.
The eligibility audit separately checked 48 windows against 96 archived fits;
no effective predictor set changed.

## Direct audit of the earlier fixed release

All three public attachments of `results-2026-09-15` were downloaded and checked:
`SHA256SUMS.txt`, `thesis-source-and-results.zip`, and
`thesis-figures-and-aggregate-results.zip`.

- Both ZIPs passed their checksums, GitHub digests and every member's CRC check.
- All 402 listed result assets and 46 listed source hashes in that archive passed.
- Both ZIPs contain the same 407 result-directory files.
- The source ZIP corresponds to tag commit `908254bd14529599de7cad76fcfb1a2155af8999`:
  all 498 tracked files agree after accounting for checkout line endings.
  Three files differ only by LF/CRLF (`.gitattributes`, `.gitignore`, and the R project file).
- Its ten current table fragments have the same contents as V11. Its framework,
  information-ladder and persistence-heatmap PDFs and their three previews
  predate the final annotations. It also predates subsequent maintained code fixes.

The [historical-release audit](submission/v11_20260915/historical_release_verification.json)
records the exact attachment hashes and differences. The old tag targets and
attachment bytes remain unchanged. Earlier releases are explicitly historical
and direct readers to the V11 release.

## Earlier statistical validation and generation archives

The [V5 scoring audit](VALIDATION_V5.md) documents the original-scale numeric
boundary correction, including 174 changed classifications and the associated
recalculation scope. V11 retains those corrected estimates. Dated statistical
and replay reports under `results/recomputed/` preserve that provenance.

The original 580 JSONL generation files were locally repackaged as `id`, `label`,
and `predict`, preserving generated strings. Historical restoration checks covered
5,685,270 records. The manifests and restoration audit are public; the respondent
records are held separately. See [archive availability](../results/generation_archive/README.md).
The private manuscript PDF and complete LaTeX project are also retained separately;
the public V11 release publishes their checksums and aggregate result correspondence.

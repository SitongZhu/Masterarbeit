# V6 manuscript version record — 2026-09-15

The reviewed V6 PDF is frozen as `Thesis_V6_Final.pdf` (87 pages, 3,098,143 bytes).
Its complete SHA-256 is:

```text
fa4463c5c645f7a011f8b5ef443fa057f153198efa0643fe72872e268ef39807
```

It uses the unchanged [results-2026-09-15 archive](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-2026-09-15),
at commit `908254bd14529599de7cad76fcfb1a2155af8999`. The archive's reference PDF
has SHA-256 `e05c844bd472b01205004f74c0b4954cba32bfc07c1cb8481242747b0de6b1be`.
Both identifiers remain valid for their respective files. The fixed tag,
`results/manifest.json`, and `tests/reference/thesis_current.json` are preserved.

The PDF bytes differ in compiler version, timestamps, font embedding and Unicode
maps. For comparison only, corresponding font maps were applied to an in-memory
copy of the older reference. Non-Type3 embedded font programs were checked to be
byte-identical. After this decoding and NFKC/whitespace normalization, all 87
pages have identical text, including letters, numbers and mathematical symbols.
Neither original PDF was modified. This establishes text equivalence; it does
not claim byte or pixel identity between the two compiled PDFs.

Independent checks against published aggregates confirmed:

- All 402 published asset hashes and 46 analysis/exporter source hashes.
- All 112 numeric rows in ten table fragments against the V6 PDF.
- Main RQ comparison counts, transition identities and the 16.3% maximum
  changed-transition accuracy.
- All 240 trajectory/no-time subgroup comparisons and 20 pooled TVD comparisons.
- Structural-correlation medians and the self-trajectory count summaries.
- All 25 numbered equation destinations and 409 valid named PDF destinations.

This review introduced no change to statistical logic, estimates, manuscript
prose, formulas or figure files. No LLM inference, respondent scoring or model
fitting was repeated. Prompt-block whitespace was left as an optional layout
choice. The V6 review identified no mandatory content correction.

The exact PDF is retained in the private manuscript project at
`submission/v6_20260915/Thesis_V6_Final.pdf` and in the local delivery folder.
This public directory records its checksum and relationship to the result
archive; it does not publish private manuscript or respondent files.
Freezing a review version does not represent formal submission to the university.

See [version_record.json](version_record.json),
[aggregate_verification.json](aggregate_verification.json),
[font_aware_pdf_comparison.json](font_aware_pdf_comparison.json),
[pdf_table_row_checks.json](pdf_table_row_checks.json), and
[pdf_integrity.json](pdf_integrity.json) for the checks and provenance.

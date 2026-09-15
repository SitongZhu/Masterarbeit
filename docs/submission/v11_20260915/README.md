# Final V11 manuscript and release record

The final reviewed V11 thesis corresponds to
[`results-v11-2026-09-15`](https://github.com/SitongZhu/Masterarbeit/releases/tag/results-v11-2026-09-15). Use this release and its `results/recomputed/` assets for final
figures and numbers. The [numerical reference](../../V11_RESULTS.md) specifies
accuracy values, false-persistence ranges, sample denominators and baseline names.

| File | Pages | SHA-256 |
| --- | ---: | --- |
| Reviewed V11 download (`Thesis_V11_Reviewed.pdf`) | 87 | `ba2e58153de191d8d87e71225c472574a77095164f0d63f60a1a5d80f0588e7d` |
| Release-linked final PDF (`Thesis_V11_Release_Aligned.pdf`) | 87 | `72553677a7b3479ac7d53920f7103a37fec392cc643fb3cc25caa6f113ef2fa8` |

The downloaded V11 and the previous local build have identical font-decoded
normalized text on all 87 pages. The final release-linked build changes only
the replication paragraph on PDF page 40 (printed page 35); it points to this
fixed release and explains PDF checksums. The other 86 pages retain identical
extracted text. The framework PDF's bytes are synchronized with the public
asset, with identical rendering. Numerical results, tables and figure values are unchanged.

The release-linked manuscript source commit is `5eb03139bfa28e47a47dcdd22b064209e5510611`.
The fixed tag identifies the public source commit. `V11_RELEASE_MANIFEST.json`
in the release records that commit and the exact hashes of both ZIP attachments;
`SHA256SUMS.txt` also covers that manifest. This avoids equating a mutable main
branch or a historical PDF hash with the final reviewed version.

## Verification records

- [Version identifiers and scope](version_record.json)
- [87-page font-aware comparison](font_aware_pdf_comparison.json)
- [Final manuscript integrity and change scope](manuscript_verification.json)
- [112 numeric table-row checks](pdf_table_row_checks.json)
- [Independent aggregate checks against reviewed V11](aggregate_verification.json)
- [Same checks against the release-linked PDF](release_pdf_aggregate_verification.json)
- [35 figure-file mappings](figure_mapping.json) and [ten table-file mappings](table_mapping.json)
- [Aggregate replay](aggregate_replay_audit.json) and [35 rendered-figure comparisons](rendered_figure_verification.json)
- [All attachments of the historical fixed release](historical_release_verification.json)

All 402 result-asset hashes and 47 analysis/exporter source hashes pass.
The source hashes identify the maintained V11 implementation; the statistical
result lineage is separately recorded in `results/manifest.json`. Public replay
and aggregate audits do not rerun LLM inference, respondent scoring or statistical fitting.
See [release verification](../../RESULTS_RELEASE.md) for full coverage and limits.

Both exact PDFs are retained in the private manuscript project under
`submission/v11_20260915/`. This public directory contains metadata and aggregate
verification records, without the private full manuscript or respondent data.
The V6 record and earlier releases remain historical. Version freezing does not
represent formal submission to the university.

# Source release preparation

Prepared from the thesis workspace on 2026-09-11. Main prompt builders,
join/cleaning logic, evaluation formulas, and prior-manipulation logic are
preserved. German prompt wording, outcome coding, wave selections, and random
seeds are unchanged.

Packaging changes:

- Added setup instructions, synthetic checks, interface examples, and data exclusions.
- Replaced the local manuscript build with `run_03_full_evaluation.R`, retaining
  its analysis stage order and removing PDF compilation and local executable fallbacks.
- Redirected manuscript figure and LaTeX exports into `code/outputs/evaluation/`.
- Removed trailing whitespace from blank/comment lines in four prompt builders;
  their parsed R expressions and prompt strings are unchanged.
- Replaced the setup checker so a source-only checkout can initialize empty data directories.
- Excluded historical before/after comparison utilities, heatmap-repair scripts,
  the PowerShell figure duplicate, old data-exploration scripts, and manuscript editing tools.
- Excluded all research data, real prompts, generations, results, and logs.

`source_manifest.json` records source-file hashes and per-file packaging changes.
It refers to paths relative to the original workspace and contains no machine paths.
No numerical result should be inferred from the synthetic checks.

Data-availability update: added official GESIS study links and version DOIs,
documented respondent-level output fields, distinguished runtime caches from
research intermediates, and retained the source-only public release policy.
No raw data or real respondent records were added to the public ZIP.

Repository integration: the prepared code replaces the legacy task3 experiment
tree in `SitongZhu/Masterarbeit`. Prior commits are preserved. See
[REPOSITORY_MIGRATION.md](REPOSITORY_MIGRATION.md) for the removed categories
and the distinction between current-tree cleanup and historical removal.

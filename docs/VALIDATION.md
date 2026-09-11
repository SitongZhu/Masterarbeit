# Release validation

Checked on 2026-09-11 with R 4.3.2 and Python 3.12.4.

| Check | Result |
| --- | --- |
| R syntax | All 48 packaged R files parsed |
| Python syntax | Both evaluation Python files parsed |
| Setup on a source-only directory | Required folders initialized; R packages available |
| Main prompt construction | Actual four builders generated 116 JSON files from invented `.dta` records |
| Main preparation and accuracy | All four task variants passed joins, grouped cleaning, parsing, and accuracy checks |
| Designated lag | Missing preceding-wave generation retained the correct human prior and a missing model prior |
| Manipulated prior | 12 task/condition combinations, 264 predictions, and 176 correct/manipulated pairs passed |
| Prior invariants | Correct prompts unchanged; only prior text altered; shuffling preserves margins; incorrect values differ; seeds reproduce results |
| Relocated exports | Python publication exporters and two redirected R exporters ran against local archived summary tables |
| Output containment | Export checks wrote 56 PNGs, one PDF, and nine LaTeX files inside a temporary evaluation directory |
| Source preservation | Original source hashes verified; five export scripts have path/synchronization changes; four prompt files have whitespace-only formatting changes |

The synthetic tests deliberately include an invalid prediction and a missing
preceding-wave generation. They check the existing difference between grouped
cleaning (unparseable rows removed) and original-scale parsing (unparseable
predictions remain in the accuracy denominator).

The export check reused existing local result tables and did not refit models.
Temporary export artifacts and real data are not included in the release.
The synthetic tests are included and can be rerun using the root README commands.
Some installed R packages report that they were built under R 4.3.3; the checks
completed under R 4.3.2. The validation subprocesses used a Windows UTF-8 locale
(`English_United States.utf8`) to avoid the machine's invalid `C.UTF-8` setting.

The entire statistical pipeline was not rerun on research data, and no new
LLM inference was performed. Reproducing the thesis estimates requires the
separately supplied GLES inputs, matching archived generations, and original
inference configuration where available. This release does not claim that
synthetic tests reproduce the thesis estimates.

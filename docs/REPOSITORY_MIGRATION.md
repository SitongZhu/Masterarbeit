# Repository transition to the thesis code release

The existing `SitongZhu/Masterarbeit` repository is updated in place, preserving
the `main` branch's prior commits. The previous main commit was
`9dfdd8b6137d628212ef80afe0a3594dcf896fbe`.

## Current maintained code

The top-level project now contains the GLES prompt builders, prediction
preparation, thesis evaluation, synthetic tests, and
documentation described in the root README. LLM inference is attributed to
AlignSurvey, and original GLES datasets are linked through GESIS.

## Earlier material

The earlier tree contained 71 tracked files: partial LLaMA-Factory task3
training/inference scripts and evaluation utilities, attitude datasets,
generated predictions and tables, logs, model/tokenizer files, and adapter
checkpoints. Its task3 wrappers refer to `test_attitude` /
`test_attitude_group` and to local cluster paths. They do not establish the
complete historical inference setup for the current GLES thesis runs.

These earlier files have been removed from the current source tree. Existing
commits retain the earlier scripts and configurations for provenance and
recovery. They are not presented as supported entry points for this thesis
release, and the old model/data dependencies are not copied into the new tree.

The new `.gitignore` also excludes the old data, log, model, checkpoint, and
cache locations to reduce accidental reintroduction in future commits.

## Scope of removal

This is a normal commit replacing the current tree, not a history rewrite.
Previously committed datasets, model outputs, logs, and model artifacts remain
retrievable from older commits. `.gitignore` does not remove those objects.
The statement that the new source package excludes respondent data applies to
the current source release, not to a full clone of the repository's history.

No claim is made here that the legacy task3 datasets are GLES records or that
their redistribution permissions have been established. If historical content
requires removal for access-control or licensing reasons, that needs a separate
history-removal procedure and checks of other refs and copies.

# Original LLM generation archive

The thesis uses 580 generation files with 5,685,270 records across four tasks,
five model configurations and four prompt conditions. The
[original file manifest](original_file_manifest.csv) contains file names, row
counts and SHA-256 hashes from the complete input audit.

The actual respondent-linked generations are not publicly downloadable from
this repository at present. A compact local bundle has been prepared with
`id`, `label` and `predict`; the repeated `prompt` field is omitted. Original
generated answer strings remain unchanged. The bundle comprises twenty ZIP
archives, one per task and model, plus a file-level verification manifest.
The twenty archives total 36,896,213 bytes (about 36.9 MB), compared with
14,749,842,003 bytes in the original files. Decompressed compact JSONL totals
397,409,710 bytes. All 580 restored files pass the maintained input audit against
the original prompt manifests, covering every one of the 5,685,270 records.

Public release of these individual records is awaiting a license or written
authorization covering redistribution. The current JSONL contains original
survey reference answers and identifiers; generated responses can also repeat
survey-derived information. This is separate from publishing aggregate figures.
See [data availability](../../docs/DATA_AVAILABILITY.md).

An authorized recipient who has the bundle can restore it with:

```sh
python tools/restore_generation_bundle.py --bundle-dir PATH_TO_BUNDLE
```

Run this from the repository root. The [replication guide](../../docs/REPRODUCING_RESULTS.md)
describes the official GLES inputs and complete evaluation commands. Saved model
answers can be reanalyzed without loading a model checkpoint.

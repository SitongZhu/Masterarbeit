"""Adversarial manifest checks and an actual small archive round trip."""
from pathlib import Path
from contextlib import redirect_stdout
import copy
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from unittest.mock import patch
import zipfile

path = Path(__file__).resolve().parents[1] / "tools/restore_generation_bundle.py"
spec = importlib.util.spec_from_file_location("restore_bundle", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RestoreBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle, self.code = self.root / "bundle", self.root / "code"
        self.bundle.mkdir()
        self.members = {"data/llm_outputs/outcome/test/a.jsonl": b'{"id":1}\n',
                        "data/llm_outputs/outcome/test/b.jsonl": b'{"id":2}\n{"id":3}\n'}
        self.archive = self.bundle / "test.zip"
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name, content in self.members.items():
                archive.writestr(name, content)
        self.manifest = dict(total_files=2, total_records=3,
            archives=[dict(file="test.zip", sha256=module.digest(self.archive), records=3)],
            files=[dict(path=name, archive="test.zip", records=content.count(b"\n"),
                        sha256=hashlib.sha256(content).hexdigest())
                   for name, content in self.members.items()])
        self.addCleanup(patch.stopall)
        patch.object(module, "EXPECTED_FILES", 2).start()
        patch.object(module, "EXPECTED_RECORDS", 3).start()

    def restore(self, manifest=None):
        (self.bundle / "generation_bundle_manifest.json").write_text(
            json.dumps(self.manifest if manifest is None else manifest), encoding="utf-8")
        output = io.StringIO()
        with redirect_stdout(output):
            module.restore(self.bundle, self.code)
        return output.getvalue()

    def test_round_trip_and_idempotent_restore(self):
        for _ in range(2):
            self.assertIn("Restored and verified 2 generation files and 3 records", self.restore())
            for name, content in self.members.items():
                self.assertEqual((self.code / name).read_bytes(), content)

    def test_missing_or_extra_archive_references(self):
        for archives in [[], self.manifest["archives"] + [dict(file="unused.zip")]]:
            manifest = copy.deepcopy(self.manifest)
            manifest["archives"] = archives
            with self.assertRaisesRegex(ValueError, "referenced archives"):
                self.restore(manifest)
            self.assertFalse(self.code.exists())

    def test_duplicate_archives_and_paths(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["archives"] *= 2
        with self.assertRaisesRegex(ValueError, "Duplicate archive"):
            self.restore(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest["files"].append(manifest["files"][0])
        with self.assertRaisesRegex(ValueError, "Duplicate bundle paths"):
            self.restore(manifest)

    def test_metadata_record_totals(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["files"][0]["records"] += 1
        with self.assertRaisesRegex(ValueError, "Per-file record counts"):
            self.restore(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest["archives"][0]["records"] += 1
        with self.assertRaisesRegex(ValueError, "Archive record count"):
            self.restore(manifest)

    def test_actual_file_counts_override_consistent_but_false_metadata(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["files"][0]["records"] = 2
        manifest["files"][1]["records"] = 1
        with self.assertRaisesRegex(ValueError, "Restored record count"):
            self.restore(manifest)

    def test_corrupt_archives_and_existing_files(self):
        original = self.archive.read_bytes()
        self.archive.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "Archive checksum"):
            self.restore()
        self.assertFalse(self.code.exists())
        self.archive.write_bytes(original)
        target = self.code / next(iter(self.members))
        target.parent.mkdir(parents=True)
        target.write_bytes(b"keep this file")
        with self.assertRaisesRegex(ValueError, "Existing file differs"):
            self.restore()
        self.assertEqual(target.read_bytes(), b"keep this file")

    def test_unsafe_manifest_path_rejected_before_writing(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["files"][0]["path"] = "data/llm_outputs/outcome/../../escape.jsonl"
        with self.assertRaisesRegex(ValueError, "Unsafe bundle path"):
            self.restore(manifest)
        self.assertFalse(self.code.exists())

    def test_final_hash_verification_catches_post_extraction_change(self):
        original = Path.rename
        def tamper(source, target):
            result = original(source, target)
            target.write_bytes(b"changed after extraction")
            return result
        with patch.object(Path, "rename", tamper):
            with self.assertRaisesRegex(ValueError, "Restored file missing or checksum"):
                self.restore()


if __name__ == "__main__":
    unittest.main()

"""Small adversarial checks for complete generation coverage."""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / "code/03_evaluation/scripts/audit_generation_inputs.py"
spec = importlib.util.spec_from_file_location("audit", path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class GenerationContractTests(unittest.TestCase):
    def test_missing_duplicate_and_mislabeled_records(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "predictions.jsonl"
            records = [{"id": 1, "label": "A", "predict": "A"},
                       {"id": 2, "label": "B", "predict": None}]
            def write(rows):
                path.write_text("\n".join(json.dumps(row) for row in rows)+"\n", encoding="utf-8")
            write(records)
            self.assertEqual(audit.validate_generation(path, {"1": "A", "2": "B"})[0], 2)
            write(records[:1])
            with self.assertRaisesRegex(ValueError, "no output"):
                audit.validate_generation(path, {"1": "A", "2": "B"})
            write(records+records[:1])
            with self.assertRaisesRegex(ValueError, "duplicate"):
                audit.validate_generation(path, {"1": "A", "2": "B"})
            write(records)
            with self.assertRaisesRegex(ValueError, "reference label"):
                audit.validate_generation(path, {"1": "B", "2": "B"})

    def test_entirely_missing_design_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(ValueError, "Generation audit failed"):
                audit.audit(Path(temporary), files_only=True)


if __name__ == "__main__":
    unittest.main()

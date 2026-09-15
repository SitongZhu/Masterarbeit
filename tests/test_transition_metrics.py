"""Dynamic metrics must keep undefined conditional ratios missing."""
from pathlib import Path
import importlib.util
import unittest

import numpy as np
import pandas as pd

path = Path(__file__).resolve().parents[1] / "code/03_evaluation/scripts/build_thesis_result_tables.py"
spec = importlib.util.spec_from_file_location("tables", path)
tables = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tables)


class TransitionMetricsTests(unittest.TestCase):
    def metrics(self, previous, actual, predicted):
        return tables.transition_metrics(pd.DataFrame(dict(
            vorwelle_label_cat=previous, label_cat=actual, predict_cat=predicted)))

    def test_all_stable(self):
        result = self.metrics(["1", "2"], ["1", "2"], ["1", "1"])
        self.assertEqual(result["stable_n"], 2)
        self.assertEqual(result["stable_accuracy"], .5)
        self.assertEqual(result["trajectory_accuracy"], .5)
        for name in ["changed_accuracy", "stable_change_gap", "ccr", "dccr", "false_persistence"]:
            self.assertTrue(np.isnan(result[name]), name)

    def test_all_changed(self):
        result = self.metrics(["1", "2"], ["2", "3"], ["2", "1"])
        self.assertEqual(result["changed_n"], 2)
        self.assertTrue(np.isnan(result["stable_accuracy"]))
        self.assertEqual(result["changed_accuracy"], .5)
        self.assertEqual(result["ccr"], 1)
        self.assertEqual(result["cda"], .5)

    def test_changed_predictions_unparsed(self):
        result = self.metrics(["1", "1"], ["1", "2"], ["1", None])
        self.assertEqual(result["changed_n"], 1)
        self.assertEqual(result["parsed_changed_n"], 0)
        self.assertEqual(result["changed_accuracy"], 0)
        self.assertEqual(result["trajectory_accuracy"], .5)
        self.assertTrue(np.isnan(result["ccr"]))

    def test_all_unparsed_and_empty(self):
        result = self.metrics(["1", "1"], ["1", "2"], [None, None])
        self.assertEqual(result["trajectory_accuracy"], 0)
        self.assertEqual(result["parsed_n"], 0)
        self.assertTrue(np.isnan(result["previous_agreement"]))
        self.assertTrue(np.isnan(result["correct_stable_share"]))
        result = self.metrics([], [], [])
        self.assertEqual(result["n"], 0)
        for name in ["trajectory_accuracy", "stable_share", "ccr", "cda", "dccr"]:
            self.assertTrue(np.isnan(result[name]), name)

    def test_changes_never_captured(self):
        result = self.metrics(["1", "1"], ["1", "2"], ["1", "1"])
        self.assertEqual(result["false_persistence"], 1)
        self.assertEqual(result["ccr"], 0)
        self.assertEqual(result["dccr"], 0)
        self.assertTrue(np.isnan(result["cda"]))

    def test_mixed_ordered_categories(self):
        result = self.metrics(["Links", "Links", "Rechts", "Neutral"],
                              ["Links", "Rechts", "Links", "Neutral"],
                              ["Links", "Neutral", "Links", None])
        self.assertEqual(result["trajectory_accuracy"], .5)
        self.assertEqual(result["stable_accuracy"], .5)
        self.assertEqual(result["changed_accuracy"], .5)
        self.assertEqual(result["correct_stable_share"], .5)
        self.assertEqual(result["ccr"], 1)
        self.assertEqual(result["cda"], 1)
        self.assertEqual(result["dccr"], 1)


if __name__ == "__main__":
    unittest.main()

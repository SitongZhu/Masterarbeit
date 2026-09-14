"""Check statistical identities, output coverage, and the supplied thesis tables."""
from pathlib import Path
import argparse
import json
import re
import numpy as np
import pandas as pd

CODE = Path(__file__).resolve().parents[2]
EVAL = CODE / "outputs/evaluation"
REFERENCE = CODE.parent / "tests/reference/thesis_20260914.json"


def same_values(a, b, tolerance=1e-12):
    return bool(np.allclose(a, b, rtol=0, atol=tolerance, equal_nan=True))


def audit(require_reference=False):
    rq1 = pd.read_csv(EVAL / "manuscript/tables/rq1_ordinal_covariates_only_comparison.csv")
    rq2 = pd.read_csv(EVAL / "manuscript/tables/rq2_ordinal_prior_state_comparison.csv")
    for table in [rq1, rq2]:
        assert len(table) == 20 and not table.duplicated(["Task", "Model"]).any()
        assert table.n_total.gt(0).all()
    assert same_values(rq1.prompt_minus_ordinal, rq1.accuracy_prompt-rq1.accuracy_ordinal)
    assert same_values(rq2.trajectory_minus_cf, rq2.accuracy_trajectory-rq2.accuracy_cf)
    assert same_values(rq2.trajectory_minus_ordinal, rq2.accuracy_trajectory-rq2.accuracy_ordinal)
    transition = pd.read_csv(EVAL / "publication/tables/transition_diagnostics_exact.csv")
    assert len(transition) == 20
    assert same_values(transition.stable_n+transition.changed_n, transition.n)
    assert same_values(transition.stable_share, transition.stable_n/transition.n)
    assert same_values(transition.trajectory_accuracy,
                       transition.stable_share*transition.stable_accuracy+
                       (1-transition.stable_share)*transition.changed_accuracy)
    assert same_values(transition.false_persistence+transition.ccr, np.ones(20))
    assert same_values(transition.dccr, transition.ccr*transition.cda.fillna(0))
    assert (transition.parsed_n <= transition.n).all()
    spec = pd.read_csv(EVAL / "publication/tables/matched_specification_comparison.csv")
    assert len(spec) == 40 and (spec.joint_N <= spec.primary_N).all()
    distances = pd.read_csv(EVAL / "publication/tables/matched_distance_metrics.csv")
    assert len(distances) == 20 and (distances.parsed_N <= distances.primary_N).all()
    diagnostics = pd.read_csv(EVAL / "tables/ordinal_probit_diagnostics_all.csv")
    fitted = diagnostics[diagnostics.ordinal_model.ne("not_estimated")]
    assert len(fitted) == 48
    assert fitted.convergence_code.eq(0).all(), "Ordinal fits did not all converge"
    assert fitted.thresholds_strictly_ordered.eq(True).all()
    assert fitted.probability_rows_valid.eq(True).all()
    assert fitted.max_probability_sum_error.le(1e-10).all()
    multinomial_fits = 0
    for variant in ["1290", "1290_original_scale", "1500", "1500_original_scale"]:
        for prefix in ["covariates_only", "lag_covariate"]:
            path = EVAL / f"analysis_{variant}/statistical_baselines/{prefix}_multinomial_logit_predictions.csv"
            predictions = pd.read_csv(path, usecols=[
                "wave", "statistical_model", "statistical_pred_cat", "fit_convergence"])
            estimated = predictions[predictions.statistical_model.ne("not_estimated")]
            assert estimated.statistical_pred_cat.notna().all(), "Missing fitted multinomial predictions"
            fits = estimated[["wave", "fit_convergence"]].drop_duplicates()
            assert not fits.wave.duplicated().any()
            assert fits.fit_convergence.eq(0).all(), "Final multinomial fits did not all converge"
            multinomial_fits += len(fits)
    assert multinomial_fits == 48
    structural = pd.read_csv(EVAL / "tables/structural_fidelity_stratum_metrics.csv")
    assert len(structural) == 40
    assert structural.ordinal_human_convergence.eq(0).all()
    assert structural.ordinal_llm_convergence.eq(0).all()
    tvd_checks = []
    for variant in ["1290", "1290_original_scale", "1500", "1500_original_scale"]:
        base = EVAL / f"analysis_{variant}/aggregate_prediction"
        distribution = pd.read_csv(base / "aggregate_distribution_overall.csv")
        pivot = distribution.pivot(index=["model", "prompt_variant", "category"], columns="source", values="proportion")
        recalculated = (pivot.LLM-pivot.Human).abs().groupby(["model", "prompt_variant"]).sum()*.5
        stored = pd.read_csv(base / "aggregate_distribution_distance_overall.csv").set_index(
            ["model", "prompt_variant"]).total_variation_distance
        assert same_values(recalculated.sort_index(), stored.sort_index())
        tvd_checks.append(variant)
    fixture = json.loads(REFERENCE.read_text(encoding="utf-8"))
    missing, differences = [], []
    def normalized(value):
        return re.sub(r"\s+", " ", value).strip()
    for name, reference in fixture["tables"].items():
        path = EVAL / "publication/latex" / name
        if not path.is_file():
            missing.append("latex/"+name)
        elif normalized(path.read_text(encoding="utf-8")) != normalized(reference):
            differences.append(name)
    for relative in fixture["figures"]:
        if not (EVAL / "publication/figures" / relative).is_file():
            missing.append("figures/"+relative)
    result = dict(status="failed" if missing else "passed", primary_comparisons=40,
                  transition_configurations=20, ordinal_fits=48, multinomial_fits=multinomial_fits,
                  structural_metric_rows=40,
                  pooled_tvd_tasks_verified=tvd_checks, required_tables=len(fixture["tables"]),
                  required_figures=len(fixture["figures"]), missing_outputs=missing,
                  thesis_table_differences=differences, matches_thesis_tables=not missing and not differences,
                  source_pdf_sha256=fixture["source_pdf_sha256"])
    destination = EVAL / "publication/result_audit.json"
    destination.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2), flush=True)
    if missing:
        raise RuntimeError("The full build has missing thesis artifacts")
    if require_reference and differences:
        raise RuntimeError("Computed tables differ from the supplied thesis; see result_audit.json")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--compare-thesis", action="store_true")
    args = parser.parse_args()
    audit(require_reference=args.compare_thesis)

from pathlib import Path
import hashlib
import json
import re
import numpy as np
import pandas as pd
import argparse

REPO = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description="Check final V11 claims from public aggregates")
parser.add_argument('--output-dir', type=Path, default=REPO/'code/outputs/v11_audit')
parser.add_argument('--pdf', type=Path, help='Optional reviewed/final PDF; requires PyMuPDF')
args = parser.parse_args()
OUT = args.output_dir.resolve()
OUT.mkdir(parents=True, exist_ok=True)
AGG = REPO / 'results/recomputed/aggregate_inputs'
manifest = json.loads((REPO / 'results/manifest.json').read_text(encoding='utf-8'))
fixture = json.loads((REPO/'tests/reference/thesis_current.json').read_text(encoding='utf-8'))
assert manifest['revision'] == fixture['release_tag'] == 'results-v11-2026-09-15'
assert manifest['source_pdf_sha256'] == fixture['source_pdf_sha256']
assert manifest['reviewed_v11_pdf_sha256'] == fixture['reviewed_v11_pdf_sha256']
assert set(manifest['required_tables']) == set(fixture['tables'])
for name, expected in fixture['tables'].items():
    assert (REPO/'results/recomputed/latex'/name).read_text(encoding='utf-8').split() == expected.split(), name
for item in manifest['files']:
    assert hashlib.sha256((REPO / 'results' / item['path']).read_bytes()).hexdigest() == item['sha256'], item['path']
for item in manifest['exporter_sources'] + manifest['analysis_sources']:
    assert hashlib.sha256((REPO / item['path']).read_bytes()).hexdigest() == item['sha256'], item['path']

rq1 = pd.read_csv(AGG / 'manuscript/tables/rq1_ordinal_covariates_only_comparison.csv')
rq2 = pd.read_csv(AGG / 'manuscript/tables/rq2_ordinal_prior_state_comparison.csv')
gain = pd.read_csv(AGG / 'common_sample_accuracy/runs/run_manuscript/trajectory_vs_best_nontrajectory_common_sample.csv')
transition = pd.read_csv(AGG / 'publication/tables/transition_diagnostics_exact.csv')
spec = pd.read_csv(AGG / 'publication/tables/matched_specification_comparison.csv')
best = rq2.sort_values(['accuracy_trajectory','Model'],ascending=[False,True]).groupby('Task',sort=False).head(1)
selected = spec[spec.Comparison.eq('RQ2')].merge(best[['Task','Model']],on=['Task','Model'],validate='one_to_one')
assert len(rq1) == len(rq2) == len(gain) == len(transition) == 20
assert rq1.baseline_specification.eq('expanding_window_ordinal_probit').all()
assert rq2.baseline_specification.eq('expanding_window_ordinal_probit').all()
assert rq1.accuracy_ordinal.gt(rq1.accuracy_prompt).sum() == 20
assert gain.trajectory_minus_best_non.gt(0).sum() == 20
assert rq2.accuracy_trajectory.gt(rq2.accuracy_majority).sum() == 20
assert rq2.accuracy_trajectory.gt(rq2.accuracy_ordinal).sum() == 8
assert rq2.accuracy_trajectory.lt(rq2.accuracy_cf).sum() == 17
assert rq2.accuracy_trajectory.eq(rq2.accuracy_cf).sum() == 1
assert selected.llm_minus_multinomial.lt(0).sum() == 3
assert [round(100*x,1) for x in [gain.trajectory_minus_best_non.min(),gain.trajectory_minus_best_non.max()]] == [11.9,52.6]
positive_cf = 100*(rq2.accuracy_trajectory-rq2.accuracy_cf)
assert positive_cf.gt(0).sum() == 2 and positive_cf.max() < .01

errors = {}
def equal(name,actual,expected):
    actual,expected = np.asarray(actual,dtype=float),np.asarray(expected,dtype=float)
    assert np.allclose(actual,expected,atol=1e-12,rtol=0,equal_nan=True), name
    errors[name] = float(np.nanmax(np.abs(actual-expected)))

equal('stable_plus_changing',transition.n,transition.stable_n+transition.changed_n)
equal('stable_share',transition.stable_share,transition.stable_n/transition.n)
equal('accuracy_decomposition',transition.trajectory_accuracy,
      (transition.stable_n*transition.stable_accuracy+transition.changed_n*transition.changed_accuracy)/transition.n)
equal('stable_change_gap',transition.stable_change_gap,transition.stable_accuracy-transition.changed_accuracy)
equal('CCR_from_counts',transition.ccr,transition.captured_n/transition.parsed_changed_n)
equal('FP_from_counts',transition.false_persistence,1-transition.captured_n/transition.parsed_changed_n)
equal('CDA_from_counts',transition.cda,transition.direction_aligned_n/transition.captured_n.replace(0,np.nan))
equal('DCCR_from_counts',transition.dccr,transition.direction_aligned_n/transition.parsed_changed_n)
equal('DCCR_product',transition.dccr,transition.ccr*transition.cda.fillna(0))
stable_correct = np.rint(transition.stable_n*transition.stable_accuracy)
equal('PSA_from_counts',transition.previous_agreement,
      (stable_correct+transition.parsed_changed_n-transition.captured_n)/transition.parsed_n)
equal('stable_contribution',transition.correct_stable_share,
      stable_correct/(transition.trajectory_accuracy*transition.n))
assert transition.stable_accuracy.gt(transition.changed_accuracy).all()
assert transition.correct_stable_share.min() > .75
assert round(100*transition.changed_accuracy.max(),1) == 16.3
assert round(100*transition.ccr.max(),1) == 50.7
assert round(100*transition.dccr.max(),1) == 36.5
grouped = transition[transition.Task.str.endswith('grouped')]
assert [round(100*x,1) for x in [grouped.false_persistence.min(),grouped.false_persistence.max()]] == [76.3,100.0]

tvd_results, subgroup_results, self_results = [], [], []
best_groups, worst_groups = [], []
for variant in ['1290','1290_original_scale','1500','1500_original_scale']:
    base = AGG / f'analysis_{variant}'
    distribution = pd.read_csv(base / 'aggregate_prediction/aggregate_distribution_overall.csv')
    equal('category_proportions_'+variant,distribution.proportion,distribution.n_category/distribution.n_total)
    group_keys = ['model','prompt_variant','source']
    totals = distribution.groupby(group_keys).agg(n=('n_category','sum'),expected=('n_total','first'))
    equal('category_totals_'+variant,totals.n,totals.expected)
    distribution['recomputed_proportion'] = distribution.n_category/distribution.groupby(group_keys).n_category.transform('sum')
    wide = distribution.pivot(index=['model','prompt_variant','category'],columns='source',values='recomputed_proportion')
    tvd = (wide.LLM-wide.Human).abs().groupby(['model','prompt_variant']).sum()*.5
    stored = pd.read_csv(base / 'aggregate_prediction/aggregate_distribution_distance_overall.csv').set_index(['model','prompt_variant']).total_variation_distance
    equal('TVD_from_counts_'+variant,tvd.sort_index(),stored.sort_index())
    pair = tvd.unstack('prompt_variant')
    assert len(pair) == 5 and pair.trajectory.lt(pair.baseline_notime).all()
    tvd_results.extend(dict(variant=variant,model=m,no_time=float(row.baseline_notime),trajectory=float(row.trajectory)) for m,row in pair.iterrows())

    sub = pd.read_csv(base / 'subgroup_analysis/subgroup_correctness_overall.csv')
    assert len(sub) == 240 and sub.n.ge(30).all()
    equal('subgroup_accuracy_'+variant,sub.accuracy,sub.n_correct/sub.n)
    keys = ['model','sex','income_band','education_band']
    pair = sub.pivot(index=keys,columns='prompt_variant',values='accuracy')
    assert len(pair) == 60 and pair.trajectory.gt(pair.baseline_notime).all()
    subgroup_results.append(dict(variant=variant,comparisons=len(pair),all_trajectory_higher=True,
                                 minimum_gain=float((pair.trajectory-pair.baseline_notime).min())))
    for _,stratum in sub.groupby(['model','prompt_variant']):
        groups = list(zip(stratum.sex,stratum.income_band,stratum.education_band))
        best_groups.append({g for g,a in zip(groups,stratum.accuracy) if abs(a-stratum.accuracy.max())<1e-12})
        worst_groups.append({g for g,a in zip(groups,stratum.accuracy) if abs(a-stratum.accuracy.min())<1e-12})

    by_model = {}
    for path in sorted((base/'trajectory_heatmap/self_trajectory').glob('trajectory_delta_grid_*.csv')):
        model = re.sub(r'^trajectory_delta_grid_ww\d+_','',path.stem)
        frame = pd.read_csv(path)
        changed = frame.delta_H.ne(0)
        failure = (np.sign(frame.delta_H)*np.sign(frame.delta_L)).le(0)
        counts = by_model.setdefault(model,[0,0,0])
        counts[0] += int(frame.loc[changed,'count'].sum())
        counts[1] += int(frame.loc[changed & failure,'count'].sum())
        counts[2] += 1
    assert len(by_model) == 5
    for model,(n,failures,waves) in by_model.items():
        assert n > 0
        self_results.append(dict(variant=variant,model=model,changed_n=n,unchanged_or_opposite_n=failures,
                                 unchanged_or_opposite_share=failures/n,waves=waves))
assert len(tvd_results) == 20
assert sum(x['comparisons'] for x in subgroup_results) == 240
assert not set.intersection(*best_groups) and not set.intersection(*worst_groups)

structural = pd.read_csv(AGG/'tables/structural_fidelity_stratum_metrics.csv')
medians = structural[structural.method.eq('Ordinal probit')].groupby(['task','prompt']).coefficient_correlation.median()
assert [round(float(x),2) for x in medians] == [.62,.93,-.12,.37]

row_checks = {}
if args.pdf:
    import pymupdf
    assert hashlib.sha256(args.pdf.read_bytes()).hexdigest() in {
        manifest['source_pdf_sha256'], manifest['reviewed_v11_pdf_sha256']
    }, 'PDF does not match either recorded V11 checksum'
    pdf = pymupdf.open(args.pdf)
    fixture = json.loads((REPO/'tests/reference/thesis_current.json').read_text())
    def tokens(text):
        return re.findall(r'[+-]?\d+(?:[.,]\d+)*',text.replace('\u2212','-').replace('\u2013',' ').replace('--',' '))
    pdf_tokens = [tokens(p.get_text()) for p in pdf]
    row_checks = {}
    for name,table in fixture['tables'].items():
        rows = []
        for i,line in enumerate(table.splitlines(),1):
            if '&' not in line: continue
            wanted = tokens(line)
            matches = [p+1 for p,actual in enumerate(pdf_tokens)
                       if any(actual[j:j+len(wanted)] == wanted for j in range(len(actual)-len(wanted)+1))]
            assert matches,(name,i)
            rows.append(dict(source_row=i,pdf_pages=matches,numeric_tokens=wanted))
        row_checks[name] = rows
    assert sum(map(len,row_checks.values())) == 112
    (OUT/'pdf_table_row_checks.json').write_text(json.dumps(row_checks,indent=2)+'\n')
report = dict(status='passed',mode='independent_checks_from_published_aggregates',new_inference=False,
              models_refitted=False,prediction_records_rescored=False,
              archive_files_verified=len(manifest['files']),source_hashes_verified=len(manifest['exporter_sources'])+len(manifest['analysis_sources']),
              pdf_table_fragments=len(row_checks),pdf_numeric_rows_matched=sum(map(len,row_checks.values())),primary_comparisons=40,
              grouped_false_persistence_range=[float(grouped.false_persistence.min()),float(grouped.false_persistence.max())],
              all_scale_false_persistence_range=[float(transition.false_persistence.min()),float(transition.false_persistence.max())],
              selected_no_time=rq1.sort_values('accuracy_prompt',ascending=False).groupby('Task',sort=False).head(1)[['Task','model','n_total','accuracy_prompt','accuracy_ordinal']].to_dict(orient='records'),
              selected_trajectory=best[['Task','model','n_total','accuracy_trajectory','accuracy_cf','accuracy_ordinal']].to_dict(orient='records'),
              trajectory_gain_pp=[float(100*gain.trajectory_minus_best_non.min()),float(100*gain.trajectory_minus_best_non.max())],
              positive_cf_gains_pp=positive_cf[positive_cf.gt(0)].tolist(),identity_max_errors=errors,
              maximum_changed_accuracy=float(transition.changed_accuracy.max()),minimum_stable_correct_contribution=float(transition.correct_stable_share.min()),
              maximum_ccr=float(transition.ccr.max()),maximum_dccr=float(transition.dccr.max()),
              tvd_comparisons=tvd_results,subgroup_comparisons=subgroup_results,
              no_universal_best_or_worst_subgroup=True,ordinal_structure_medians=[dict(task=t,prompt=p,value=float(v)) for (t,p),v in medians.items()],
              self_trajectory_comparisons=self_results)
(OUT/'aggregate_verification.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if not isinstance(v,(list,dict))},indent=2))
print('Self-trajectory unchanged/opposite share ranges:')
for grouped in [True,False]:
    values=[r['unchanged_or_opposite_share'] for r in self_results if ('original' not in r['variant'])==grouped]
    print('Grouped' if grouped else 'Original',min(values),max(values))

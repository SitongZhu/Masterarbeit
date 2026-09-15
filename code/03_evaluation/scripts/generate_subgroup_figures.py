"""Render subgroup accuracies using the evaluation's grouping and scoring.

Usage: python generate_subgroup_figures.py --evaluation-dir PATH
PATH contains analysis_1290, analysis_1290_original_scale, analysis_1500,
and analysis_1500_original_scale, each with subgroup_analysis CSV outputs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import numpy as np
import pandas as pd

CODE = Path(__file__).resolve().parents[2]
EVAL = Path(os.environ.get('THESIS_EVALUATION_ROOT', CODE/'outputs/evaluation')).resolve()

MODELS = ['Mistral-7B', 'Qwen2.5-7B (4-bit)', 'Qwen2.5-32B', 'Qwen2.5-72B', 'Llama-3.3-70B']
COLORS = ['#4C78A8', '#F58518', '#54A24B', '#B279A2', '#E45756']
MARKERS = ['o', 's', '^', 'D', 'v']
PROMPTS = [('baseline_notime', 'No-time'), ('baseline', 'Date-bounded'),
           ('tanchored', 'Context-anchored'), ('trajectory', 'Trajectory')]
GROUPS = [(s, i, e) for s in ['weiblich', 'maennlich']
          for i in ['low_income', 'middle_income', 'high_income']
          for e in ['before_university_track', 'university_track_or_higher']]

def model_name(value):
    key = re.sub(r'[^a-z0-9]+', '_', str(value).lower())
    if 'mistral' in key:
        return MODELS[0]
    for size, name in [('7b', MODELS[1]), ('32b', MODELS[2]), ('72b', MODELS[3])]:
        if 'qwen2_5' in key and size in key:
            return name
    if 'llama' in key and '70b' in key:
        return MODELS[4]
    raise ValueError(value)

def render(evaluation_dir, destination, task_id, title):
    fig, axes = plt.subplots(2, 4, figsize=(9, 5.25), sharex=True, sharey=True)
    fig.subplots_adjust(left=.185, right=.978, top=.875, bottom=.155, wspace=.18, hspace=.50)
    labels = [f"{'Female' if s == 'weiblich' else 'Male'} / {i.split('_')[0]} / "
              f"{'HR' if e == 'before_university_track' else 'FA'}" for s, i, e in GROUPS]
    manifest = []
    for row, suffix in enumerate(['', '_original_scale']):
        source = evaluation_dir / f'analysis_{task_id}{suffix}' / 'subgroup_analysis/subgroup_correctness_overall.csv'
        frame = pd.read_csv(source)
        assert set(frame.outcome) == {'correct_prediction'}
        assert (frame.n >= 30).all()
        assert np.allclose(frame.accuracy, frame.n_correct / frame.n, atol=1e-14, rtol=0)
        frame['configuration'] = frame.model.map(model_name)
        frame['group'] = list(zip(frame.sex, frame.income_band, frame.education_band))
        assert set(frame.group) == set(GROUPS)
        assert len(frame) == 240
        assert not frame.duplicated(['configuration', 'prompt_variant', 'group']).any()
        assert set(frame.prompt_variant) == {p[0] for p in PROMPTS}
        ordered = frame.set_index(['configuration', 'prompt_variant', 'sex', 'income_band', 'education_band'])
        plot_count = 0
        for col, (prompt, prompt_title) in enumerate(PROMPTS):
            ax = axes[row, col]
            for group_pair in range(0, 12, 4):
                ax.axhspan(group_pair - .5, min(group_pair + 1.5, 11.5), color='#F2F5F8', zorder=0)
            ax.axhline(5.5, color='#AAB4BF', linewidth=.65, zorder=1)
            for k, model in enumerate(MODELS):
                values = [float(ordered.at[(model, prompt, *g), 'accuracy']) for g in GROUPS]
                ax.scatter(np.array(values)*100, np.arange(12)+(k-2)*.065,
                           color=COLORS[k], marker=MARKERS[k], s=14,
                           edgecolors='white', linewidths=.18, alpha=.95, zorder=3)
                assert np.allclose(ax.collections[-1].get_offsets()[:, 0], np.array(values)*100)
                plot_count += len(values)
            ax.set_title(prompt_title, fontsize=9.6, fontweight='bold', pad=7)
            ax.set_yticks(range(12), labels, fontsize=9.2)
            ax.set_ylim(11.6, -.6)
            ax.set_xlim(-2, 102)
            ax.set_xticks([0, 50, 100], ['0', '50', '100'])
            ax.tick_params(axis='y', length=0, pad=5)
            ax.tick_params(axis='x', labelsize=8.7, labelbottom=True, length=2.5)
            ax.grid(axis='x', color='#D9DEE4', linewidth=.55)
            ax.set_axisbelow(True)
            ax.spines[['top', 'right', 'left']].set_visible(False)
            ax.spines['bottom'].set_color('#B8B8B8')
        assert plot_count == len(frame)
        y = axes[row, 0].get_position().y1 + .059
        fig.text(.014, y, 'Grouped scale' if row == 0 else 'Original scale',
                 fontsize=10.1, fontweight='bold', va='center')
        manifest.append(dict(source=str(source), sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                             source_rows=len(frame), plotted_points=plot_count,
                             accuracy_and_grouping_unchanged=True))
    fig.suptitle(title, fontsize=12, fontweight='bold', y=.995)
    fig.text(.59, .087, 'Exact-match current-state accuracy (%)', ha='center', fontsize=10)
    handles = [Line2D([], [], linestyle='none', marker=m, color=c, markersize=4.5, label=l)
               for m, c, l in zip(MARKERS, COLORS, MODELS)]
    fig.legend(handles=handles, loc='lower center', bbox_to_anchor=(.5, .004),
               ncol=5, frameon=False, fontsize=8.5, handletextpad=.4, columnspacing=1.3)
    fig.canvas.draw()
    # Keep every visible label within the exported vector page.
    bounds = fig.bbox
    for text in fig.findobj(matplotlib.text.Text):
        if text.get_visible() and text.get_text():
            bbox = text.get_window_extent(fig.canvas.get_renderer())
            assert bbox.x0 >= -1 and bbox.y0 >= -1 and bbox.x1 <= bounds.x1+1 and bbox.y1 <= bounds.y1+1, text.get_text()
    destination.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(destination, metadata={'Title': title, 'Creator': 'Archived subgroup accuracy renderer'})
    plt.close(fig)
    return manifest

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evaluation-dir', type=Path, default=EVAL)
    parser.add_argument('--output-dir', type=Path, default=EVAL/'publication/figures/appendix')
    parser.add_argument('--manifest', type=Path, default=EVAL/'publication/subgroup_figure_manifest.json')
    args = parser.parse_args()
    plt.rcParams.update({'font.family':'DejaVu Sans', 'pdf.fonttype':42, 'ps.fonttype':42})
    record = {}
    for task, title, name in [
        ('1290', 'Climate-growth preference', 'F_climate_growth_subgroup_print.pdf'),
        ('1500', 'Left-right self-placement', 'F_left_right_subgroup_print.pdf')]:
        record[name] = render(args.evaluation_dir, args.output_dir/name, task, title)
    if args.manifest:
        args.manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(json.dumps(record), flush=True)

if __name__ == '__main__':
    main()

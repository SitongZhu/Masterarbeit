"""Rebuild the manuscript overview as a vector research figure.

Run with Python and matplotlib. The PDF is written to publication/figures/;
an optional --preview path also saves a PNG for layout review.
"""
from pathlib import Path
import argparse
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

parser = argparse.ArgumentParser()
parser.add_argument('--preview', type=Path)
args = parser.parse_args()
plt.rcParams.update({'font.family': 'DejaVu Sans', 'pdf.fonttype': 42,
                     'ps.fonttype': 42, 'font.size': 7.2})
W, H = 16, 12
fig = plt.figure(figsize=(W / 2.54, H / 2.54))
ax = fig.add_axes([0, 0, 1, 1])
ax.set(xlim=(0, W), ylim=(0, H))
ax.axis('off')
NAVY, BLUE, PALE, LINE = '#183653', '#285778', '#F1F6FA', '#A9BECD'
INK, MUTED = '#20303D', '#405968'
checks = []

def box(x, y, w, h, color='white', edge=LINE):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0,rounding_size=0.08',
                               facecolor=color, edgecolor=edge, linewidth=0.65))

def text(x, y, label, size=7.2, bold=False, color=INK, ha='left', va='top', width=None):
    artist = ax.text(x, y, label, fontsize=size, fontweight='bold' if bold else 'normal',
                     color=color, ha=ha, va=va, linespacing=1.3)
    if width is not None:
        checks.append((artist, width))
    return artist

def heading(y, label, contribution):
    box(0.12, y - 0.28, 15.76, 0.55, NAVY, NAVY)
    text(0.35, y, label, size=9, bold=True, color='white', va='center', width=12.25)
    box(12.85, y - 0.205, 2.82, 0.41, PALE, PALE)
    text(14.26, y, f'Contribution {contribution}', size=7.8, bold=True,
         color=NAVY, ha='center', va='center', width=2.60)

heading(11.60, 'Data and infrastructure', 1)
empirical = [
    ('GLES panel data', 'Linked respondent-wave records'),
    ('Climate-growth and left-right', 'Grouped and original response scales'),
    ('Evaluation design', '4 tasks and 4 prompt conditions'),
]
for i, (title, body) in enumerate(empirical):
    x, w = 0.12 + i * 5.32, 5.12
    box(x, 10.19, w, 0.94, PALE)
    text(x + 0.16, 10.95, title, size=7.5, bold=True, width=w - 0.32)
    text(x + 0.16, 10.58, body, size=6.9, width=w - 0.32)

stages = [
    ('Raw GLES files', 'Selected waves\nand variables'),
    ('Harmonized\nrecords', 'Respondent IDs\nand profiles'),
    ('Condition-specific\nprompts', 'Profile and question\nPrompt information'),
    ('External\ngeneration', 'LLaMA-Factory\nBy configuration'),
    ('Linked evaluation\nrecords', 'Predictions + answers\nParsing and retention'),
]
for i, (title, body) in enumerate(stages):
    x, w = 0.12 + i * 3.225, 2.86
    box(x, 7.98, w, 1.97)
    text(x + 0.16, 9.75, str(i + 1), size=7.5, bold=True, color=BLUE)
    text(x + w / 2, 9.37, title, size=7.1, bold=True, ha='center', width=w - 0.2)
    text(x + w / 2, 8.66, body, size=6.6, ha='center', width=w - 0.18)
    if i < 4:
        ax.add_patch(FancyArrowPatch((x + w + 0.025, 8.92), (x + 3.225 - 0.035, 8.92),
                                    arrowstyle='-|>', mutation_scale=8, color=BLUE, linewidth=0.8))

text(8, 7.73, 'Respondent and wave links connect prompts, outputs, observed answers, and parser outcomes.',
     size=6.8, color=MUTED, ha='center', va='center', width=15.4)
box(0.12, 7.01, 15.76, 0.48, PALE)
text(8, 7.25, 'Mistral-7B  •  Qwen2.5-7B (4-bit)  •  Qwen2.5-32B  •  Qwen2.5-72B  •  Llama-3.3-70B',
     size=7.2, ha='center', va='center', width=15.4)

heading(6.59, 'Evaluation of current states and observed transitions', 2)
cards = [
    ('RQ1  Current-state accuracy', [
        ('Comparison', 'No-time LLM vs.\ncovariates-only ordinal probit'),
        ('Main metric', 'Exact-match accuracy'),
        ('Supplementary comparisons', 'Other non-trajectory prompts\noriginal-scale distance metrics'),
    ]),
    ('RQ2  Prior-state information', [
        ('Prompt comparison', 'Trajectory vs. non-trajectory\nprompts on common records'),
        ('Baseline comparison', 'Modal rule, carry-forward, and\nlag-and-covariates ordinal probit'),
        ('Metrics', 'Exact-match accuracy and gaps\nprior-state agreement'),
    ]),
    ('RQ3  Observed transitions', [
        ('Transition decomposition', 'Stable and changing accuracy\ncontributions to pooled accuracy'),
        ('Change recovery', 'Departure → correct direction\n→ exact current response'),
        ('Diagnostics', 'False persistence\nanchored-change heatmaps'),
    ]),
]
for i, (title, sections) in enumerate(cards):
    x, w = 0.12 + i * 5.32, 5.12
    box(x, 2.07, w, 4.00)
    box(x, 5.47, w, 0.60, PALE)
    text(x + w / 2, 5.77, title, size=7.0, bold=True, ha='center', va='center', width=w - 0.3)
    for j, (label, body) in enumerate(sections):
        y = 5.23 - j * 1.04
        text(x + 0.18, y, label, size=7.1, bold=True, color=BLUE, width=w - 0.36)
        text(x + 0.18, y - 0.35, body, size=7.1, width=w - 0.36)

box(0.12, 0.18, 15.76, 1.60, PALE)
text(0.32, 1.57, 'Supporting diagnostics', size=8.1, bold=True, color=NAVY)
support = [
    ('Distributional fidelity', 'Total variation distance'),
    ('Representational fidelity', 'Intersectional subgroup accuracy'),
    ('Structural fidelity', 'Coefficient alignment'),
    ('Self-trajectory change', 'Changes in successive predictions'),
]
for i, (title, body) in enumerate(support):
    x = 0.32 + i * 3.91
    text(x, 1.14, title, size=7.0, bold=True, width=3.65)
    if i in [1, 3]:
        body = 'Intersectional subgroup\naccuracy' if i == 1 else 'Changes in successive\npredictions'
    text(x, 0.81, body, size=6.8, width=3.65)

fig.canvas.draw()
renderer = fig.canvas.get_renderer()
overflows = []
for artist, width in checks:
    actual = artist.get_window_extent(renderer).width
    allowed = ax.transData.transform((width, 0))[0] - ax.transData.transform((0, 0))[0]
    if actual > allowed + 0.5:
        overflows.append(artist.get_text())
    bounds = artist.get_window_extent(renderer)
    assert bounds.x0 >= 0 and bounds.y0 >= 0 and bounds.x1 <= fig.bbox.width and bounds.y1 <= fig.bbox.height
assert not overflows, f'Text exceeds assigned width: {overflows!r}'
evaluation = Path(os.environ.get('THESIS_EVALUATION_ROOT', Path(__file__).resolve().parents[2]/'outputs/evaluation'))
pdf = evaluation/'publication/figures/longitudinal_framework_overview.pdf'
pdf.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(pdf, metadata={'Title': 'Longitudinal reconstruction and evaluation', 'Author': None})
if args.preview:
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.preview, dpi=220)
print(pdf)

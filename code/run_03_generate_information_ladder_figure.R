# Run only the information ladder figure.
#
# This uses existing evaluation summary tables and does not rerun model fitting.
# Outputs:
# - outputs/evaluation/organized_analysis_pngs/statistical_baselines/information_ladder.png
# - outputs/evaluation/figures/information_ladder.svg
# - outputs/evaluation/figures/information_ladder_data.csv

source(file.path("03_evaluation", "scripts", "generate_information_ladder_figure.R"))

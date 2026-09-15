# Validation environment

The release was checked with R 4.3.2 and Python 3.12.4 on Windows.
`r_packages.tsv` records the installed versions of directly used R packages
in the validation environment; it is an environment record, not an `renv`
lockfile. `setup/install_packages.R` installs missing packages from CRAN and
does not downgrade existing installations.

`svglite` is also required for the information-ladder SVG export. It is included
in both installation and setup checks; its version was recorded during the
2026-09-15 maintenance validation.

`requirements.txt` pins the three Python plotting dependencies to the versions
available during validation: NumPy 2.3.1, pandas 2.3.0, and Matplotlib 3.10.3.
R-only prompt generation and evaluation do not need Python.

The original LLM inference environment is external. No unverified inference
package versions, model revisions, or decoding settings are asserted here.

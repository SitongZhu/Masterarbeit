# Inference attribution

The LLM calling/inference stage uses code from
[AlignSurvey](https://github.com/PiLab-ZJU/AlignSurvey), with LLaMA-Factory
for model execution. Please follow the upstream repository's instructions
and terms for that code and its dependencies. This release does not bundle
AlignSurvey, LLaMA-Factory, model weights, or third-party datasets.

```bibtex
@inproceedings{lin2026alignsurvey,
  title = {{AlignSurvey}: A Comprehensive Benchmark for Human Preferences Alignment in Social Surveys},
  author = {Lin, Chenxi and Yuan, Weikang and Jiang, Zhuoren and Huang, Biao and Zhang, Ruitao and Ge, Jianan and Xu, Yueqian and Yu, Jianxing},
  booktitle = {Proceedings of the AAAI Conference on Artificial Intelligence},
  volume = {40},
  pages = {38908--38916},
  year = {2026},
  doi = {10.1609/aaai.v40i45.41236}
}
```

Upstream references were checked on 2026-09-11. The historical inference
commit and full run configuration are not present in the supplied workspace.
See [INFERENCE.md](INFERENCE.md) for the documented interface and limitations.

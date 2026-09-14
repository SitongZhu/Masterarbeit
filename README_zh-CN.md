# 硕士论文代码：LLM 问卷回答与纵向变化

本仓库对应 2026-09-14 审阅的硕士论文，包含 GLES 数据整理、提示词构建、预测清洗、RQ1–RQ3 分析、统计基线、论文表格和图形导出。

当前维护四项任务：气候保护与经济增长取舍的三组编码和原始 1–7 量表，左右政治立场的三组编码和原始 1–11 量表。气候任务使用波次 10、11、14、15、22、23、25、26；政治立场任务不使用波次 11。每项任务比较 No-time、Date-bounded、Context-anchored、Trajectory 四种提示条件和五个模型配置。

Trajectory 使用受访者在前一个**选定波次的真实回答**。缺失该波次回答时，不用更早回答替代；这不是将模型预测递归反馈给下一波的实验。

## 运行

验证环境为 R 4.3.2、Python 3.12.4。先在仓库根目录运行：

```sh
Rscript setup/install_packages.R
python -m pip install -r requirements.txt
cd code
Rscript check_project_setup.R
```

按 [数据目录说明](code/data/README.md) 放置指定版本的 GLES 文件。现有研究数据、真实提示词和原始预测不随公开源码发布。缺少已配置的原始文件时，提示词构建会明确停止。

```sh
Rscript run_01_generate_prompts.R
```

模型推理由外部 [AlignSurvey](https://github.com/PiLab-ZJU/AlignSurvey) 基础设施完成，接口见 [INFERENCE.md](docs/INFERENCE.md)。当前论文原始推理脚本和完整配置没有随代码存档，因此不能仅凭这个仓库精确重跑历史模型生成。重新计算论文已有结果应使用与提示词匹配的历史 JSONL 预测。

预测放入 `code/data/llm_outputs/outcome/<variant>/` 后，在 `code/` 运行：

```sh
Rscript run_03_full_evaluation.R
python 03_evaluation/scripts/audit_thesis_results.py --compare-thesis
```

完整流程先检查 580 个预测文件、116 份提示词清单和逐条 ID/参考答案，再清洗、拟合、汇总、导出并检查论文结果。`--skip-input-rebuild` 可复用同一次实验已清洗的输入。需要指定 Python 时设置 `MANUSCRIPT_PYTHON`。独立复现应使用新的结果目录，避免混入旧产物。

结果位于 `code/outputs/evaluation/`：

- `manuscript/tables/`：RQ1/RQ2 主比较及其他数值结果。
- `publication/tables/`：按受访者记录重算的量表距离、模型规格比较和转变指标。
- `publication/latex/`：论文表格行片段。
- `publication/figures/`：论文主文和附录图形。
- `publication/result_audit.json`：统计恒等式、10 份表格、35 个论文图形文件及历史参考值的核对结果。
- `manuscript/audits/`：预测档案覆盖、哈希、分组解析保留数和滞后连接检查。

完整构建不需要论文源文件或 LaTeX，也不自动修改 PDF 或 Overleaf。基础入口 `run_02a_build_and_clean_analysis_inputs.R`、`run_02b_evaluate_existing_analysis_inputs.R` 仍可单独运行，但它们不生成整篇论文所需的全部产物。

## 指标口径

分组任务按论文的模糊匹配规则清洗，无法解析的当前预测会被删除；原始量表的准确率仍将无法解析的预测计为错误。原始量表 MAE、RMSE、相差不超过一档的比例，以及连续变化诊断使用相应的可解析子样本。更新后的距离比较让 LLM 和统计基线使用同一组可解析记录。

RQ1、RQ2 的 ordinal-probit 比较需要对应统计预测可用；RQ3 的转变分析使用全部满足滞后要求的轨迹记录。三者的 N 可能不同，不能统一替换成一个样本量。具体流程见 [WORKFLOW.md](docs/WORKFLOW.md)。

评估固定使用 `LC_COLLATE=C` 和 treatment contrasts，防止分类变量的参照水平随电脑语言设置变化；字符编码单独保持 UTF-8。结构系数相关性和符号一致率须结合这些参照水平解释。

## 无研究数据时的检查

从仓库根目录运行：

```sh
Rscript tests/check_syntax.R
Rscript tests/smoke_main_pipeline.R
Rscript tests/regression_contracts.R
Rscript tests/test_utf8_locale.R
python -m unittest discover -s tests -p "test_*.py"
```

这些检查使用虚构数据，不调用模型。实际研究数据的验证范围与限制见 [VALIDATION.md](docs/VALIDATION.md)。历史数字比对是回归检查，不能代替研究设计的合理性论证。

本次真实数据重建发现：部分历史 CSV 将德文字符转成 `<U+00E4>` 等文本，数字解析器可能把其中的数字当作回答。修复 UTF-8 输入、输出和运行环境后，Mistral 的部分原始量表结果改变。因此原论文参考表会报告差异；不能通过恢复错误编码来消除这些差异。详情和需要更新的结果见 [VALIDATION.md](docs/VALIDATION.md)。

## 本次清理

已删除当前论文没有使用的 manipulated-prior 实验分支、same-database 分支、使用可用行滞后的旧动态链脚本，以及被论文最终结构保真分析替代的回归模块。恢复方法和修改说明见 [RELEASE_NOTES.md](docs/RELEASE_NOTES.md)。原始数据和预测档案不属于清理对象；不符合当前波次设计的旧预测仅被报告并排除。

数据出处见 [DATA_AVAILABILITY.md](docs/DATA_AVAILABILITY.md)，推理基础设施引用见 [THIRD_PARTY.md](docs/THIRD_PARTY.md)。旧 Git 提交可能包含历史研究产物；清理当前源码树不等于删除 Git 历史。

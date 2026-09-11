# 论文代码：Prompt 构建与 Evaluation

本代码包包括 GLES 数据处理与 prompt 构建、LLM 输出整理、主分析 evaluation，
以及 correct / shuffled / incorrect prior 稳健性实验。

**调用 LLM 使用 [AlignSurvey 的 GitHub 代码](https://github.com/PiLab-ZJU/AlignSurvey)。**
论文推理流程基于 AlignSurvey 的推理基础设施进行适配，模型执行使用 LLaMA-Factory。
本仓库提供论文自己的 prompt 构建和 evaluation 代码，通过文件接口连接外部推理流程。

## 使用顺序

1. 在仓库根目录运行 `Rscript setup/install_packages.R`；需要 Python 图表时，
   运行 `python -m pip install -r requirements.txt`。
2. 进入 `code/`，运行 `Rscript check_project_setup.R`，根据
   [数据说明](code/data/README.md) 放入所需调查文件。
3. 运行 `Rscript run_01_generate_prompts.R`。
4. 使用 AlignSurvey 执行推理，按 [接口说明](docs/INFERENCE.md) 保存 JSONL。
5. 运行 `Rscript run_02_build_inputs_and_evaluate.R`；完整论文评估及图表使用
   `Rscript run_03_full_evaluation.R`。

prior 操纵实验参见 [实验说明](code_manipulated_prior/README.md)。英文
[README](README.md) 列出了各任务、prompt 条件、环境依赖和完整运行方式。

## 上传 GitHub

原始数据请从 [GESIS GLES 官方入口](https://www.gesis.org/en/gles/data-and-documentation)
获取；主面板数据为 [ZA6838 v6.0.0](https://doi.org/10.4232/1.14114)。
[数据获取与发布说明](docs/DATA_AVAILABILITY.md) 列出了代码配置的九项研究、
具体版本、官方页面及 DOI，[文件清单](code/data/README.md) 给出了本地放置路径。

数据可供科研使用，并不等于可以在 GitHub 重新发布；具体取决于
[GESIS 使用规则](https://www.gesis.org/fileadmin/user_upload/Usage_regulations.pdf)
和所用版本的协议。论文现有声明也是不再分发 GLES 数据。

真实受访者对应的 JSONL 包含 `prompt`、`predict`、`label` 和 `id`，
因此包含真实参考答案及可关联记录，不能整体视作虚构数据。目前不提供这些
模型输出的公开下载链接。它们与原始数据、中间 RDS、prior manifests 可以
按说明保存在本地受访问控制的工作目录，继续由 `.gitignore` 排除。
普通运行缓存无需发布；上述研究中间文件应与原始实验一起保存。

仅下载 GLES 数据还不能复现原论文数值：还需要对应的已归档模型输出；原始推理
程序和完整参数未齐备，因此不承诺精确重跑原始生成过程。

将本目录的内容作为仓库内容上传，保留 `.gitignore` 和 `.gitattributes`。
原始数据、真实受访者 prompt、模型输出、个人级分析文件和论文修改记录未包含在代码包中。
提供的数据示例和 smoke tests 均使用虚构记录。

维护仓库为 [SitongZhu/Masterarbeit](https://github.com/SitongZhu/Masterarbeit)。
原有 task3 实验已由当前论文代码结构替代，旧脚本仍可从 Git 提交历史中找回。
旧数据、模型输出和日志也仍存在于历史提交中；当前目录清理并不等于历史清除。
详见 [仓库整理说明](docs/REPOSITORY_MIGRATION.md)。

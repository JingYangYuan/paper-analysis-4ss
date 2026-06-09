---
name: paper-analysis-4ss
description: 中文社会科学论文数据分析技能。用于结构化数据清洗、描述统计、基础回归、稳健性检验、质性材料编码、主题/内容分析、混合方法整合和论文结果呈现。支持 Stata、R、Python，内置常用社科基础模型、三语言模板和案例。当用户需要从数据或访谈/文本材料产出论文级表格、图形、编码结果、方法说明和结果段落时使用。
---

# Paper Analysis 4SS

你是中文社会科学论文的数据分析助手。你的任务是把结构化数据、面板数据、访谈文本、田野笔记、开放题文本、政策/新闻/档案文本转化为可复现的清洗脚本、基础回归结果、质性编码结果、混合方法整合表和论文结果写作素材。

本技能必须独立工作。不要把用户引导到其他 scholar-route、CFPS 或 paper-* 技能执行；可以学习其方法原则，但所有操作按本技能文件完成。

## 1. 参数解析

从 `$ARGUMENTS` 中提取：

| 字段 | 规则 | 默认 |
|---|---|---|
| 模式 | `clean`/`describe`/`regression`/`qual`/`mixed`/`robustness`/`export`/`full` | `full` |
| 数据类型 | `.csv/.xlsx/.dta/.sav/.rds/.parquet` 为结构化；`.txt/.md/.docx` 为文本；多种同时出现为混合 | 自动推断 |
| 语言 | `stata`/`r`/`python` | `.dta` 或用户提 Stata 时选 Stata；文本和 ML 选 Python；通用默认 R |
| 核心变量 | `Y=`、`X=`、`controls=`、`fe=`、`cluster=`、`weight=`、`id=`、`time=` | 缺失则从变量名和研究问题推断，无法推断时询问 |
| 质性路径 | `codebook`、`open-coding`、`thematic`、`content`、`reliability`、`llm-coding` | 根据文本材料和需求推断 |
| 目标输出 | 表格、图形、结果文字、脚本、报告 | 全部 |

如果缺少数据路径或研究问题，先扫描当前目录和 `output/` 中的候选数据文件；仍无法确定时，简短询问用户。

## 2. 输出目录

所有模式先创建：

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-output/paper-analysis}"
mkdir -p "$OUTPUT_ROOT"/{data,scripts,tables,figures,reports,qual/codebooks,qual/coded-data,qual/memos,qual/anonymized,qual/reliability}
mkdir -p output/logs
```

过程日志保存到 `output/logs/process-log-paper-analysis-4ss-[YYYY-MM-DD].md`。每个关键决策记录：数据来源、样本口径、变量构造、模型选择、标准误、质性编码规则、输出文件。

## 3. 工作流路由

| 模式 | 执行文件 | 产出 |
|---|---|---|
| `clean` | [02-quant-cleaning.md](phases/02-quant-cleaning.md) | 清洗脚本、变量字典、样本流失表、分析数据 |
| `describe` | [02-quant-cleaning.md](phases/02-quant-cleaning.md) | 描述统计、相关矩阵、基础图 |
| `regression` | [03-basic-regression.md](phases/03-basic-regression.md) | 主回归、边际效应、模型表 |
| `qual` | [04-qual-analysis.md](phases/04-qual-analysis.md) | 匿名化文本、编码本、编码数据、主题/内容分析、信度报告 |
| `mixed` | [05-mixed-methods.md](phases/05-mixed-methods.md) | joint display、案例选择、编码变量化、整合解释 |
| `robustness` | [03-basic-regression.md](phases/03-basic-regression.md) | 稳健性、异质性、机制检验 |
| `export` | [06-export-and-quality-gates.md](phases/06-export-and-quality-gates.md) | 表图导出、方法说明、中文结果段落 |
| `full` | 依次执行 01-06 | 完整论文分析包 |

先读 [01-init-and-routing.md](phases/01-init-and-routing.md)，再按模式读取对应 phase。方法细节按需读取：

- 模型选择：[model-router.md](references/model-router.md)
- 质性方法：[qual-methods.md](references/qual-methods.md)
- 报告规范：[reporting-standards.md](references/reporting-standards.md)
- 三语言生态：[language-ecosystem.md](references/language-ecosystem.md)

## 4. 核心边界

必须做到：

- 结构化数据分析前，完成变量存在性、类型、缺失、异常值、重复、样本筛选和面板唯一性检查。
- 二元、有序、多分类非线性模型必须报告边际效应或预测概率；原始 logit/probit 系数不能作为唯一解释。
- 导出的回归表必须在系数下方显示 t/z 统计值；标准误类型、聚类层级和权重只在表注、正文或日志中说明。
- 所有导出的描述统计、系数、边际效应、t/z 统计值和比例默认保留 3 位小数；样本量、频数保留整数。
- 回归表必须说明 N、固定效应、控制变量、参考组。
- 访谈、田野笔记、开放题文本进入 AI 阅读或 LLM 辅助编码前必须先去标识化；不得读取或展示真实身份映射表。
- 质性分析必须保留编码本、编码到原文摘录映射、分析备忘录和信度/复核记录。
- 混合方法必须输出定量发现与质性主题的整合矩阵，而不是把两部分并排罗列。

不得越界：

- 不承诺复杂数据库全套原始数据重构；只做常规清洗和论文分析数据构建。
- 高级贝叶斯、SEM、复杂机器学习、深度文本模型、网络分析只作为可选扩展，不作为核心流程。
- 不虚构变量、访谈摘录、模型结果或显著性；无法从文件或脚本得到的结果必须标注为待运行。

## 5. 模板与案例

优先复用本技能模板：

| 语言 | 模板 | 案例 |
|---|---|---|
| Stata | [analysis-template.do](templates/stata/analysis-template.do) | [stata-basic-regression.md](examples/stata-basic-regression.md) |
| R | [analysis-template.R](templates/r/analysis-template.R) | [r-clean-regression-qual.md](examples/r-clean-regression-qual.md) |
| Python | [analysis_template.py](templates/python/analysis_template.py) | [python-clean-regression-qual.md](examples/python-clean-regression-qual.md) |

Stata 执行入口固定为：

```bash
/Users/yjy/.local/bin/statacli --stata-path /Applications/Stata --edition mp --compact --no-daemon do "path/to/analysis.do"
```

涉及多条 Stata 命令时必须写入 `.do` 文件运行，不用 `statacli run 'cmd1; cmd2'` 测试生产逻辑。

## 6. 交付格式

最终回复要列出：

1. 已生成或应生成的脚本路径。
2. 主要表格、图形、质性编码和报告路径。
3. 关键模型/编码决策。
4. 已通过和未通过的质量门控。
5. 结果段落中哪些结论来自实际运行，哪些仍需用户提供数据或运行脚本。

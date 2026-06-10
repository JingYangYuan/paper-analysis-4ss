# Phase 02: 定量数据清洗与描述统计

## 1. 清洗原则

目标是构建论文分析数据，不做特定大型调查数据库的完整原始数据重构。所有清洗必须可复现、可审计、可回退。

## 2. 必做检查

| 检查 | 输出 |
|---|---|
| 文件读取和编码 | 读取日志 |
| 变量存在性 | 核心变量清单 |
| 类型检查 | 数值/字符/日期/分类变量表 |
| 缺失检查 | 缺失比例表 |
| 异常值 | 极端值、非法值、箱线图或分位数表 |
| 重复值 | ID 或 ID-time 重复诊断 |
| 样本筛选 | 样本流失表 |
| 面板结构 | `id-time` 唯一性、波次数、平衡性 |

## 3. 常规清洗动作

- 变量改名：保留原变量名到变量字典，清洗变量使用可读名称。
- 类型转换：金额、年龄、教育年限等转数值；日期转标准日期。
- 缺失值：将特殊缺失码显式转为缺失，记录规则。
- 异常值：优先报告和敏感性分析；去极值必须说明阈值。
- 分类变量：保留参考组和标签，记录合并小类规则。
- 连续变量：按理论需要取对数、标准化、中心化。
- 指数构造：分量方向统一，报告 Cronbach alpha 或构造逻辑。

## 4. 变量字典

必须输出 `variable-dictionary.csv`，字段至少包括：

| 字段 | 含义 |
|---|---|
| `raw_name` | 原始变量名 |
| `clean_name` | 清洗后变量名 |
| `label` | 中文含义 |
| `role` | Y/X/control/fe/cluster/weight/id/time/mechanism/moderator |
| `type` | numeric/categorical/text/date |
| `missing_rule` | 特殊缺失码和处理规则 |
| `transform` | 取对数、标准化、反向计分、合成指数等 |
| `source_file` | 来源文件 |
| `notes` | 口径说明和限制 |

变量字典不要求一次完美，但所有进入模型的变量必须有记录。

## 5. 样本流失表

样本流失表按“可复现筛选步骤”而非自然语言摘要生成：

| step | rule | n_before | n_after | dropped | reason |
|---|---|---:|---:|---:|---|
| 0 | raw data |  |  |  | 原始样本 |
| 1 | keep eligible population |  |  |  | 研究对象界定 |
| 2 | nonmissing Y |  |  |  | 因变量缺失 |
| 3 | nonmissing X |  |  |  | 核心解释变量缺失 |
| 4 | nonmissing controls |  |  |  | 控制变量缺失 |
| 5 | valid panel/id-time |  |  |  | 面板唯一性 |

如果同一论文需要多个分析样本，分别输出 `sample-flow-main.csv`、`sample-flow-robustness.csv` 或在 `sample_id` 字段区分。

## 6. 描述统计

输出：

- Table 1：均值、标准差、最小值、最大值、N；分类变量给比例。
- 分组描述：按处理组、性别、城乡、年份或核心分组。
- 相关矩阵：仅用于描述，不作为因果证据。
- 基础图：结果变量分布、核心自变量分布、分组均值图。

所有导出的描述统计保留 3 位小数；N 和频数保留整数。

## 7. 数据质量诊断

清洗报告至少回答：

- 核心变量缺失是否集中在某些群体或年份。
- 极端值是否来自录入错误、真实极端还是单位混乱。
- 分类变量是否存在小样本类别，是否需要合并。
- 面板数据是否有重复 id-time，是否存在严重不平衡。
- 权重变量是否可用，权重为 0 或缺失的样本如何处理。
- 清洗动作是否改变主要样本结构。

## 8. 三语言实现

- Stata：参考 `modules/analysis/templates/stata-analysis-template.do` 的读取、样本标记和描述统计段。
- R：参考 `modules/analysis/templates/r-analysis-template.R` 的 `load_data()`、`clean_data()`、`make_table1()`。
- Python：参考 `modules/analysis/templates/python-analysis-template.py` 的 `load_data()`、`clean_data()`、`describe_data()`。

## 9. 输出文件

保存到：

- `analysis-output/data/analysis-data.*`
- `analysis-output/data/variable-dictionary.csv`
- `analysis-output/tables/table1-descriptives.*`
- `analysis-output/tables/sample-flow.csv`
- `analysis-output/reports/cleaning-report-[date].md`

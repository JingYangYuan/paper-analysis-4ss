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

## 4. 描述统计

输出：

- Table 1：均值、标准差、最小值、最大值、N；分类变量给比例。
- 分组描述：按处理组、性别、城乡、年份或核心分组。
- 相关矩阵：仅用于描述，不作为因果证据。
- 基础图：结果变量分布、核心自变量分布、分组均值图。

所有导出的描述统计保留 3 位小数；N 和频数保留整数。

## 5. 三语言实现

- Stata：参考 `templates/stata/analysis-template.do` 的 `01_descriptives` 和 `02_clean` 段。
- R：参考 `templates/r/analysis-template.R` 的 `load_data()`、`clean_data()`、`make_table1()`。
- Python：参考 `templates/python/analysis_template.py` 的 `load_data()`、`clean_data()`、`describe_data()`。

## 6. 输出文件

保存到：

- `output/paper-analysis/data/analysis-data.*`
- `output/paper-analysis/data/variable-dictionary.csv`
- `output/paper-analysis/tables/table1-descriptives.*`
- `output/paper-analysis/tables/sample-flow.csv`
- `output/paper-analysis/reports/cleaning-report-[date].md`

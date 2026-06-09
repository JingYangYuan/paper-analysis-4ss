# Phase 03: 基础回归、稳健性与结果表

## 1. 模型路由

先读取 `references/model-router.md`。根据因变量类型、数据结构和研究问题选择基础模型。

## 2. 主模型规范

每个主模型必须记录：

- 样本口径和 N。
- 因变量、核心自变量、控制变量。
- 固定效应和聚类层级。
- 权重使用与否。
- 标准误类型。
- 表格展示格式：系数下方必须放 t/z 统计值，不放标准误。
- 数值格式：系数、边际效应、t/z 统计值和比例统一保留 3 位小数；N 和频数保留整数。
- 模型族和链接函数。

## 3. 常用模型

| 任务 | 模型 |
|---|---|
| 连续因变量 | OLS、稳健/聚类标准误、固定效应 |
| 二元因变量 | logit/probit + AME/预测概率 |
| 有序因变量 | ordered logit/probit + 边际效应 |
| 多分类因变量 | multinomial logit + 预测概率 |
| 计数因变量 | Poisson/NB，检查过度离散 |
| 面板数据 | FE/RE、双向固定效应、Hausman |
| 基础因果 | DiD、事件研究、PSM、IV/2SLS |

## 4. 稳健性

至少考虑：

- 替代因变量或核心自变量口径。
- 替代样本限制。
- 替代标准误或聚类层级。
- 加入/移除固定效应。
- 分组回归或交互项。
- DiD 平行趋势、安慰剂、窗口敏感性。
- IV 第一阶段、弱工具变量、过度识别检验。

## 5. 结果解释规则

- 不把相关性写成因果，除非研究设计支持因果识别。
- logit/probit 结果主要解释 AME 或预测概率。
- 交互项优先报告边际效应图或简单斜率。
- 固定效应模型说明估计来自组内变化。
- 表格星号只能辅助阅读；正文报告方向、量级和置信区间或 exact p；表格括号内为 t/z 统计值。

## 6. 输出文件

- `tables/table2-main-regression.*`
- `tables/table3-marginal-effects.*`
- `tables/tableA1-robustness.*`
- `figures/coefplot-main.*`
- `figures/marginal-effects.*`
- `reports/regression-results-[date].md`

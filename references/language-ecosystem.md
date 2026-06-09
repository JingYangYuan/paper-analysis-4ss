# 三语言生态

## Stata

适合：`.dta` 数据、传统计量表、固定效应、DiD、IV、论文回归表。

常用命令：

- 清洗：`destring`、`encode`、`recode`、`egen`、`duplicates`、`misstable`
- 回归：`regress`、`logit`、`probit`、`ologit`、`mlogit`、`poisson`、`nbreg`
- 面板：`xtset`、`xtreg`、`reghdfe`
- 边际效应：`margins`、`marginsplot`
- IV：`ivregress 2sls`、`estat firststage`
- 导出：`esttab/estout`、`putdocx`、`collect`；多模型回归表默认使用 `esttab, b(3) t(3) nogaps`，系数下方放 t/z 统计值

执行入口：

```bash
/Users/yjy/.local/bin/statacli --stata-path /Applications/Stata --edition mp --compact --no-daemon do "script.do"
```

## R

适合：通用清洗、固定效应、边际效应、模型表、期刊图形、编码信度。

常用包：

- 清洗：`tidyverse`、`haven`、`readxl`、`arrow`
- 回归：`fixest`、`broom`、`sandwich`、`lmtest`
- 边际效应：`marginaleffects`
- 表格：`modelsummary`、`gt`
- 图形：`ggplot2`
- 质性信度：`irr`

## Python

适合：批量文本、自动化清洗、基础回归、面板模型、预测建模、LLM 辅助编码。

常用包：

- 清洗：`pandas`、`numpy`
- 回归：`statsmodels`
- 面板：`linearmodels`
- ML：`scikit-learn`
- 图形：`seaborn`、`matplotlib`
- 文本：`re`、`jieba`、`sklearn.feature_extraction`
- 信度：`sklearn.metrics.cohen_kappa_score`

# Stata 案例：清洗检查、基础回归与边际效应

## 适用场景

用户有 `.dta` 分析数据，希望产出描述统计、OLS/固定效应、logit 边际效应和论文回归表。

## 输入

- `data/raw/survey.dta`
- 因变量：`life_satisfaction`
- 核心自变量：`internet_use`
- 控制变量：`age gender education income`
- 固定效应：年份和省份
- 聚类：省份

## 代码骨架

复制 `templates/stata/analysis-template.do`，修改：

```stata
global DATA_PATH "$PROJ/data/raw/survey.dta"
global Y "life_satisfaction"
global X "internet_use"
global C "age gender education income"
global FE "i.year i.province"
global CLUSTER "province"
```

运行：

```bash
/Users/yjy/.local/bin/statacli --stata-path /Applications/Stata --edition mp --compact --no-daemon do "output/paper-analysis/scripts/main-analysis.do"
```

## 输出

- `tables/table1-descriptives.csv`
- `tables/table2-main-regression.csv/.rtf`，默认使用 `esttab, b(3) t(3) nogaps`，系数下方为 t/z 统计值
- `tables/table3-ame.csv`
- `reports/stata-analysis.log`

## 论文写法

“表 2 显示，互联网使用与生活满意度显著正相关。在控制年龄、性别、教育和收入并加入年份与省份固定效应后，核心系数仍为正。标准误按省份聚类。若因变量改为二元高满意度指标，logit 模型的平均边际效应显示，互联网使用者的高满意度概率更高。”

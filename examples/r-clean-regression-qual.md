# R 案例：清洗、固定效应回归、边际效应与编码信度

## 适用场景

用户有 CSV/XLSX/DTA 数据，需要清洗、回归、导出表格；同时有一份开放题编码结果，需要计算编码一致性。

## 输入

- `data/raw/survey.csv`
- 因变量：`trust`
- 自变量：`platform_work`
- 控制变量：`age`、`gender`、`education`
- 固定效应：`city`、`year`
- 聚类：`city`
- 编码信度文件：`output/paper-analysis/qual/coded-data/double-coded.csv`

## 代码骨架

```r
source("templates/r/analysis-template.R")

df <- load_data("data/raw/survey.csv") |> clean_data()
df_a <- make_sample(df, "trust", "platform_work", c("age", "gender", "education"))
make_table1(df_a, c("trust", "platform_work", "age", "education"))

m1 <- run_ols(
  df_a,
  y = "trust",
  x = "platform_work",
  controls = c("age", "gender", "education"),
  fe = c("city", "year"),
  cluster = "city"
)

export_models(list("FE model" = m1))
plot_coef(m1)

coded <- readr::read_csv("output/paper-analysis/qual/coded-data/double-coded.csv")
code_reliability(coded$coder_a, coded$coder_b)
```

## 输出

- `tables/table1-descriptives.html`
- `tables/table2-main-regression.html/.tex/.docx/.csv`
- `figures/coefplot-main.pdf/.png`
- `qual/reliability/reliability-report-*.md`

## 论文写法

“固定效应模型显示，平台劳动经历与信任水平之间存在负向关联。模型控制个体特征，并加入城市和年份固定效应，标准误按城市聚类。开放题编码的一致性检验显示，两名编码者的 Cohen's kappa 达到可接受水平，说明编码本具备基本稳定性。”

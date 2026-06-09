# Python 案例：数据清洗、基础回归与质性文本分段

## 适用场景

用户需要用 Python 完成 pandas 清洗、statsmodels 回归、访谈文本匿名化分段、编码频次统计。

## 输入

- `data/raw/panel.csv`
- 因变量：`income`
- 自变量：`training`
- 控制变量：`age`、`education`
- 聚类：`county`
- 访谈文本：`materials/interviews/interview01.txt`

## 代码骨架

```python
import importlib.util
import pandas as pd

spec = importlib.util.spec_from_file_location(
    "analysis_template",
    "/Users/yjy/.skills-manager/skills/paper-analysis-4ss/templates/python/analysis_template.py"
)
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)

df = analysis.clean_data(analysis.load_data("data/raw/panel.csv"))
analysis.sample_flow(df, y="income", x="training", controls=["age", "education"])
df_a = df.dropna(subset=["income", "training", "age", "education"])
analysis.describe_data(df_a, ["income", "training", "age", "education"])

m = analysis.run_ols(df_a, y="income", x="training", controls=["age", "education"], cluster="county")
analysis.export_regression_text(m)
analysis.export_regression_table(m)

segments = analysis.segment_text_file("materials/interviews/interview01.txt")

# 人工编码后，coded_segments.csv 至少包含 segment_id 和 code
coded = pd.read_csv("output/paper-analysis/qual/coded-data/coded_segments.csv")
analysis.code_frequency(coded)
```

## 输出

- `tables/sample-flow.csv`
- `tables/table1-descriptives.csv`
- `tables/table2-main-regression.txt`
- `tables/table2-main-regression.csv`，系数和 t/z 统计值均保留 3 位小数
- `qual/coded-data/segments-interview01.csv`
- `tables/qual-code-frequency.csv`

## 论文写法

“Python 清洗脚本首先剔除核心变量缺失的观测，并输出样本流失表。OLS 回归采用 HC3 或聚类稳健标准误。访谈文本在分段前完成匿名化，后续编码频次表用于呈现不同主题在材料中的分布。”

# Paper Analysis 4SS

中文社会科学论文数据分析工具。将结构化数据（CSV、DTA、SAV、RDS 等）、面板数据、访谈文本、田野笔记、开放题文本、政策/新闻/档案文本转化为可复现的清洗脚本、基础回归结果、质性编码结果、混合方法整合表和论文结果写作素材。

## 支持的分析模式

| 模式 | 产出 |
|---|---|
| `clean` | 清洗脚本、变量字典、样本流失表 |
| `describe` | 描述统计、相关矩阵、基础图形 |
| `regression` | 主回归、边际效应、模型表 |
| `qual` | 匿名化文本、编码本、主题/内容分析、信度报告 |
| `mixed` | Joint display、案例选择、编码变量化、整合解释 |
| `robustness` | 稳健性检验、异质性分析、机制检验 |
| `export` | 图表导出、方法说明、中文结果段落 |
| `full` | 依次执行以上全部流程 |

## 支持语言

- **Stata** — 含 OLS、IV、DID、RDD、PSM、SCM、面板、非线性、时间序列、空间计量、Bootstrap（~800 行完整模板）
- **R** — 20 个分析模块，含诊断套件与可视化协议（~800 行模板）
- **Python** — 17 个分析模块，覆盖清洗到稳健性（~800 行模板）

## 项目结构

```
├── SKILL.md              # Skill 定义与完整使用说明
├── phases/               # 六阶段执行流程
│   ├── 01-init-and-routing.md
│   ├── 02-quant-cleaning.md
│   ├── 03-basic-regression.md
│   ├── 04-qual-analysis.md
│   ├── 05-mixed-methods.md
│   └── 06-export-and-quality-gates.md
├── references/           # 方法参考知识库
│   ├── model-router.md           # 模型选择、诊断阈值、内生性框架
│   ├── qualitative-methods.md    # 扎根理论、主题分析、内容分析、LLM 编码
│   ├── reporting-standards.md    # 数值格式、模型表、图形规范、段落模板
│   ├── language-ecosystem.md     # 三语言生态与包选择
│   ├── r-ecosystem-plotting.md   # R 绘图与运行环境
│   └── stata-cli-setup.md        # Stata CLI 安装配置
└── templates/            # 三语言完整分析脚手架
    ├── stata-analysis-template.do
    ├── r-analysis-template.R
    └── python-analysis-template.py
```

## 使用方式

本仓库作为 Claude Code 的 Skill 使用，由 Skills Manager 管理。安装后通过 `paper-analysis-4ss` 技能名调用，支持自动推断数据类型、分析语言和目标输出。

### 关键质量边界

- 结构化数据分析前，完成变量存在性、类型、缺失、异常值、重复、样本筛选和面板唯一性检查
- Logistic/Probit 等非线性模型必须报告边际效应或预测概率，不能仅报告原始系数
- 回归表系数下方显示 t/z 统计值，表注说明标准误类型、聚类层级和权重
- 描述统计、系数、边际效应保留 3 位小数，样本量和频数保留整数
- 访谈/田野笔记进入分析前必须去标识化，保留编码本、编码摘录映射、分析备忘录和信度记录
- 混合方法必须输出定量发现与质性主题的整合矩阵

## 许可证

本项目作为 Skills Manager 生态的一部分发布。

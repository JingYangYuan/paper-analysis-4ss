# Phase 01: 初始化与路由

## 1. 环境与目录

创建目录并初始化日志：

```bash
OUTPUT_ROOT="${OUTPUT_ROOT:-analysis-output}"
mkdir -p "$OUTPUT_ROOT"/{data,scripts,tables,figures,reports,qual/codebooks,qual/coded-data,qual/memos,qual/anonymized,qual/reliability}
mkdir -p analysis-output/_logs
LOG_FILE="analysis-output/_logs/process-log-analysis-$(date +%Y-%m-%d).md"
if [ ! -f "$LOG_FILE" ]; then
  printf "# Process Log: modules/analysis\n\n| Time | Step | Decision | Output |\n|---|---|---|---|\n" > "$LOG_FILE"
fi
```

## 2. 数据发现

若用户未给路径，扫描当前项目目录寻找候选数据文件：

```bash
find . -maxdepth 4 -type f \( -name "*.csv" -o -name "*.xlsx" -o -name "*.dta" -o -name "*.sav" -o -name "*.rds" -o -name "*.parquet" -o -name "*.txt" -o -name "*.md" -o -name "*.docx" \) 2>/dev/null | head -80
```

候选较多时，按最近修改时间、文件名中的 `clean`、`analysis`、`访谈`、`transcript`、`data`、`panel` 优先。

## 3. 数据类型路由

| 输入 | 路由 |
|---|---|
| CSV/XLSX/DTA/SAV/RDS/Parquet | 定量清洗与基础回归 |
| 多波次或含 id/time | 面板检查 + FE/RE/DiD 可能路径 |
| 访谈/田野/开放题/政策文本 | 质性匿名化 + 编码/主题/内容分析 |
| 定量结果 + 质性材料 | 混合方法 |

## 4. 语言选择

| 条件 | 默认语言 |
|---|---|
| 用户明确指定 | 用户指定 |
| `.dta`、Stata 项目、要求 esttab/putdocx | Stata |
| 通用清洗、固定效应、论文表图 | R |
| 文本分段、批量编码、机器学习、Python 项目 | Python |

记录语言选择及理由。若同一项目用多语言，必须生成 `script-index.md` 说明运行顺序。

## 5. 安全门控

结构化数据：只在输出中打印汇总统计，不泄露原始行级敏感信息。  
质性材料：访谈、田野笔记、开放题文本必须先走匿名化流程，真实身份映射表不得被读取、复制到报告或提交给 AI。

## 6. 最低信息要求

定量回归至少需要：数据路径、因变量、核心自变量。控制变量、固定效应、聚类层级可以从研究设计推断，但推断要记录。  
质性分析至少需要：文本路径、研究问题、分析单位。若用户只要求整理材料，默认做分段和编码本草案。

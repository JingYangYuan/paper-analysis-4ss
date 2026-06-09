# Phase 04: 质性材料分析

## 1. 适用材料

访谈文本、田野笔记、开放题回答、政策文本、新闻文本、档案文本、组织文件、会议纪要。

## 2. 匿名化硬门控

在 AI 阅读或 LLM 辅助编码前，必须：

1. 扫描姓名、电话、邮箱、地址、单位、学校、医院、精确日期、身份证号、罕见事件。
2. 建立本地匿名映射表，文件名必须含 `DO-NOT-SHARE`。
3. 生成 `ANON_` 前缀的匿名化文本。
4. 再扫描匿名化文本。
5. 后续只读取匿名化文本。

不得读取或输出真实身份映射表内容。

## 3. 资料整理

把文本整理为分段数据：

| 字段 | 说明 |
|---|---|
| document_id | 文档或访谈编号 |
| segment_id | 片段编号 |
| speaker | 说话人或材料来源 |
| date_or_period | 时间信息 |
| text | 匿名化文本片段 |
| memo | 初始备忘 |

分析单位可为句子、段落、话轮、事件、文档。必须记录选择理由。

## 4. 编码本

编码本字段：

`code_id, code_name, parent_code, level, definition, inclusion_criteria, exclusion_criteria, typical_example, boundary_case, notes`

支持三种策略：

- 归纳编码：从材料中生成概念，保留 in-vivo 表达。
- 演绎编码：从理论、文献或研究问题生成初始编码。
- 混合编码：先理论骨架，再加入材料中涌现的编码。

## 5. 扎根理论基础流程

- 开放编码：逐段编码，记录 in-vivo、描述性、过程性编码。
- 主轴编码：按因果条件、现象、背景、干预条件、行动策略、后果组织范畴。
- 选择性编码：识别核心范畴，写 500-800 字 storyline。
- 理论备忘录：记录概念变化、编码合并拆分、负面案例。
- 输出范畴关系图和理论命题。

## 6. 主题分析

按 Braun & Clarke 的轻量化流程：

1. 熟悉材料并记录初始印象。
2. 生成语义编码和潜在编码。
3. 聚合候选主题。
4. 回到已编码片段和完整材料复核主题。
5. 定义并命名主题。
6. 写主题化结果段落，包含代表性引文和解释。

主题不能只是话题标签，必须表达共享意义模式。

## 7. 内容分析

定义：

- 抽样单位：纳入哪些文档。
- 记录单位：编码的最小对象。
- 语境单位：解释记录单位时可参考的范围。

输出编码频次、按材料类型/时间/主体的交叉表、共现矩阵和可视化。

## 8. 信度检查

- 两名编码者：Cohen's kappa。
- 多名编码者或缺失编码：Krippendorff's alpha。
- 最低可接受：0.60；常规目标：0.70；高质量目标：0.80。
- 未达标时必须修订编码本、重新训练、记录分歧解决。

## 9. LLM 辅助编码

仅作为可选路径。必须满足：

- 使用匿名化文本。
- 有人类金标准样本。
- 先在 gold standard 上测试，目标 kappa >= 0.70。
- 低置信度片段人工复核。
- 10-20% 语料人工验证。
- 检查编码顺序偏差、长文本偏差、多数类偏差。
- 归档提示词、模型、温度、成本、人工复核比例。

## 10. 输出文件

- `qual/codebooks/codebook-[slug]-[date].md/.csv`
- `qual/coded-data/segments-[slug]-[date].csv`
- `qual/coded-data/open-codes-[slug]-[date].csv`
- `qual/coded-data/thematic-analysis-[slug]-[date].md`
- `qual/coded-data/content-analysis-[slug]-[date].md`
- `qual/reliability/reliability-report-[slug]-[date].md`
- `qual/memos/*.md`

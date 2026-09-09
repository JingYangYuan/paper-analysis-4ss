<p align="center">
  <img src="docs/banner.svg" alt="paper-analysis-4ss" width="100%">
</p>

# Paper 数据分析 4SS（analysis 模块独立版）

中文社会科学论文数据分析技能。用于结构化数据清洗、描述统计、主回归、中介/机制、调节、异质性、门槛、非线性、政策识别、稳健性检验、质性材料编码、主题/内容分析、混合方法整合和论文结果呈现。支持 Stata、R、Python，内置常用社科基础模型、三语言模板和案例。当用户需要从数据或访谈/文本材料产出论文级表格、图形、代码、方法说明和结果段落时使用。

本包由 `paper-master-4ss/scripts/export_standalone.py` 从总控包 `paper-master-4ss/modules/analysis/` 自动导出：

- 包内相对路径相对本包根目录解析；
- `master/` 与 `references/` 中的协议/治理文件是导出时拷贝的快照；
- 跨模块路径 `paper-master-4ss/modules/<x>/...` 相对同级安装的总控包解析；
- 更新方式：修改总控包对应模块后运行
  `python3 paper-master-4ss/scripts/export_standalone.py analysis` 重新导出，勿直接编辑本包。

## 它做什么

把结构化数据、面板、访谈/田野/开放题文本和政策档案转成可复现的清洗脚本、估计结果、质性编码和论文结果素材。支持 Stata、R、Python 三语言模板。

不替代 design 的识别策略裁决；声称边界交给 write。

## 使用

将本目录安装为宿主 skill（与 `paper-master-4ss` 总控包同级）。入口见 `SKILL.md`。Stata MCP / 本地 Stata 按 `references/install-dependencies.md` 验收。

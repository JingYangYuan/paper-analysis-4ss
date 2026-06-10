# R 运行环境与绘图知识库

本文件供 `modules/analysis/` 在选择 R 环境、配置镜像源、安装 R 依赖、生成论文图形或交互图时按需读取。

## 0. CRAN 镜像源

首次使用 R 前，建议配置国内镜像加速包下载。

### 持久配置（推荐）

在 `~/.Rprofile` 中添加：

```r
options(repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))
options(BioC_mirror = "https://mirrors.tuna.tsinghua.edu.cn/bioconductor")
```

### 国内常用镜像

| 镜像 | URL |
|------|-----|
| 清华 TUNA | `https://mirrors.tuna.tsinghua.edu.cn/CRAN/` |
| 中科大 USTC | `https://mirrors.ustc.edu.cn/CRAN/` |
| 阿里云 | `https://mirrors.aliyun.com/CRAN/` |
| 官方 CDN | `https://cloud.r-project.org` |

### 安装验证

```bash
# 检查 R 是否正确安装
R --version

# R 内验证镜像配置
R -e 'options("repos")'

# 测试安装包
R -e 'install.packages("ggplot2", repos="https://cloud.r-project.org")'
```

## 1. R 运行环境选择

| 场景 | 推荐环境 | 用法 |
|---|---|---|
| 本机常规论文分析 | CRAN R + RStudio/Positron | 稳定、包兼容性最好，适合日常清洗、回归、制图 |
| 多版本 R 管理 | `rig` | 安装、切换、并行保留多个 R 版本 |
| 可复现项目 | CRAN R + `renv` | 锁定项目包版本，适合论文复现包 |
| 服务器/容器 | Rocker Docker | 固化 R、系统库、LaTeX、地理库等依赖 |
| Python/R 混合环境 | conda/mamba `r-base` | 适合统一管理 Python 与 R，但 `sf` 等空间包可能有系统库问题 |
| 空间制图 | CRAN/Rocker + GDAL/GEOS/PROJ | 优先使用二进制包或容器，减少系统库冲突 |

R 环境记录必须写入 `analysis-output/reports/r-session-info.txt`：

```r
writeLines(capture.output(sessionInfo()), "analysis-output/reports/r-session-info.txt")
```

## 2. 包安装策略

优先级：

1. 已安装包：直接复用，不自动升级破坏项目。
2. 项目复现：使用 `renv::snapshot()` 锁定版本。
3. 新项目：从 CRAN 或 Posit Package Manager 安装稳定版。
4. 空间包失败：优先使用二进制包、Rocker geospatial 镜像或系统库补齐。
5. 开发版只用于明确需要新特性时，不作为默认。

基础安装片段：

```r
required <- c(
  "tidyverse", "haven", "readxl", "arrow", "janitor",
  "fixest", "marginaleffects", "modelsummary", "broom",
  "ggplot2", "patchwork", "cowplot", "ggrepel", "scales",
  "viridis", "ggthemes", "ggridges", "ggdist", "ggeffects",
  "showtext"
)
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) install.packages(missing)
```

空间与交互图按需安装：

```r
spatial <- c("sf", "tmap", "leaflet", "ggspatial")
interactive <- c("plotly", "htmlwidgets", "DT")
```

## 3. 绘图库路由

| 任务 | 首选库 | 辅助库 | 输出 |
|---|---|---|---|
| 描述统计图 | `ggplot2` | `scales`, `viridis`, `ggthemes` | PDF + PNG |
| 分组均值/置信区间 | `ggplot2` | `ggdist`, `ggridges` | 论文图 |
| 回归系数图 | `modelsummary::modelplot`, `ggplot2` | `broom`, `dotwhisker` | 系数点图 |
| 边际效应图 | `marginaleffects`, `ggeffects` | `ggplot2` | AME/预测概率图 |
| DiD 事件研究图 | `fixest::iplot`, `ggplot2` | `did`, `broom` | 相对时间图 |
| 多图组合 | `patchwork` | `cowplot` | 主文组合图 |
| 标签防重叠 | `ggrepel` | `ggtext` | 可读注释 |
| 期刊配色 | `viridis`, `ggsci`, `RColorBrewer` | `scales` | 色盲友好 |
| 交互探索 | `plotly` | `htmlwidgets` | HTML，只作探索或附录 |
| 空间静态图 | `sf`, `tmap`, `ggplot2::geom_sf` | `ggspatial` | 地图 PDF/PNG |
| 空间交互图 | `leaflet` | `sf`, `htmlwidgets` | HTML |
| 表格图形一体 | `gt`, `modelsummary`, `tinytable` | `gtsummary` | HTML/DOCX/TeX |

## 4. 论文图形硬规则

- 每张图都保存 PDF 和 PNG：PDF 用于排版，PNG 用于预览。
- 文件名使用 `fig-[number]-[slug].pdf/png`，例如 `fig-02-event-study.pdf`。
- 轴标题必须说明变量含义和单位。
- 颜色不得只靠红绿区分；默认使用 `viridis` 或灰阶可读方案。
- 回归图必须显示置信区间和零线。
- 边际效应图必须说明计算口径：AME、MEM 或指定情境预测概率。
- 地图必须说明空间单位、年份、投影或坐标系。
- 交互图不得替代论文静态图；只作为探索结果或补充材料。

## 5. 内置绘图协议

### 5.1 描述统计图

用于展示核心变量分布、分组均值和样本结构。

```r
plot_distribution <- function(df, var, group = NULL) {
  p <- ggplot(df, aes(x = .data[[var]], fill = if (!is.null(group)) .data[[group]] else NULL)) +
    geom_histogram(bins = 30, alpha = 0.75, color = "white") +
    theme_paper() +
    labs(x = var, y = "Count", fill = group)
  save_plot_pair(p, paste0("dist-", var))
  p
}
```

### 5.2 回归系数图

用于把主回归或稳健性模型转为可读图形。

```r
plot_model_coefficients <- function(models, coef_omit = "Intercept|^factor|^C\\(") {
  p <- modelsummary::modelplot(models, coef_omit = coef_omit) +
    geom_vline(xintercept = 0, linetype = "dashed") +
    theme_paper() +
    labs(x = "Estimate", y = NULL)
  save_plot_pair(p, "coefplot-main")
  p
}
```

### 5.3 事件研究图

用于政策评估和 staggered DiD。

```r
plot_event_study_fixest <- function(model) {
  pdf(file.path(output_root, "figures/fig-event-study.pdf"), width = 7, height = 5)
  fixest::iplot(model, ref.line = 0, main = "Event-study estimates")
  dev.off()
}
```

### 5.4 地图

空间数据首选 `sf` 对象；静态图可用 `geom_sf()` 或 `tmap`。

```r
plot_choropleth <- function(sf_data, fill_var) {
  p <- ggplot(sf_data) +
    geom_sf(aes(fill = .data[[fill_var]]), color = "white", linewidth = 0.1) +
    scale_fill_viridis_c(option = "C", na.value = "grey90") +
    theme_void(base_size = 12) +
    labs(fill = fill_var)
  save_plot_pair(p, paste0("map-", fill_var), width = 7, height = 6)
  p
}
```

## 6. 中文字体渲染

论文图形涉及中文变量名、分组标签、坐标轴标题时，R 默认 `pdf()` 设备不支持 CJK 字符。必须同时满足两个条件：

1. **加载 `showtext` 包**并在脚本顶部调用 `showtext_auto()`，自动接管后续所有图形设备的字体渲染。
2. **PDF 使用 `cairo_pdf` 设备**（`ggsave(..., device = cairo_pdf)` 或 `cairo_pdf()`）。

```r
library(showtext)
showtext_auto()  # 之后所有 ggplot 输出自动支持中文
```

`showtext` 依赖 `sysfonts` + `showtextdb`，首次安装需从源码编译（≈1 分钟），之后零配置即可使用系统字体。macOS 无需手动 `font_add()`，Windows 通常也无需额外配置。

## 7. 常见故障

| 问题 | 处理 |
|---|---|
| PDF 中文乱码或空白 | 缺少 `showtext_auto()`；或 `ggsave` 用了默认 `device` 而非 `cairo_pdf` |
| `sf` 安装失败 | 检查 GDAL、GEOS、PROJ、udunits2；优先二进制包或 Rocker geospatial |
| 图中文字乱码 | `showtext_auto()` + `cairo_pdf` 即可解决；不需要逐图设置 family |
| `ggsave()` 尺寸混乱 | 统一使用英寸和 `dpi = 300` |
| Word 中图不清楚 | 使用 PNG 300dpi；投稿排版使用 PDF |
| 颜色不可读 | 使用 `viridis`、灰阶或线型区分 |
| 交互图无法投稿 | 同时生成静态 PDF/PNG |
| `scale_fill_viridis_d()` 报 not exported | 这些 scale 函数是 ggplot2 的 re-export，直接调用不加 `viridis::` 前缀 |
| `modelsummary` 安装失败 | 依赖链 `bayestestR→parameters→performance→modelsummary` 源码安装时容易因锁文件 (`00LOCK-*`) 中断；删除锁文件后重试，或用 `ggplot2` 手写系数图替代 `modelplot()` |
| dplyr `across()` 弃用警告 | dplyr ≥1.1.0 中 `across(a:b, mean, na.rm = TRUE)` 需改为 `across(a:b, \(x) mean(x, na.rm = TRUE))` |

## 8. 检索来源

本文件根据以下公开官方资料整理为内部协议：CRAN R、Posit RStudio/Package Manager、r-lib `rig`、Rocker、ggplot2、patchwork、plotly R、sf、tmap、leaflet。

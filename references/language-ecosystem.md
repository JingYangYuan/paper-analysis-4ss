# 三语言生态

---

## 1. Stata

### 1.1 安装

Stata 是商业软件，需自行购买并安装。本模块通过 [stata-cli](https://github.com/ashuiGordon/stata-cli) 命令行桥接工具调度 Stata。

安装步骤、路径检测和故障排除详见 [stata-cli-setup.md](stata-cli-setup.md)。

### 1.2 社区包安装

```stata
* 设置 SSC 镜像（国内用户）
net set ado https://stata.pzhao.org/ado/       // 郑凡丁镜像
* 或保持默认
net set ado https://fmwww.bc.edu/repec/bocode/

* 安装常用社区包
ssc install reghdfe, replace
ssc install ftools, replace
ssc install estout, replace
ssc install winsor2, replace
ssc install ivreg2, replace
ssc install ranktest, replace
ssc install ivreghdfe, replace
ssc install rdrobust, replace
ssc install rddensity, replace
ssc install psmatch2, replace
ssc install pstest, replace
ssc install outreg2, replace
```

### 1.3 适用场景

`.dta` 数据、传统计量表、固定效应、DiD、IV、论文回归表。

### 1.4 常用命令

- 清洗：`destring`、`encode`、`recode`、`egen`、`duplicates`、`misstable`
- 回归：`regress`、`logit`、`probit`、`ologit`、`mlogit`、`poisson`、`nbreg`
- 面板：`xtset`、`xtreg`、`reghdfe`
- 边际效应：`margins`、`marginsplot`
- IV：`ivregress 2sls`、`estat firststage`
- 导出：`esttab/estout`、`putdocx`、`collect`；多模型回归表默认使用 `esttab, b(3) t(3) nogaps`，系数下方放 t/z 统计值

### 1.5 执行入口

```bash
STATA_CLI="${STATA_CLI:-$(command -v stata-cli)}"
test -n "$STATA_CLI" || { echo "未找到 stata-cli；按 modules/analysis/references/stata-cli-setup.md 安装"; exit 1; }
"$STATA_CLI" --stata-path "${STATA_PATH:-/Applications/Stata}" --edition mp --compact --no-daemon do "script.do"
```

---

## 2. R

### 2.1 安装 R 运行时

```bash
# macOS
brew install R

# Ubuntu / Debian
sudo apt-get update && sudo apt-get install -y r-base r-base-dev

# Windows
# 从 https://cran.r-project.org/bin/windows/base/ 下载安装包
```

多版本管理（推荐 rig）：

```bash
brew install rig
rig install release    # 安装最新正式版
rig default release    # 设为默认版本
rig list               # 列出已安装版本
```

### 2.2 CRAN 镜像源

```r
# 方式一：写入 .Rprofile（持久生效）
# ~/.Rprofile
options(repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))

# 方式二：手动设置
chooseCRANmirror()        # 交互式选择
options("repos" = "https://cloud.r-project.org")  # 官方 CDN

# 方式三：临时指定
install.packages("fixest", repos = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/")
```

国内常用 CRAN 镜像：
| 镜像 | URL |
|------|-----|
| 清华 TUNA | `https://mirrors.tuna.tsinghua.edu.cn/CRAN/` |
| 中科大 USTC | `https://mirrors.ustc.edu.cn/CRAN/` |
| 阿里云 | `https://mirrors.aliyun.com/CRAN/` |
| 官方 CDN | `https://cloud.r-project.org` |

Bioconductor 镜像：

```r
options(BioC_mirror = "https://mirrors.tuna.tsinghua.edu.cn/bioconductor")
```

### 2.3 包管理

```r
# 基础安装
required <- c("tidyverse", "fixest", "marginaleffects", "modelsummary", "ggplot2")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) install.packages(missing)

# 锁定版本（论文复现）
renv::init()      # 创建项目级包库
renv::snapshot()  # 锁定当前版本
renv::restore()   # 复现时还原
```

### 2.4 适用场景

通用清洗、固定效应、边际效应、模型表、期刊图形、空间图、交互探索、编码信度。

### 2.5 常用包

- 清洗：`tidyverse`、`haven`、`readxl`、`arrow`
- 回归：`fixest`、`broom`、`sandwich`、`lmtest`、`plm`
- 边际效应：`marginaleffects`
- 表格：`modelsummary`、`gt`
- 图形：`ggplot2`、`patchwork`、`ggrepel`、`scales`、`viridis`、`ggdist`、`ggeffects`
- 空间/交互：`sf`、`spdep`、`tmap`、`leaflet`、`plotly`
- 质性信度：`irr`

R 环境管理和绘图协议详见 [r-ecosystem-plotting.md](r-ecosystem-plotting.md)。

---

## 3. Python

### 3.1 安装 Python 运行时

```bash
# macOS
brew install python@3.12

# Ubuntu / Debian
sudo apt-get install -y python3.12 python3.12-venv

# Windows
# 从 https://www.python.org/downloads/ 下载安装包
```

推荐使用虚拟环境隔离项目依赖：

```bash
# 标准 venv
python3 -m venv .venv
source .venv/bin/activate     # macOS/Linux
.venv\Scripts\activate        # Windows

# conda
conda create -n paper-analysis python=3.12
conda activate paper-analysis
```

### 3.2 PyPI 镜像源

```bash
# 方式一：临时指定
pip install pandas statsmodels -i https://pypi.tuna.tsinghua.edu.cn/simple

# 方式二：持久配置 (~/.pip/pip.conf 或 %APPDATA%/pip/pip.ini)
# [global]
# index-url = https://pypi.tuna.tsinghua.edu.cn/simple
# trusted-host = pypi.tuna.tsinghua.edu.cn

# 方式三：pip config 命令
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

国内常用 PyPI 镜像：
| 镜像 | URL |
|------|-----|
| 清华 TUNA | `https://pypi.tuna.tsinghua.edu.cn/simple` |
| 阿里云 | `https://mirrors.aliyun.com/pypi/simple/` |
| 中科大 USTC | `https://pypi.mirrors.ustc.edu.cn/simple/` |
| 官方 | `https://pypi.org/simple/` |

### 3.3 关键依赖安装

```bash
pip install pandas numpy scipy statsmodels matplotlib seaborn  # 核心
pip install linearmodels                                       # IV + 面板
pip install scikit-learn                                       # ML + 倾向得分
pip install jupyterlab                                         # 交互探索（可选）
```

### 3.4 适用场景

批量文本、自动化清洗、基础回归、面板模型、预测建模、LLM 辅助编码。

### 3.5 常用包

- 清洗：`pandas`、`numpy`
- 回归：`statsmodels`
- 面板/IV：`linearmodels`
- ML：`scikit-learn`
- 因果 ML：`doubleml`、`econml`
- RDD：`rdrobust`
- 图形：`matplotlib`、`seaborn`、`scipy`
- 文本：`re`、`jieba`

### 3.6 绘图关键规则

- **中文字体**：`plt.rcParams["font.sans-serif"] = ["PingFang SC", "Heiti SC", "SimHei", "Microsoft YaHei"]`；`axes.unicode_minus = False`
- **后端**：headless/服务器环境必须 `matplotlib.use("Agg")`
- **颜色**：用十六进制如 `#666666`，不用 CSS 名称如 `grey40`
- **双格式导出**：`fig.savefig(...)` 同时存 PDF（排版）+ PNG（预览）
- **公式模型预测**：使用 `C()` 编码（如 `"y ~ x + C(gender)"`），避免在公式中写 dummy 列名

绘图函数（模板已内置）：`save_plot_pair()`、`theme_paper()`、`plot_distribution()`、`plot_group_mean()`、`plot_coef()`、`plot_marginal()`、`plot_diagnostics()`。详见 [python-analysis-template.py](../templates/python-analysis-template.py)。

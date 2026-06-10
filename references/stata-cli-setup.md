# Stata CLI 安装参考

本文档供 `modules/analysis/` 在需要运行 Stata 脚本、但当前环境缺少命令行入口时按需读取。覆盖安装、验收、路径检测和常见故障。

## 何时读取

仅在以下情况读取本文件：

- 用户要求使用 Stata。
- 输入数据是 `.dta`，或分析脚本已经是 `.do` 文件。
- 运行 `command -v stata-cli` 失败。
- Stata 路径或版本不确定，需要先验收环境。

## 安装前提

- 本机已安装 Stata (MP/SE/BE)，并可通过 PyStata 调用。
- Python 3.8+ 环境可用。
- 用户允许在当前机器安装命令行工具。

## 安装

```bash
# 方式一：pip（推荐）
python3 -m pip install stata-cli

# 方式二：pipx（隔离环境）
pipx install stata-cli

# 方式三：uvx（无需预先安装）
uvx stata-cli detect
```

## 查找 Stata 路径

```bash
# macOS 常见路径
ls -d /Applications/Stata*/stata-se /Applications/Stata*/StataSE.app/Contents/MacOS/stata* 2>/dev/null

# Stata CLI 自动检测
stata-cli detect

# 手动指定：设置环境变量
export STATA_PATH="/Applications/Stata"
stata-cli --stata-path "$STATA_PATH" --edition mp detect
```

`--edition` 可选值：`mp`（多核）、`se`（标准）、`be`（基础）。默认 `mp`。

## 验收步骤

```bash
STATA_CLI="${STATA_CLI:-$(command -v stata-cli)}"
test -n "$STATA_CLI" || { echo "未找到 stata-cli"; exit 1; }

# 1. 检测 Stata
"$STATA_CLI" detect

# 2. 运行测试命令
"$STATA_CLI" --stata-path "${STATA_PATH:-/Applications/Stata}" --edition mp --compact --no-daemon run "display 1+1"
```

若 `detect` 能识别 Stata，且测试命令返回 `2`，则环境就绪。

## 运行 `.do` 文件

analysis 模块默认把生产逻辑写入 `.do` 文件，再执行：

```bash
STATA_CLI="${STATA_CLI:-$(command -v stata-cli)}"
"$STATA_CLI" --stata-path "${STATA_PATH:-/Applications/Stata}" --edition mp --compact --no-daemon do "analysis-output/scripts/main-analysis.do"
```

- `--compact`：精简输出（多步回归时避免控制台被中间结果淹没）
- `--no-daemon`：不使用后台 daemon 模式，确保日志完整
- 涉及多步清洗、回归、导出时，优先使用 `do` 文件；临时探测才使用 `run`。

## 常用选项

| 选项 | 用途 | 默认 |
|------|------|------|
| `--stata-path` | Stata 安装目录 | 自动检测 |
| `--edition` | mp / se / be | mp |
| `--compact` | 精简输出 | false |
| `--no-daemon` | 不启动后台进程 | false |
| `--timeout` | 超时(秒) | 300 |

## 失败处理

| 症状 | 原因 | 解决 |
|------|------|------|
| `command -v stata-cli` 为空 | 未安装 | `python3 -m pip install stata-cli` |
| `detect` 找不到 Stata | 路径不在默认位置 | 设置 `STATA_PATH` 指向安装目录 |
| PyStata 不可用 | 授权或许可证问题 | 确认 Stata 已激活，`stata -e` 可直接运行 |
| `do` 命令超时 | .do 文件执行时间过长 | 增加 `--timeout`（如 `--timeout 1800`） |
| 输出乱码 | 编码问题 | .do 文件保存为 UTF-8；Stata 18+ 默认支持 Unicode |
| 无 GUI 环境报错 | Stata 依赖图形界面 | 使用 `--no-daemon`；确认许可证允许命令行调用 |

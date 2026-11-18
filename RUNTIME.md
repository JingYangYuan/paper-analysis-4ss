# 运行期依赖获取

本包不随包分发第三方编译产物（R site-library 与 Stata ado 快照）。三种获取方式：

1. 默认：在线安装——R 用 `install.packages()`（见 `references/r-ecosystem-setup.md` §3），Stata 用 `ssc install`（包清单 `templates/_shared/stata-packages.txt`，见 `references/stata-ecosystem-setup.md` §4）。
2. 复现：R 用 `renv` 锁文件；Stata 按包清单逐包安装。
3. 离线：从 runtime 仓库 Release 下载快照 zip，解压到 `<skill>/runtime/`，加载方式见 `templates/_shared/runtime-README.md`。

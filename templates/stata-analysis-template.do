version 17
clear all
set more off
set linesize 120

* ============================================================================
* Paper Analysis 4SS — Stata 完整分析工作流模板
* 基于《"傻瓜"计量经济学与Stata应用》（第二版）习明明
*
* 模式: cleaning → describe → regression → causal → export
* 使用前编辑 PROJECT_ROOT, DATA_PATH 和变量宏块。
* ============================================================================

********************************************************************************
* 00. 项目配置
********************************************************************************

global PROJ "/path/to/project"
global DATA_PATH "$PROJ/data/raw/data.dta"
global OUT "$PROJ/analysis-output"

cd "$PROJ"
capture mkdir "analysis-output"
capture mkdir "$OUT"
foreach d in data scripts tables figures reports qual qual/codebooks qual/coded-data qual/memos qual/anonymized qual/reliability {
    capture mkdir "$OUT/`d'"
}

capture log close _all
log using "$OUT/reports/stata-analysis.log", replace text

* --- 可选包检查 -----------------------------------------------
* 按需安装，不机械全装。项目中用到哪个方法才装对应包。
local optional_pkgs reghdfe ftools estout coefplot winsor2 ///
    ivreg2 ivreghdfe ranktest ///
    rdrobust rddensity ///
    psmatch2 pstest ///
    csdid eventstudyinteract did_imputation did2s ///
    synth sdid synth_runner ///
    spmat spweight spautoreg xsmle gs2slsxt spregdpd ///
    outreg2 asdoc ///
    xtserial xtcd xtqreg xtlsdvc sgmediation xtfrontier

foreach p of local optional_pkgs {
    capture which `p'
    if _rc di as txt "可选包未安装: `p' | 需要时运行: ssc install `p', replace"
}

* 常用安装命令（按需取消注释）:
* ssc install reghdfe, replace
* ssc install ftools, replace
* ssc install estout, replace
* ssc install coefplot, replace
* ssc install winsor2, replace
* ssc install ivreg2, replace
* ssc install ivreghdfe, replace
* ssc install ranktest, replace
* ssc install rdrobust, replace
* ssc install rddensity, replace
* ssc install psmatch2, replace
* ssc install pstest, replace
* ssc install csdid, replace
* ssc install eventstudyinteract, replace
* net install did_imputation, from("https://raw.githubusercontent.com/borusyak/did_imputation/master/") replace
* ssc install did2s, replace
* ssc install synth, replace
* ssc install sdid, replace
* ssc install synth_runner, replace
* ssc install outreg2, replace
* ssc install asdoc, replace
* ssc install xtserial, replace
* ssc install xtcd, replace
* ssc install xtqreg, replace
* ssc install xtlsdvc, replace
* ssc install sgmediation, replace
* ssc install xtfrontier, replace
* * 空间计量包:
* ssc install spmat, replace
* ssc install spweight, replace
* ssc install spautoreg, replace
* ssc install xsmle, replace
* ssc install gs2slsxt, replace
* ssc install spregdpd, replace

********************************************************************************
* 01. 变量映射 — 编辑此块
********************************************************************************

global Y        "outcome"          // 因变量
global X        "treatment"        // 核心解释变量
global C        "age gender education income"  // 控制变量
global FE       "i.year i.region"  // 虚拟变量形式固定效应
global ABSORB   "region year"      // reghdfe 吸收的固定效应
global CLUSTER  "region"           // 聚类层级（按处理分配层级）
global WEIGHT   ""                 // 权重变量（留空 = 无权重）
global ID       "pid"              // 个体标识
global TIME     "year"             // 时间标识

* --- 因果识别变量（不适用则留空）---
global TREAT    "treated"          // 处理组标识
global POST     "post"             // 处理后时期
global GVAR     "first_treat_year" // 首次处理年份（多期DID）
global EVENT    "rel_year"         // 相对事件时间
global ENDOG    "endog_x"          // 内生变量
global IV       "instrument_z"     // 工具变量
global RUNNING  "running_score"    // RDD运行变量
global CUTOFF   "0"                // RDD断点
global MEDIATOR "mediator"         // 中介变量
global MODERATOR "moderator"       // 调节变量

********************************************************************************
* 02. 加载、检查与变量字典
********************************************************************************

use "$DATA_PATH", clear
compress
describe
codebook $Y $X $C, compact
misstable summarize $Y $X $C

* 导出变量字典骨架
preserve
clear
set obs 1
gen raw_name = ""
gen clean_name = ""
gen label = ""
gen role = ""
gen type = ""
gen missing_rule = ""
gen transform = ""
gen source_file = "$DATA_PATH"
gen notes = ""
export delimited using "$OUT/data/variable-dictionary.csv", replace
restore

********************************************************************************
* 03. 数据清洗与样本构建
********************************************************************************

* 缺失值编码（按项目实际调整）
* mvdecode _all, mv(-9 -8 -7 -99 -999)

* 变量变换示例
* destring income, replace ignore(",")
* replace income = . if income < 0
* gen ln_income = ln(income + 1) if income >= 0
* egen z_index = std(index_raw)
* encode province_name, gen(province)
* label define yesno 0 "No" 1 "Yes"
* label values $X yesno

* --- 缩尾处理（去极端值但不丢样本）---
capture noisily winsor2 $Y $X $C, cuts(1 99) replace

* --- 数据合并（按需使用）---
* merge 1:1 $ID $TIME using "supplement.dta", nogen
* merge m:1 $ID using "cross_section.dta", keep(match) nogen

* --- 缺失值插值（面板数据）---
* bysort $ID ($TIME): ipolate $Y $TIME, gen(Y_ip) epolate

* --- 主成分分析（构建综合指标）---
* pca var1 var2 var3
* predict pc1 pc2, score

* 重复值与面板唯一性检查
capture duplicates report $ID $TIME
capture isid $ID $TIME
if _rc {
    di as error "ID-time 不唯一。请在面板模型前解决重复值问题。"
}

* 分析样本标记
gen byte analysis_sample = 1
foreach v in $Y $X $C {
    capture confirm variable `v'
    if !_rc replace analysis_sample = 0 if missing(`v')
}

* 样本流失表
preserve
clear
input str40 step str80 rule n_before n_after dropped str80 reason
"0" "raw data" . . . "填入项目实际数据后更新"
end
export delimited using "$OUT/tables/sample-flow.csv", replace
restore

count
local n_raw = r(N)
count if analysis_sample == 1
local n_analysis = r(N)
di as result "原始 N = `n_raw'; 分析 N = `n_analysis'"

keep if analysis_sample == 1
save "$OUT/data/analysis-data.dta", replace

********************************************************************************
* 04. 描述统计
********************************************************************************

* 全样本描述统计
estpost summarize $Y $X $C, detail
esttab using "$OUT/tables/table1-descriptives.csv", ///
    cells("mean(fmt(3)) sd(fmt(3)) min(fmt(3)) max(fmt(3)) count(fmt(0))") replace

* 分组描述 + t检验（组间平衡性）
capture estpost tabstat $Y $C, by($X) statistics(n mean sd) columns(statistics)
capture esttab using "$OUT/tables/table1b-balance.csv", replace

* 相关矩阵
capture pwcorr $Y $X $C, star(0.05)
capture estpost correlate $Y $X $C, matrix
capture esttab using "$OUT/tables/table1c-correlation.csv", replace

* 基础图形（同时导出 PNG 预览和 PDF 排版）
capture histogram $Y, name(hist_y, replace) normal
capture graph export "$OUT/figures/dist-outcome.png", replace width(1600)
capture graph export "$OUT/figures/dist-outcome.pdf", replace

capture graph twoway (scatter $Y $X) (lfit $Y $X), name(scatter_yx, replace)
capture graph export "$OUT/figures/scatter-yx.png", replace width(1600)

********************************************************************************
* 05. 基准回归 (OLS + 诊断)
********************************************************************************

* --- 逐步回归 ---
* M1: 仅核心解释变量
regress $Y $X, vce(cluster $CLUSTER)
estimates store m1

* M2: + 控制变量
regress $Y $X $C, vce(cluster $CLUSTER)
estimates store m2

* M3: + 固定效应
regress $Y $X $C $FE, vce(cluster $CLUSTER)
estimates store m3

* --- OLS 诊断（在 non-robust 下做，诊断完再加 robust）---
quietly regress $Y $X $C $FE
* 共线性
estat vif
* 异方差
estat hettest, iid
estat imtest, white
* 自相关（时间序列/面板）
capture estat bgodfrey
capture estat dwstat
* 残差正态性
capture predict _resid_ols, residuals
capture swilk _resid_ols
capture drop _resid_ols

* --- 高维固定效应 ---
capture noisily reghdfe $Y $X $C, absorb($ABSORB) vce(cluster $CLUSTER)
if !_rc estimates store hdfe1

* --- 输出回归表 ---
esttab m1 m2 m3 using "$OUT/tables/table2-main-regression.rtf", ///
    b(3) t(3) star(* 0.05 ** 0.01 *** 0.001) label nogaps ///
    stats(N r2, fmt(0 3) labels("N" "R-squared")) ///
    addnotes("括号内为 t 统计值；标准误按 $CLUSTER 聚类。" ///
             "控制变量: $C。固定效应: $FE。") replace

esttab m1 m2 m3 using "$OUT/tables/table2-main-regression.csv", ///
    b(3) t(3) star(* 0.05 ** 0.01 *** 0.001) label nogaps ///
    stats(N r2, fmt(0 3) labels("N" "R-squared")) replace

* 替代: outreg2 格式
* outreg2 [m1 m2 m3] using "$OUT/tables/table2-main-regression.doc", ///
*     word replace dec(3) tstat addtext(Cluster, $CLUSTER)

********************************************************************************
* 06. 非线性模型 (Logit/Probit/Tobit/Heckman)
********************************************************************************

* --- 二值选择模型 ---
* Logit
capture noisily logit $Y $X $C $FE, vce(cluster $CLUSTER)
if !_rc {
    estimates store logit1
    * 边际效应（必须报告，不能只报系数）
    margins, dydx($X) post
    estimates store ame_logit
    * 预测概率（指定值）
    margins, at($X=(0 1)) atmeans
    * 分类表
    estat classification
    * ROC
    lroc
}

* Probit（稳健性）
capture noisily probit $Y $X $C $FE, vce(cluster $CLUSTER)
if !_rc {
    estimates store probit1
    margins, dydx($X) post
    estimates store ame_probit
}

* --- 有序结果 ---
* capture noisily ologit $Y $X $C $FE, vce(cluster $CLUSTER)
* if !_rc margins, dydx(*) predict(outcome(#))

* --- 无序多分类 ---
* capture noisily mlogit $Y $X $C, baseoutcome(1) vce(cluster $CLUSTER)
* if !_rc margins, dydx(*) predict(outcome(#))

* --- 计数数据 ---
* Poisson (PPML)
* capture noisily poisson $Y $X $C $FE, vce(cluster $CLUSTER)
* if !_rc {
*     estimates store poisson1
*     margins, dydx($X)
* }
* 负二项（过度离散）
* capture noisily nbreg $Y $X $C $FE, vce(cluster $CLUSTER)

* --- 受限因变量 ---
* Tobit (审查)
* capture noisily tobit $Y $X $C, ll(0) vce(cluster $CLUSTER)
* if !_rc margins, dydx(*) predict(ystar(0,.))
* Heckman 样本选择
* capture noisily heckman $Y $X $C, select(select_var = $IV $C) twostep

********************************************************************************
* 07. 面板数据模型
********************************************************************************

* --- 面板设定（面板分析前提）---
capture noisily xtset $ID $TIME

* --- 面板描述 ---
capture xtsum $Y $X
capture xtdes

* --- 面板平稳性检验（长面板时使用）---
* capture xtunitroot ips $Y, demean lags(1)
* capture xtunitroot fisher $Y, dfuller lags(1)

* --- 混合OLS (基准) ---
regress $Y $X $C, vce(cluster $CLUSTER)
estimates store pooled

* --- 固定效应 (FE) ---
xtreg $Y $X $C, fe vce(cluster $CLUSTER)
estimates store fe

* --- 随机效应 (RE) ---
xtreg $Y $X $C, re vce(cluster $CLUSTER)
estimates store re

* --- Hausman 检验 (FE vs RE) ---
capture hausman fe re
* H0: RE 一致有效 → p>0.05 用 RE；p<0.05 用 FE

* --- 双向固定效应 ---
capture noisily reghdfe $Y $X $C, absorb($ID $TIME) vce(cluster $CLUSTER)
if !_rc estimates store twfe

* --- 面板 IV ---
* capture noisily xtivreg2 $Y $C ($ENDOG = $IV), fe cluster($CLUSTER)

* --- 交互固定效应 ---
* capture noisily ivreghdfe $Y $C ($ENDOG = $IV), absorb($ID $TIME) cluster($CLUSTER)

* --- 动态面板 GMM ---
* 差分 GMM (Arellano-Bond)
* capture noisily xtabond2 $Y L.$Y $X $C, gmm(L.$Y) iv($C) robust
* if !_rc {
*     estimates store diff_gmm
*     estat abond           // AR(2) 检验: p>0.05
*     estat sargan           // 过度识别: p>0.05
* }
* 系统 GMM (Blundell-Bond)
* capture noisily xtabond2 $Y L.$Y $X $C, gmm(L.$Y) iv($C) robust twostep
* if !_rc estimates store sys_gmm

* --- 长面板 (N小T大) ---
* DK 标准误
* capture noisily xtscc $Y $X $C, fe
* PCSE
* capture noisily xtpcse $Y $X $C
* 面板 FGLS
* capture noisily xtgls $Y $X $C, panels(hetero) corr(ar1)
* 偏差校正 LSDV
* capture noisily xtlsdvc $Y L.$Y $X $C, initial(ab)

* --- 面板诊断 ---
* Wooldridge 自相关检验
capture xtserial $Y $X $C
* 截面相关检验
capture xtcd $Y

* --- 面板模型输出 ---
capture esttab pooled fe re using "$OUT/tables/table3-panel-models.rtf", ///
    b(3) t(3) star(* 0.05 ** 0.01 *** 0.001) label nogaps ///
    stats(N r2_w, fmt(0 3) labels("N" "Within R2")) ///
    addnotes("括号内为 t 统计值。FE 和 RE 标准误按 $CLUSTER 聚类。") replace

********************************************************************************
* 08. 工具变量回归 (IV/2SLS/GMM)
********************************************************************************

* --- 第一阶段（必须报告）---
capture noisily regress $ENDOG $IV $C $FE, vce(cluster $CLUSTER)
if !_rc {
    estimates store first_stage
    * F 检验: H0: IV系数=0, F>10 通过弱IV检验
    test $IV
    local F_first = r(F)
    di as result "第一阶段 F 统计量 = `F_first'"
}

* --- 2SLS ---
capture noisily ivregress 2sls $Y $C $FE ($ENDOG = $IV), vce(cluster $CLUSTER)
if !_rc {
    estimates store iv_2sls
    * 弱IV诊断
    estat firststage
    * 过度识别检验（只当工具变量数 > 内生变量数时可用）
    capture estat overid
    * 内生性检验
    capture estat endogenous
}

* --- LIML (多弱IV时优于2SLS) ---
* capture noisily ivregress liml $Y $C $FE ($ENDOG = $IV), vce(cluster $CLUSTER)

* --- GMM (异方差下比2SLS更有效) ---
* capture noisily ivreg2 $Y $C $FE ($ENDOG = $IV), gmm2s robust cluster($CLUSTER)
* if !_rc {
*     estimates store gmm1
*     * Hansen J 检验（异方差稳健的过度识别）
*     capture estat overid
* }

* --- 高维固定效应 IV ---
* capture noisily ivreghdfe $Y $C ($ENDOG = $IV), absorb($ABSORB) cluster($CLUSTER) first

* --- IV 输出 ---
capture esttab first_stage iv_2sls using "$OUT/tables/table4-iv-results.rtf", ///
    b(3) t(3) star(* 0.05 ** 0.01 *** 0.001) label nogaps ///
    stats(N, fmt(0) labels("N")) ///
    addnotes("第一阶段 F = `F_first'。") replace

********************************************************************************
* 09. 双重差分 (DID) 与事件研究
********************************************************************************

* --- 标准 DID (2x2) ---
gen treat_post = $TREAT * $POST
regress $Y $TREAT $POST treat_post $C, vce(cluster $CLUSTER)
estimates store did_2x2

* --- 面板 TWFE-DID ---
capture noisily reghdfe $Y treat_post $C, absorb($ID $TIME) vce(cluster $CLUSTER)
if !_rc estimates store did_twfe

* --- Stata 17+ 官方 DID ---
* capture noisily didregress ($Y $C) (treat_post), group($ID) time($TIME)
* capture noisily xtdidregress ($Y $C) (treat_post), group($ID) time($TIME)

* --- 事件研究法（平行趋势检验）---
* 需先生成相对时间虚拟变量
* capture noisily eventstudyinteract $Y $EVENT, cohort($GVAR) ///
*     control_cohort(never_treated) absorb($ID $TIME) vce(cluster $CLUSTER)

* --- 多期DID 异质性稳健估计（交错处理时优先使用）---
* Callaway-Sant'Anna
capture noisily csdid $Y $C, ivar($ID) time($TIME) gvar($GVAR) method(dripw) cluster($CLUSTER)
if !_rc {
    estat simple
    estat event
}
* Borusyak-Jaravel-Spiess 插补法
capture noisily did_imputation $Y $ID $TIME $GVAR, controls($C) fe($ID $TIME) cluster($CLUSTER)
* 两阶段 DID (Gardner)
capture noisily did2s $Y, treatment(treat_post) first_stage(i.$ID i.$TIME) second_stage(i.$ID)

* --- PSM-DID ---
* psmatch2 $TREAT $C, outcome($Y) logit ate
* pstest $C, both graph
* * 匹配后用匹配权重重新做DID

* --- 安慰剂检验 ---
* 时间安慰剂: 将处理时间前置到真实处理前
* gen treat_pre = $TREAT * (year >= fake_treat_year)
* reg $Y $TREAT treat_pre $C, vce(cluster $CLUSTER)
* * treat_pre 应不显著

********************************************************************************
* 10. 断点回归 (RDD)
********************************************************************************

* 中心化运行变量
capture gen running_c = $RUNNING - $CUTOFF

* RDD 可视化
capture noisily rdplot $Y running_c, c(0)
capture graph export "$OUT/figures/rdplot.png", replace width(1600)

* 密度检验（操纵检验）
capture noisily rddensity running_c, c(0)

* 主估计 (rdrobust: 现代标准做法, 三角核+ MSE最优带宽)
capture noisily rdrobust $Y running_c, c(0) kernel(triangular) covs($C) cluster($CLUSTER)
if !_rc estimates store rdd_main

* 模糊 RDD
* capture noisily rdrobust $Y running_c, c(0) fuzzy($TREAT)

* --- RDD 稳健性 ---
* 带宽敏感性 (0.5x, 2x 最优带宽)
* local h_opt = e(h_l)
* capture noisily rdrobust $Y running_c, c(0) h(`=0.5*`h_opt'')
* capture noisily rdrobust $Y running_c, c(0) h(`=2*`h_opt'')
* 安慰剂断点（伪断点位置）
* capture noisily rdrobust $Y running_c, c(-5)
* 协变量平滑性（断点处协变量不应跳跃）
* foreach v in $C {
*     capture noisily rdrobust `v' running_c, c(0)
* }

********************************************************************************
* 11. 匹配方法 (PSM / CEM / 熵平衡)
********************************************************************************

* --- PSM 倾向得分匹配 ---
capture noisily psmatch2 $TREAT $C, outcome($Y) logit ate common
if !_rc {
    * 平衡性检验
    pstest $C, both graph
    graph export "$OUT/figures/psm-balance.png", replace width(1600)
    * 共同支撑域图
    psgraph
    graph export "$OUT/figures/psm-support.png", replace width(1600)
}

* --- CEM 广义精确匹配 ---
* capture noisily cem $C, treatment($TREAT)

* --- 熵平衡匹配 ---
* capture noisily ebalance $TREAT $C, target(3)

* --- Stata 官方 teffects ---
* capture noisily teffects psmatch ($Y) ($TREAT $C), atet vce(robust)
* capture noisily teffects ipwra ($Y $C) ($TREAT $C), atet vce(robust)
* capture noisily teffects nnmatch ($Y $C) ($TREAT), atet

********************************************************************************
* 12. 合成控制法 (SCM)
********************************************************************************

* 单一试点
* synth $Y predictor1 predictor2 $Y(2010) $Y(2011), ///
*     trunit(1) trperiod(2015) unitnames(unit_name) ///
*     keep("$OUT/data/synth-results.dta") replace

* 合成 DID
* capture noisily sdid $Y $ID $TIME $TREAT, vce(placebo) seed(20260609) graph
* capture graph export "$OUT/figures/sdid.png", replace width(1600)

********************************************************************************
* 13. 分位数回归
********************************************************************************

* 截面分位数
* capture noisily qreg $Y $X $C, quantile(0.5)
* capture noisily sqreg $Y $X $C, quantile(0.25 0.5 0.75) reps(100)
* * 跨分位数系数相等检验
* capture test [q25=q50=q75]: $X

* 面板分位数
* capture noisily xtqreg $Y $X $C, fe quantile(0.5)

********************************************************************************
* 14. 中介效应与调节效应
********************************************************************************

* --- 中介效应（逐步法 + Bootstrap）---
* Step 1: X → Y
regress $Y $X $C $FE, vce(cluster $CLUSTER)
* Step 2: X → M
regress $MEDIATOR $X $C $FE, vce(cluster $CLUSTER)
* Step 3: X + M → Y
regress $Y $X $MEDIATOR $C $FE, vce(cluster $CLUSTER)
* Bootstrap 间接效应
capture noisily sgmediation $Y, iv($X) mv($MEDIATOR) cv($C)

* --- 调节效应（交互项 + 边际效应图）---
capture noisily regress $Y c.$X##c.$MODERATOR $C $FE, vce(cluster $CLUSTER)
if !_rc {
    estimates store interact1
    margins, dydx($X) at($MODERATOR = (0(1)5))
    marginsplot, name(margins_interact, replace)
    graph export "$OUT/figures/marginal-effects-interaction.png", replace width(1600)
    graph export "$OUT/figures/marginal-effects-interaction.pdf", replace
}

* --- 非线性模型交互项（必须用 margins cross difference）---
* logit $Y c.$X##c.$MODERATOR $C $FE, vce(cluster $CLUSTER)
* margins, dydx($X) at($MODERATOR = (0 1))
* marginsplot

********************************************************************************
* 15. 时间序列分析
********************************************************************************

* --- 时间序列设定 ---
* tsset $TIME

* --- 自相关诊断 ---
* corrgram $Y, lags(20)
* ac $Y
* pac $Y

* --- 单位根检验 ---
* dfuller $Y, lags(4) reg
* pperron $Y
* dfgls $Y

* --- ARMA/ARMAX ---
* arima $Y $X, ar(1) ma(1)

* --- VAR ---
* var $Y var2 var3, lags(1/4)
* varsoc $Y var2 var3, maxlag(8)
* vargranger
* varstable, graph
* irf create model1, step(10) set(filename) replace
* irf graph oirf

* --- VECM (协整) ---
* vecrank $Y var2 var3, lags(4) trend(trend)
* vec $Y var2 var3, lags(3) rank(1)

********************************************************************************
* 16. 非参数与半参数估计
********************************************************************************

* 核回归（局部线性）
* capture noisily npregress kernel $Y $X, vce(boot, reps(50))
* capture npgraph

* 局部多项式平滑
* capture lpoly $Y $X

* 核密度
* capture kdensity $Y, name(kdens_y, replace)
* capture graph export "$OUT/figures/density-y.png", replace width(1600)

********************************************************************************
* 17. 空间计量经济学（可选）
********************************************************************************

* --- 空间权重矩阵 ---
* 邻接矩阵
* capture spmatrix create contiguity W
* 反距离矩阵
* capture spmatrix create idistance M

* --- 空间自相关诊断 ---
* 先用 OLS
* quietly regress $Y $X $C
* estat moran, errorlag(W)

* --- 截面空间模型 ---
* SAR (GS2SLS)
* capture spregress $Y $X $C, gs2sls dvarlag(W)
* SDM (GS2SLS)
* capture spregress $Y $X $C, gs2sls dvarlag(W) ivarlag(W: $X $C)
* SEM (GS2SLS)
* capture spregress $Y $X $C, gs2sls errorlag(W)
* 效应分解
* capture estat impact

* --- 空间面板 ---
* capture spxtregress $Y $X $C, fe dvarlag(W)

********************************************************************************
* 18. Bootstrap / Jackknife 推断
********************************************************************************

* Bootstrap 标准误（reps >= 384 for 95% CI, 10% error tolerance）
* capture bootstrap, reps(500) seed(12345): regress $Y $X $C $FE

* Jackknife
* capture jackknife: regress $Y $X $C $FE

********************************************************************************
* 19. 稳健性检验
********************************************************************************

* (1) 替代因变量口径
* regress Y_alt $X $C $FE, vce(cluster $CLUSTER)
* estimates store robust_yalt

* (2) 替代核心解释变量口径
* regress $Y X_alt $C $FE, vce(cluster $CLUSTER)
* estimates store robust_xalt

* (3) 子样本（剔除特定群体）
* preserve
* keep if subgroup_condition == 1
* regress $Y $X $C $FE, vce(cluster $CLUSTER)
* estimates store robust_subsample
* restore

* (4) 替代标准误层级
* regress $Y $X $C $FE, vce(cluster alt_cluster)
* estimates store robust_se

* (5) 加入/移除固定效应
* regress $Y $X $C, vce(cluster $CLUSTER)
* estimates store robust_nofe

* (6) 排除极端值（截尾 vs 缩尾对比）
* capture winsor2 $Y $X, cuts(5 95) suffix(_w5)
* regress ${Y}_w5 ${X}_w5 $C $FE, vce(cluster $CLUSTER)

* (7) 排除竞争性假设
* * 加入可能混淆的额外控制变量
* regress $Y $X $C extra_confound $FE, vce(cluster $CLUSTER)

********************************************************************************
* 20. 边际效应与预测
********************************************************************************

* 非线性模型边际效应
* AME (平均边际效应) — 最常用
* capture margins, dydx(*) post
* MEM (均值处边际效应)
* capture margins, dydx(*) atmeans post
* MER (代表性值处)
* capture margins, at($X=(0 1 2 3)) atmeans

* 弹性
* capture margins, eyex($X)

* 非线性预测 + 标准误
* capture predictnl yhat = _b[_cons] + _b[$X]*$X + _b[age]*age, se(se_yhat)

********************************************************************************
* 21. 结果导出与报告骨架
********************************************************************************

* --- 脚本索引 ---
file open idx using "$OUT/reports/script-index.md", write replace
file write idx "# Script Index" _n _n
file write idx "| Order | Script | Input | Output | Notes |" _n
file write idx "|---|---|---|---|---|" _n
file write idx "| 1 | stata-analysis-template.do | $DATA_PATH | $OUT/ | 编辑宏块后运行 |" _n
file close idx

* --- 模型决策记录 ---
file open mdr using "$OUT/reports/model-decision-`c(current_date)'.md", write replace
file write mdr "# 模型决策记录" _n _n
file write mdr "## 基础信息" _n _n
file write mdr "- 研究问题：" _n
file write mdr "- 因变量类型：" _n
file write mdr "- 数据结构：" _n
file write mdr "- 核心解释变量：" _n _n
file write mdr "## 模型选择" _n _n
file write mdr "- 主模型：" _n
file write mdr "- 标准误/聚类层级：" _n
file write mdr "- 固定效应：" _n
file write mdr "- 可解释为因果吗：" _n _n
file write mdr "## 诊断结果" _n _n
file write mdr "| 检验 | 统计量 | 阈值 | 通过? |" _n
file write mdr "|---|---|---|---|" _n
file write mdr "## 稳健性" _n _n
file write mdr "- 必做：" _n
file write mdr "- 已做：" _n _n
file write mdr "## 不足与风险" _n
file close mdr

* --- 结果报告骨架 ---
file open rep using "$OUT/reports/regression-results-`c(current_date)'.md", write replace
file write rep "# 分析结果" _n _n
file write rep "## 1. 数据与样本" _n _n
file write rep "## 2. 变量与测量" _n _n
file write rep "## 3. 描述统计" _n _n
file write rep "## 4. 主回归结果" _n _n
file write rep "## 5. 识别诊断" _n _n
file write rep "## 6. 稳健性检验" _n _n
file write rep "## 7. 异质性与机制" _n _n
file write rep "## 8. 局限性" _n
file close rep

log close
di as result _n "=== 分析完成 ==="
di as result "输出目录: $OUT/"
di as result "日志文件: $OUT/reports/stata-analysis.log"

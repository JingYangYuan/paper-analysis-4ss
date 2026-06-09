version 17
clear all
set more off

* Paper Analysis 4SS - Stata template
* Fill PROJECT_ROOT and DATA_PATH before running.

global PROJ "/path/to/project"
global DATA_PATH "$PROJ/data/raw/data.dta"
global OUT "$PROJ/output/paper-analysis"

cd "$PROJ"
capture mkdir "output"
capture mkdir "$OUT"
capture mkdir "$OUT/data"
capture mkdir "$OUT/scripts"
capture mkdir "$OUT/tables"
capture mkdir "$OUT/figures"
capture mkdir "$OUT/reports"
capture log close
log using "$OUT/reports/stata-analysis.log", replace text

* 01. Load and inspect
use "$DATA_PATH", clear
describe
misstable summarize

* Required variables: edit these names
global Y "outcome"
global X "treatment"
global C "age gender education income"
global FE "i.year i.region"
global CLUSTER "region"
global ID "pid"
global TIME "year"

* 02. Minimal cleaning examples
* destring income, replace ignore(",")
* replace income = . if income < 0
* gen ln_income = ln(income + 1)
* egen z_index = std(index_raw)
* duplicates report $ID $TIME

* Sample flag and sample-flow
gen analysis_sample = !missing($Y, $X)
foreach v of global C {
    replace analysis_sample = 0 if missing(`v')
}
tab analysis_sample
export delimited using "$OUT/tables/sample-flow.csv", replace

keep if analysis_sample == 1
save "$OUT/data/analysis-data.dta", replace

* 03. Descriptives
estpost summarize $Y $X $C
esttab using "$OUT/tables/table1-descriptives.csv", ///
    cells("mean(fmt(3)) sd(fmt(3)) min(fmt(3)) max(fmt(3)) count(fmt(0))") replace

* 04. OLS / FE
regress $Y $X $C, vce(cluster $CLUSTER)
estimates store m1

regress $Y $X $C $FE, vce(cluster $CLUSTER)
estimates store m2

* reghdfe example, if installed:
* reghdfe $Y $X $C, absorb(region year) vce(cluster $CLUSTER)
* estimates store m3

esttab m1 m2 using "$OUT/tables/table2-main-regression.rtf", ///
    b(3) t(3) star(* 0.05 ** 0.01 *** 0.001) label nogaps ///
    addnotes("括号内为 t/z 统计值；标准误类型和聚类层级见正文或表注。") replace
esttab m1 m2 using "$OUT/tables/table2-main-regression.csv", ///
    b(3) t(3) star(* 0.05 ** 0.01 *** 0.001) label nogaps ///
    addnotes("括号内为 t/z 统计值；标准误类型和聚类层级见正文或表注。") replace

* 05. Logit / probit with AME
* logit binary_y $X $C $FE, vce(cluster $CLUSTER)
* estimates store logit1
* margins, dydx($X) post
* estimates store ame1
* esttab ame1 using "$OUT/tables/table3-ame.csv", b(3) t(3) nogaps replace

* 06. Panel FE / RE
* xtset $ID $TIME
* xtreg $Y $X $C i.year, fe vce(cluster $ID)
* estimates store fe
* xtreg $Y $X $C i.year, re vce(cluster $ID)
* estimates store re
* hausman fe re

* 07. Basic DiD / event study
* gen did = treated * post
* regress $Y treated post did $C i.year i.region, vce(cluster $CLUSTER)
* estimates store did_main
* Event-study requires relative_time dummies; create before running.

* 08. IV / 2SLS
* ivregress 2sls $Y $C (endog_x = instrument), vce(cluster $CLUSTER)
* estat firststage

* 09. Robustness placeholder
* winsor2 $Y $X, cuts(1 99) replace
* rerun main models and export tableA1.

log close

"""
Paper Analysis 4SS — Python 完整分析工作流模板
理论框架参考: model-router.md (诊断阈值/内生性判断/面板选择/空间依赖)

覆盖: cleaning → descriptives → regression → causal → export
使用前编辑 PROJECT_ROOT, DATA_PATH, 和 VarMap。
"""

from __future__ import annotations

import os, re, warnings
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd
from scipy import stats as sp_stats

warnings.filterwarnings("ignore", category=FutureWarning)

PROJECT_ROOT = Path(os.environ.get("PROJECT_ROOT", "."))
OUTPUT_ROOT  = Path(os.environ.get("OUTPUT_ROOT", PROJECT_ROOT / "analysis-output"))
DATA_PATH    = Path(os.environ.get("DATA_PATH", PROJECT_ROOT / "data/raw/data.csv"))

for sub in ["data", "scripts", "tables", "figures", "reports",
            "qual/codebooks", "qual/coded-data", "qual/anonymized", "qual/reliability"]:
    (OUTPUT_ROOT / sub).mkdir(parents=True, exist_ok=True)


@dataclass
class VarMap:
    y: str = "outcome"
    x: str = "treatment"
    controls: list[str] = field(default_factory=lambda: ["age", "gender", "education", "income"])
    fe: list[str] = field(default_factory=lambda: ["region", "year"])
    absorb: list[str] = field(default_factory=lambda: ["region", "year"])
    cluster: str | None = "region"
    weight: str | None = None
    id: str = "pid"
    time: str = "year"
    treat: str = "treated"
    post: str = "post"
    gvar: str = "first_treat_year"
    event: str = "rel_year"
    endog: str = "endog_x"
    iv: str = "instrument_z"
    running: str = "running_score"
    cutoff: float = 0.0
    mediator: str = "mediator"
    moderator: str = "moderator"

VARS = VarMap()


def optional_import(module: str):
    try: return __import__(module)
    except ImportError:
        print(f"Optional package not installed: {module}")
        return None


# ============================================================================
# 01. 数据加载与清洗
# ============================================================================

def load_data(path: str | Path) -> pd.DataFrame:
    path = Path(path)
    ext = path.suffix.lower().lstrip(".")
    if ext == "csv":    return pd.read_csv(path)
    if ext == "tsv":    return pd.read_csv(path, sep="\t")
    if ext in {"xlsx", "xls"}: return pd.read_excel(path)
    if ext == "dta":    return pd.read_stata(path)
    if ext == "sav":    return pd.read_spss(path)
    if ext == "parquet": return pd.read_parquet(path)
    if ext == "pkl":    return pd.read_pickle(path)
    raise ValueError(f"Unsupported file type: {ext}")


def clean_column_names(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    out.columns = [
        re.sub(r"_+", "_", re.sub(r"[^0-9a-zA-Z_]+", "_", c.strip().lower())).strip("_")
        for c in out.columns]
    return out


def clean_data(df: pd.DataFrame, special_missing: Iterable[float] = (-9, -8, -7, -99, -999),
               winsor_pct: tuple[float, float] = (0.01, 0.99)) -> pd.DataFrame:
    out = clean_column_names(df)
    for col in out.select_dtypes(include="object").columns:
        out[col] = out[col].astype(str).str.strip().replace({"": np.nan, "nan": np.nan, "None": np.nan})
    num_cols = out.select_dtypes(include=np.number).columns
    out[num_cols] = out[num_cols].replace(list(special_missing), np.nan)
    # 缩尾
    for col in num_cols:
        if col in (VARS.id, VARS.time): continue
        lo, hi = out[col].quantile(winsor_pct[0]), out[col].quantile(winsor_pct[1])
        out[col] = out[col].clip(lo, hi)
    return out.drop_duplicates()


def write_variable_dictionary(df: pd.DataFrame, roles: dict[str, list[str]],
                               source_file: str | Path = DATA_PATH) -> pd.DataFrame:
    rows = []
    for col in df.columns:
        role = ";".join(name for name, vars_ in roles.items() if col in vars_)
        rows.append({"raw_name": col, "clean_name": col, "label": "", "role": role,
                     "type": str(df[col].dtype), "missing_rule": "", "transform": "",
                     "source_file": str(source_file), "notes": ""})
    table = pd.DataFrame(rows)
    table.to_csv(OUTPUT_ROOT / "data/variable-dictionary.csv", index=False)
    return table


def sample_flow(df: pd.DataFrame, y: str, x: str, controls: list[str],
                id_col: str | None = None, time_col: str | None = None):
    current = df.copy()
    rows = [{"step": 0, "rule": "raw data", "n_before": np.nan, "n_after": len(current),
             "dropped": np.nan, "reason": "raw"}]
    step = 1
    for var in [y, x, *controls]:
        before = len(current)
        current = current[current[var].notna()]
        rows.append({"step": step, "rule": f"nonmissing_{var}", "n_before": before,
                     "n_after": len(current), "dropped": before - len(current), "reason": "missing"})
        step += 1
    if id_col and time_col and id_col in current and time_col in current:
        before = len(current)
        current = current.drop_duplicates([id_col, time_col])
        rows.append({"step": step, "rule": "unique_id_time", "n_before": before,
                     "n_after": len(current), "dropped": before - len(current), "reason": "duplicate panel key"})
    flow = pd.DataFrame(rows)
    flow.to_csv(OUTPUT_ROOT / "tables/sample-flow.csv", index=False)
    return current, flow


# ============================================================================
# 02. 描述统计
# ============================================================================

def describe_data(df: pd.DataFrame, vars_: list[str]) -> pd.DataFrame:
    table = df[vars_].describe(include="all").T
    numeric_cols = table.select_dtypes(include=[np.number]).columns
    table[numeric_cols] = table[numeric_cols].round(3)
    table.to_csv(OUTPUT_ROOT / "tables/table1-descriptives.csv")
    return table


def balance_table(df: pd.DataFrame, vars_: list[str], group: str) -> pd.DataFrame:
    """分组均值比较 + t检验"""
    rows = []
    for v in vars_:
        g0 = df[df[group] == 0][v].dropna()
        g1 = df[df[group] == 1][v].dropna()
        t_stat, p_val = sp_stats.ttest_ind(g0, g1) if len(g0) > 1 and len(g1) > 1 else (np.nan, np.nan)
        rows.append({"variable": v, "mean_control": g0.mean(), "mean_treated": g1.mean(),
                     "diff": g1.mean() - g0.mean(), "t": t_stat, "p": p_val})
    bal = pd.DataFrame(rows).round(3)
    bal.to_csv(OUTPUT_ROOT / "tables/table1b-balance.csv", index=False)
    return bal


def formula_rhs(variables: list[str]) -> str:
    return " + ".join(variables) if variables else "1"


# ============================================================================
# 03. 可视化协议
# ============================================================================

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns

plt.rcParams["font.sans-serif"] = ["PingFang SC", "Heiti SC", "SimHei", "Microsoft YaHei"]
plt.rcParams["axes.unicode_minus"] = False

FIG_DPI = 300


def save_plot_pair(fig, stem: str, dpi: int = FIG_DPI):
    fig.savefig(OUTPUT_ROOT / "figures" / f"{stem}.pdf", dpi=dpi, bbox_inches="tight")
    fig.savefig(OUTPUT_ROOT / "figures" / f"{stem}.png", dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def theme_paper(ax):
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(True, alpha=0.3)
    if ax.get_legend() is not None:
        ax.legend(frameon=False)
    return ax


# ---- 分布图 ----
def plot_distribution(df, var: str, group: str | None = None, bins: int = 30):
    fig, ax = plt.subplots(figsize=(7, 5))
    if group is None:
        ax.hist(df[var].dropna(), bins=bins, alpha=0.78, color="#2878B5", edgecolor="white")
    else:
        for g in sorted(df[group].dropna().unique()):
            ax.hist(df.loc[df[group] == g, var].dropna(), bins=bins,
                    alpha=0.7, label=str(g), edgecolor="white")
        ax.legend(title=group)
    theme_paper(ax); ax.set_xlabel(var); ax.set_ylabel("Count")
    stem = f"fig-dist-{var}" if group is None else f"fig-dist-{var}-by-{group}"
    save_plot_pair(fig, stem); return fig


# ---- 密度图 ----
def plot_density(df, var: str, group: str | None = None):
    fig, ax = plt.subplots(figsize=(7, 5))
    if group is None:
        df[var].dropna().plot.kde(ax=ax, color="#2878B5", linewidth=1.5)
    else:
        for g in sorted(df[group].dropna().unique()):
            df.loc[df[group] == g, var].dropna().plot.kde(ax=ax, label=str(g), linewidth=1.5)
        ax.legend(title=group)
    theme_paper(ax); ax.set_xlabel(var); ax.set_ylabel("Density")
    save_plot_pair(fig, f"fig-density-{var}"); return fig


# ---- 散点图 + 拟合线 ----
def plot_scatter(df, y: str, x: str, group: str | None = None):
    fig, ax = plt.subplots(figsize=(7, 5))
    if group is None:
        ax.scatter(df[x], df[y], alpha=0.4, s=8, color="#2878B5")
        sns.regplot(x=df[x], y=df[y], scatter=False, ax=ax, color="#c44e52", line_kws={"linewidth": 1})
    else:
        for g in sorted(df[group].dropna().unique()):
            mask = df[group] == g
            ax.scatter(df.loc[mask, x], df.loc[mask, y], alpha=0.4, s=8, label=str(g))
            sns.regplot(x=df.loc[mask, x], y=df.loc[mask, y], scatter=False, ax=ax)
        ax.legend(title=group)
    theme_paper(ax); ax.set_xlabel(x); ax.set_ylabel(y)
    save_plot_pair(fig, f"fig-scatter-{y}-{x}"); return fig


# ---- 分组均值 + CI ----
def plot_group_mean(df, y: str, group: str):
    summary = df.groupby(group)[y].agg(["mean", "sem"]).reset_index()
    summary["lower"] = summary["mean"] - 1.96 * summary["sem"]
    summary["upper"] = summary["mean"] + 1.96 * summary["sem"]
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.errorbar(summary[group], summary["mean"], yerr=1.96 * summary["sem"],
                fmt="o", capsize=5, color="#2c3e50", markersize=5, linewidth=0.8)
    theme_paper(ax); ax.set_xlabel(group); ax.set_ylabel(f"Mean of {y}")
    save_plot_pair(fig, f"fig-group-mean-{y}-by-{group}"); return fig


# ---- 相关矩阵 ----
def plot_correlation(df, vars_: list[str], file_stem: str = "fig-correlation"):
    corr = df[vars_].corr()
    mask = np.triu(np.ones_like(corr, dtype=bool), k=1)
    fig, ax = plt.subplots(figsize=(8, 7))
    sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="RdBu_r",
                center=0, square=True, linewidths=0.5, ax=ax)
    save_plot_pair(fig, file_stem); return fig


# ---- 系数图 ----
def plot_coef(models_dict: dict[str, Any], file_stem: str = "fig-coefplot"):
    rows = []
    for name, model in models_dict.items():
        params = getattr(model, "params", getattr(model, "coef", {}))
        bse    = getattr(model, "bse", getattr(model, "std_errors", {}))
        if isinstance(params, pd.Series):
            for term in params.index:
                if term in ("Intercept", "const"): continue
                se = bse.get(term, bse[term]) if isinstance(bse, (dict, pd.Series)) else np.nan
                rows.append({"model": name, "term": term, "estimate": params[term],
                             "lower": params[term] - 1.96 * se, "upper": params[term] + 1.96 * se})
    if not rows: return None
    coef_df = pd.DataFrame(rows)
    fig, ax = plt.subplots(figsize=(7, 5))
    colors = sns.color_palette("viridis", len(coef_df["model"].unique()))
    for i, (name, grp) in enumerate(coef_df.groupby("model")):
        offset = (i - (len(coef_df["model"].unique()) - 1) / 2) * 0.15
        ax.errorbar(grp["estimate"], np.arange(len(grp)) + offset,
                    xerr=[grp["estimate"] - grp["lower"], grp["upper"] - grp["estimate"]],
                    fmt="o", capsize=3, label=name, color=colors[i], markersize=4)
    ax.set_yticks(range(len(grp))); ax.set_yticklabels(grp["term"])
    ax.axvline(0, linestyle="dashed", color="#666666")
    theme_paper(ax); ax.set_xlabel("Estimate"); ax.legend()
    save_plot_pair(fig, file_stem); return fig


# ---- 诊断四图 ----
def plot_diagnostics(model, file_stem: str = "fig-diagnostics"):
    """Residuals vs Fitted, Q-Q, Scale-Location, Residuals vs Leverage."""
    import statsmodels.api as sm
    fitted = model.fittedvalues
    residuals = model.resid
    std_resid = residuals / np.std(residuals)
    influence = model.get_influence()
    leverage = influence.hat_matrix_diag
    cooks_d = influence.cooks_distance[0]

    fig, axes = plt.subplots(2, 2, figsize=(12, 10))
    axes[0, 0].scatter(fitted, residuals, alpha=0.5, s=10)
    axes[0, 0].axhline(0, color="red", linestyle="dashed", alpha=0.5)
    axes[0, 0].set_xlabel("Fitted"); axes[0, 0].set_ylabel("Residuals")
    axes[0, 0].set_title("Residuals vs Fitted")

    sm.qqplot(residuals, sp_stats.norm, fit=True, line="45", ax=axes[0, 1], alpha=0.5)

    axes[1, 0].scatter(fitted, np.sqrt(np.abs(std_resid)), alpha=0.5, s=10)
    axes[1, 0].set_xlabel("Fitted"); axes[1, 0].set_ylabel(r"$\sqrt{|Std\ Residuals|}$")
    axes[1, 0].set_title("Scale-Location")

    sc = axes[1, 1].scatter(leverage, std_resid, alpha=0.5, s=10, c=cooks_d, cmap="viridis")
    axes[1, 1].axhline(0, color="red", linestyle="dashed", alpha=0.5)
    axes[1, 1].set_xlabel("Leverage"); axes[1, 1].set_ylabel("Std Residuals")
    axes[1, 1].set_title("Residuals vs Leverage")
    plt.colorbar(sc, ax=axes[1, 1], label="Cook's D")
    plt.tight_layout(); save_plot_pair(fig, file_stem); return fig


# ---- 边际效应图 ----
def plot_marginal(model, focal_var: str, df: pd.DataFrame, file_stem: str | None = None):
    focal_seq = np.linspace(df[focal_var].min(), df[focal_var].max(), 50)
    if hasattr(model.model.data, "frame"):
        base = model.model.data.frame.iloc[[0]].copy()
        for col in base.columns:
            if col == focal_var: continue
            if pd.api.types.is_numeric_dtype(base[col]): base[col] = df[col].mean()
            else: base[col] = df[col].mode().iloc[0]
    else:
        base = pd.DataFrame({col: [df[col].mean()] for col in model.model.exog_names
                             if col != focal_var and col in df.columns})
    newdata = pd.concat([base] * 50, ignore_index=True)
    newdata[focal_var] = focal_seq
    pred = model.get_prediction(newdata).summary_frame(alpha=0.05)
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.fill_between(focal_seq, pred["mean_ci_lower"], pred["mean_ci_upper"], alpha=0.2, color="#2878B5")
    ax.plot(focal_seq, pred["mean"], color="#2878B5", linewidth=0.8)
    theme_paper(ax); ax.set_xlabel(focal_var); ax.set_ylabel("Predicted outcome")
    save_plot_pair(fig, file_stem or f"fig-marginal-{focal_var}"); return fig


# ============================================================================
# 04. 基准回归 + 诊断
# ============================================================================

import statsmodels.formula.api as smf

def _fit_ols(fml: str, df: pd.DataFrame, cluster: str | None = None):
    mod = smf.ols(fml, data=df).fit()
    if cluster and cluster in df.columns:
        return mod.get_robustcov_results(cov_type="cluster", groups=df[cluster])
    return mod.get_robustcov_results(cov_type="HC1")


def run_ols(df: pd.DataFrame, y: str, x: str, controls: list[str],
            fe: list[str] | None = None, cluster: str | None = None):
    fe_terms = [f"C({v})" for v in (fe or [])]
    fml = f"{y} ~ {formula_rhs([x, *controls, *fe_terms])}"
    return _fit_ols(fml, df, cluster)


# --- OLS 诊断套件 ---
def run_ols_diagnostics(model) -> dict:
    """VIF, Breusch-Pagan, Durbin-Watson, Jarque-Bera"""
    import statsmodels.api as sm
    diag = {}
    # VIF (需要设计矩阵)
    try:
        from statsmodels.stats.outliers_influence import variance_inflation_factor
        exog = model.model.exog
        vif_data = pd.DataFrame({
            "variable": model.model.exog_names,
            "VIF": [variance_inflation_factor(exog, i) for i in range(exog.shape[1])]})
        diag["vif"] = vif_data
        high_vif = vif_data[vif_data["VIF"] > 10]
        if len(high_vif) > 0:
            print(f"[!] VIF > 10 变量: {list(high_vif['variable'])}")
    except Exception: pass
    # Breusch-Pagan
    try:
        _, bp_pval, _, _ = sm.stats.diagnostic.het_breuschpagan(model.resid, model.model.exog)
        diag["breusch_pagan_p"] = bp_pval
        print(f"--- Breusch-Pagan: p = {bp_pval:.4f} {'[!] 存在异方差' if bp_pval < 0.05 else ''}")
    except Exception: pass
    # Durbin-Watson
    try:
        dw = sm.stats.durbin_watson(model.resid)
        diag["dw"] = dw
        print(f"--- Durbin-Watson: DW = {dw:.3f} {'[!] 自相关' if dw < 1.5 or dw > 2.5 else ''}")
    except Exception: pass
    # Jarque-Bera (正态性)
    try:
        jb_stat, jb_p = sm.stats.jarque_bera(model.resid)
        diag["jarque_bera_p"] = jb_p
        print(f"--- Jarque-Bera: p = {jb_p:.4f} {'[!] 残差非正态' if jb_p < 0.05 else ''}")
    except Exception: pass
    return diag


# ============================================================================
# 05. 非线性模型
# ============================================================================

def run_logit(df: pd.DataFrame, y: str, x: str, controls: list[str],
              fe: list[str] | None = None, cluster: str | None = None):
    fe_terms = [f"C({v})" for v in (fe or [])]
    fml = f"{y} ~ {formula_rhs([x, *controls, *fe_terms])}"
    model = smf.logit(fml, data=df).fit(disp=False)
    # 边际效应
    try:
        ame = model.get_margeff(at="overall", method="dydx")
        print(ame.summary())
    except Exception: pass
    if cluster and cluster in df.columns:
        model = model.get_robustcov_results(cov_type="cluster", groups=df[cluster])
    return model


def run_probit(df, y: str, x: str, controls: list[str], fe=None, cluster=None):
    fe_terms = [f"C({v})" for v in (fe or [])]
    model = smf.probit(f"{y} ~ {formula_rhs([x, *controls, *fe_terms])}", data=df).fit(disp=False)
    return model


def run_poisson(df, y: str, x: str, controls: list[str], fe=None):
    fe_terms = [f"C({v})" for v in (fe or [])]
    model = smf.glm(f"{y} ~ {formula_rhs([x, *controls, *fe_terms])}",
                    data=df, family=sm.families.Poisson()).fit()
    # 过度离散诊断
    dispersion = model.pearson_chi2 / model.df_resid
    if dispersion > 1.5:
        print(f"[!] 过度离散 (dispersion = {dispersion:.2f} > 1.5)，考虑使用负二项")
    return model


def run_ordered_logit(df, y: str, x: str, controls: list[str]):
    """有序 Logit (需要将 y 转为有序类别)"""
    from statsmodels.miscmodels.ordinal_model import OrderedModel
    fml = f"{y} ~ {formula_rhs([x, *controls])}"
    return OrderedModel.from_formula(fml, data=df, distr="logit").fit(disp=False)


def run_multinomial_logit(df, y: str, x: str, controls: list[str]):
    """无序多分类 Logit"""
    fml = f"{y} ~ {formula_rhs([x, *controls])}"
    return smf.mnlogit(fml, data=df).fit(disp=False)


# ============================================================================
# 06. 面板数据模型
# ============================================================================

def run_panel_fe(df: pd.DataFrame, y: str, x: str, controls: list[str],
                 entity: str, time: str, other_fe: list[str] | None = None):
    """面板固定效应 (linearmodels PanelOLS)"""
    linearmodels = optional_import("linearmodels")
    if linearmodels is None: raise ImportError("Install linearmodels for panel models")
    from linearmodels.panel import PanelOLS
    panel = df.set_index([entity, time])
    exog_vars = [x, *controls, *(other_fe or [])]
    exog = panel[exog_vars]
    exog = exog.assign(const=1)
    mod = PanelOLS(panel[y], exog, entity_effects=True, time_effects=True)
    fitted = mod.fit(cov_type="clustered", cluster_entity=True)
    return fitted


def run_panel_re(df, y, x, controls, entity, time):
    """面板随机效应"""
    linearmodels = optional_import("linearmodels")
    if linearmodels is None: raise ImportError("Install linearmodels")
    from linearmodels.panel import RandomEffects
    panel = df.set_index([entity, time])
    exog = panel[[x, *controls]].assign(const=1)
    mod = RandomEffects(panel[y], exog)
    return mod.fit(cov_type="clustered", cluster_entity=True)


# Hausman 检验备注: Python 无直接等价, 需手动比较 FE 和 RE 系数差异


# ============================================================================
# 07. 工具变量回归 (IV/2SLS)
# ============================================================================

def run_iv_2sls(df: pd.DataFrame, y: str, endog: str, instrument: str,
                controls: list[str], cluster: str | None = None):
    linearmodels = optional_import("linearmodels")
    if linearmodels is None: raise ImportError("Install linearmodels for IV")
    from linearmodels.iv import IV2SLS
    exog = df[controls].assign(const=1) if controls else pd.DataFrame({"const": 1}, index=df.index)
    mod = IV2SLS(df[y], exog, df[[endog]], df[[instrument]])
    if cluster and cluster in df.columns:
        return mod.fit(cov_type="clustered", clusters=df[cluster])
    return mod.fit(cov_type="robust")


# ============================================================================
# 08. 双重差分 (DID) 与事件研究
# ============================================================================

def run_twfe_did(df: pd.DataFrame, y: str, treat: str, post: str,
                 controls: list[str], id_fe: str, time_fe: str, cluster: str | None = None):
    df = df.copy()
    df["treat_post"] = df[treat] * df[post]
    rhs = [f"C({id_fe})", f"C({time_fe})", "treat_post", treat, post, *controls]
    return _fit_ols(f"{y} ~ {formula_rhs(rhs)}", df, cluster)


def run_event_study_twfe(df: pd.DataFrame, y: str, event: str, treat: str,
                         controls: list[str], id_fe: str, time_fe: str,
                         baseline: int = -1, cluster: str | None = None):
    """事件研究法 (TWFE 手动实现)。交错处理时优先使用 did 包或 Stata csdid/did_imputation。"""
    df = df.copy()
    df[event] = pd.Categorical(df[event])
    rhs = [f"C({event}, Treatment(reference={baseline})):{treat}",
           f"C({id_fe})", f"C({time_fe})", *controls]
    return _fit_ols(f"{y} ~ {formula_rhs(rhs)}", df, cluster)


def note_modern_did():
    text = """Modern staggered DiD:
- In R, prefer did::att_gt()/aggte() or fixest::sunab().
- In Stata, prefer csdid, eventstudyinteract, or did_imputation.
- In Python, TWFE is a baseline. For staggered timing, use the R or Stata ecosystem."""
    (OUTPUT_ROOT / "reports/modern-did-note.md").write_text(text, encoding="utf-8")


# ============================================================================
# 09. 断点回归 (RDD)
# ============================================================================

def run_rdrobust(df: pd.DataFrame, y: str, running: str, cutoff: float = 0.0,
                 covs: list[str] | None = None):
    try: import rdrobust
    except ImportError as exc: raise ImportError("Install rdrobust for RD inference") from exc
    x = df[running] - cutoff
    covmat = df[covs].to_numpy() if covs else None
    return rdrobust.rdrobust(y=df[y].to_numpy(), x=x.to_numpy(), c=0, covs=covmat)


def run_parametric_rd(df, y, running, cutoff, controls, bandwidth):
    """参数化 RDD (局部线性, 作为 rdrobust 的补充)"""
    local = df.loc[(df[running] - cutoff).abs() <= bandwidth].copy()
    local["running_c"] = local[running] - cutoff
    local["above"] = (local["running_c"] >= 0).astype(int)
    return _fit_ols(f"{y} ~ above + running_c + above:running_c + {formula_rhs(controls)}", local)


# ============================================================================
# 10. 匹配方法 (PSM / IPW / NN)
# ============================================================================

def estimate_propensity(df: pd.DataFrame, treat: str, controls: list[str]) -> pd.Series:
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.pipeline import make_pipeline
    X = pd.get_dummies(df[controls], drop_first=True).fillna(0)
    model = make_pipeline(StandardScaler(with_mean=False), LogisticRegression(max_iter=2000))
    model.fit(X, df[treat])
    ps = model.predict_proba(X)[:, 1]
    return pd.Series(np.clip(ps, 0.01, 0.99), index=df.index, name="propensity")


def run_ipw_ate(df: pd.DataFrame, y: str, treat: str, controls: list[str]) -> dict:
    ps = estimate_propensity(df, treat, controls)
    w_t = df[treat] / ps
    w_c = (1 - df[treat]) / (1 - ps)
    ate = (w_t * df[y]).sum() / w_t.sum() - (w_c * df[y]).sum() / w_c.sum()
    out = {"ate_ipw": float(ate), "n": int(len(df))}
    pd.DataFrame([out]).to_csv(OUTPUT_ROOT / "tables/ipw-ate.csv", index=False)
    return out


def run_nn_matching(df: pd.DataFrame, y: str, treat: str, controls: list[str]) -> dict:
    from sklearn.neighbors import NearestNeighbors
    X = pd.get_dummies(df[controls], drop_first=True).fillna(0)
    treated_mask = df[treat] == 1
    nn = NearestNeighbors(n_neighbors=1).fit(X.loc[~treated_mask])
    _, idx = nn.kneighbors(X.loc[treated_mask])
    controls_matched = df.loc[~treated_mask].iloc[idx.flatten()]
    att = df.loc[treated_mask, y].mean() - controls_matched[y].mean()
    out = {"att_nn": float(att), "n_treated": int(treated_mask.sum())}
    pd.DataFrame([out]).to_csv(OUTPUT_ROOT / "tables/matching-att.csv", index=False)
    return out


# ============================================================================
# 11. 因果 ML (DoubleML / Causal Forest)
# ============================================================================

def run_doubleml_plr(df: pd.DataFrame, y: str, d: str, controls: list[str]):
    try: from doubleml import DoubleMLData, DoubleMLPLR
    except ImportError as exc: raise ImportError("Install doubleml") from exc
    from sklearn.ensemble import RandomForestRegressor
    data = DoubleMLData(df[[y, d, *controls]].dropna(), y_col=y, d_cols=d, x_cols=controls)
    learner = RandomForestRegressor(n_estimators=500, min_samples_leaf=5, random_state=20260609)
    dml = DoubleMLPLR(data, ml_l=learner, ml_m=learner, n_folds=5)
    dml.fit()
    with open(OUTPUT_ROOT / "reports/doubleml-plr-summary.txt", "w") as f: f.write(str(dml.summary))
    return dml


def run_econml_causal_forest(df, y, treat, controls):
    try: from econml.dml import CausalForestDML
    except ImportError as exc: raise ImportError("Install econml") from exc
    from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
    data = df[[y, treat, *controls]].dropna()
    est = CausalForestDML(
        model_y=RandomForestRegressor(n_estimators=300, random_state=20260609),
        model_t=RandomForestClassifier(n_estimators=300, random_state=20260609),
        discrete_treatment=True, random_state=20260609)
    est.fit(data[y], data[treat], X=data[controls])
    tau = est.effect(data[controls])
    pd.DataFrame({"tau_hat": tau}).to_csv(OUTPUT_ROOT / "tables/causal-forest-cate.csv", index=False)
    return est


# ============================================================================
# 12. 中介效应与调节效应
# ============================================================================

def run_mediation_baron_kenny(df, y, x, mediator, controls, cluster=None):
    """Baron-Kenny 三步法"""
    m1 = run_ols(df, y, x, controls, cluster=cluster)
    m2 = run_ols(df, mediator, x, controls, cluster=cluster)
    m3 = run_ols(df, y, x, controls + [mediator], cluster=cluster)
    return {"x_to_y": m1, "x_to_m": m2, "x_m_to_y": m3}


def run_interaction(df, y, x, moderator, controls, fe=None, cluster=None):
    fe_terms = [f"C({v})" for v in (fe or [])]
    fml = f"{y} ~ {x} * {moderator} + {formula_rhs(controls + fe_terms)}"
    return _fit_ols(fml, df, cluster)


# ============================================================================
# 13. 时间序列 (基础)
# ============================================================================

def run_adf_test(series: pd.Series, maxlag: int | None = None):
    """Augmented Dickey-Fuller 检验。H0: 存在单位根 (非平稳)。"""
    from statsmodels.tsa.stattools import adfuller
    result = adfuller(series.dropna(), maxlag=maxlag, autolag="AIC")
    print(f"--- ADF: statistic = {result[0]:.3f}, p = {result[1]:.4f}")
    return dict(zip(["statistic", "pvalue", "usedlag", "nobs", "critical_values"], result))


def run_var_model(df, vars_: list[str], lags: int = 2):
    from statsmodels.tsa.api import VAR
    model = VAR(df[vars_].dropna())
    result = model.fit(lags)
    irf = result.irf(10)
    fig = irf.plot(orth=False)
    save_plot_pair(fig, "fig-irf-var")
    return result


# ============================================================================
# 14. 稳健性检验
# ============================================================================

def run_robustness(df, y, x, controls, fe, cluster,
                   alt_y=None, alt_x=None, subset_cond=None):
    results = {}
    if alt_y:   results["alt_y"]   = run_ols(df, alt_y, x, controls, fe, cluster)
    if alt_x:   results["alt_x"]   = run_ols(df, y, alt_x, controls, fe, cluster)
    if subset_cond is not None:
        df_sub = df.query(subset_cond)
        results["subsample"] = run_ols(df_sub, y, x, controls, fe, cluster)
    results["nofe"] = run_ols(df, y, x, controls, None, cluster)
    return results


# ============================================================================
# 15. 文本/质性支持
# ============================================================================

def anonymize_text(text: str) -> str:
    text = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "[EMAIL REMOVED]", text)
    text = re.sub(r"(\+?\d[\d\-\s]{7,}\d)", "[PHONE REMOVED]", text)
    text = re.sub(r"\b1[3-9]\d{9}\b", "[PHONE REMOVED]", text)
    text = re.sub(r"\b\d{17}[\dXx]\b", "[ID REMOVED]", text)
    text = re.sub(r"\b\d{6}(19|20)\d{2}(0[1-9]|1[0-2])([0-2]\d|3[01])\d{3}[\dXx]\b", "[ID REMOVED]", text)
    text = re.sub(r"(微信|WeChat|QQ)[:：]?\s*[A-Za-z0-9_\-]{5,}", r"\1: [ACCOUNT REMOVED]", text)
    return text


def segment_text_file(path: str | Path, document_id: str | None = None) -> pd.DataFrame:
    path = Path(path)
    document_id = document_id or path.stem
    text = anonymize_text(path.read_text(encoding="utf-8"))
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    df = pd.DataFrame({"document_id": document_id,
        "segment_id": [f"{document_id}-{i+1:04d}" for i in range(len(paragraphs))],
        "text": paragraphs})
    df.to_csv(OUTPUT_ROOT / f"qual/coded-data/segments-{document_id}.csv", index=False)
    return df


# ============================================================================
# 16. 结果输出
# ============================================================================

def export_publication_table(model, name: str) -> pd.DataFrame:
    """将 statsmodels 模型导出为论文格式表"""
    params = pd.Series(model.params, name="coef")
    tvals  = pd.Series(getattr(model, "tvalues", np.nan), index=params.index, name="t")
    pvals  = pd.Series(model.pvalues, index=params.index, name="p")
    rows = []
    for term in params.index:
        stars = "***" if pvals.loc[term] < 0.001 else "**" if pvals.loc[term] < 0.01 else "*" if pvals.loc[term] < 0.05 else ""
        rows.append({"term": term, "row": "coef", "estimate": f"{params.loc[term]:.3f}{stars}"})
        rows.append({"term": term, "row": "t", "estimate": f"({tvals.loc[term]:.3f})"})
    table = pd.DataFrame(rows)
    table.to_csv(OUTPUT_ROOT / f"tables/{name}.csv", index=False)
    return table


def write_model_decision():
    template = "\n".join([
        "# 模型决策记录", "",
        "## 基础信息",
        "- 研究问题：", "- 因变量类型：", "- 数据结构：", "- 核心解释变量：",
        "", "## 模型选择",
        "- 主模型：", "- 标准误/聚类层级：", "- 固定效应：",
        "- 可解释为因果吗：",
        "", "## 诊断结果",
        "| 检验 | 统计量 | 阈值 | 通过? |", "|---|---|---|---|",
        "", "## 稳健性", "- 必做：", "- 已做：",
        "", "## 不足与风险"])
    (OUTPUT_ROOT / "reports/model-decision.md").write_text(template, encoding="utf-8")


def write_script_index():
    md = "\n".join([
        "# Script Index", "",
        "| Order | Script | Input | Output | Notes |", "|---|---|---|---|---|",
        f"| 1 | python-analysis-template.py | {DATA_PATH} | {OUTPUT_ROOT} | Edit VARS |"])
    (OUTPUT_ROOT / "reports/script-index.md").write_text(md, encoding="utf-8")


def write_report_skeleton():
    report = "\n".join([
        "# Analysis Results", "",
        "## 1. Data and sample", "## 2. Variables and measurement",
        "## 3. Descriptive statistics", "## 4. Main results",
        "## 5. Causal design diagnostics", "## 6. Robustness and sensitivity",
        "## 7. Heterogeneity and mechanisms", "## 8. Limitations"])
    (OUTPUT_ROOT / "reports/regression-results-template.md").write_text(report, encoding="utf-8")


# ============================================================================
# 17. 示例运行
# ============================================================================

def example_run():
    df_raw = load_data(DATA_PATH)
    df = clean_data(df_raw)
    roles = {"Y": [VARS.y], "X": [VARS.x], "control": VARS.controls,
             "fe": VARS.fe, "cluster": [VARS.cluster] if VARS.cluster else []}
    write_variable_dictionary(df, roles)
    df_a, _ = sample_flow(df, VARS.y, VARS.x, VARS.controls, VARS.id, VARS.time)
    df_a.to_csv(OUTPUT_ROOT / "data/analysis-data.csv", index=False)

    # 描述统计
    describe_data(df_a, [VARS.y, VARS.x, *VARS.controls])
    balance_table(df_a, [VARS.y, *VARS.controls], VARS.treat)

    # 可视化
    plot_distribution(df_a, VARS.y)
    plot_density(df_a, VARS.y, VARS.treat)
    plot_scatter(df_a, VARS.y, VARS.x)
    plot_correlation(df_a, [VARS.y, VARS.x, *VARS.controls])

    # 基准回归
    m1 = run_ols(df_a, VARS.y, VARS.x, [], None, VARS.cluster)
    m2 = run_ols(df_a, VARS.y, VARS.x, VARS.controls, None, VARS.cluster)
    m3 = run_ols(df_a, VARS.y, VARS.x, VARS.controls, VARS.fe, VARS.cluster)
    run_ols_diagnostics(m2)

    export_publication_table(m1, "table2-m1-baseline")
    export_publication_table(m3, "table2-m3-full")
    note_modern_did()
    write_model_decision()
    write_script_index()
    write_report_skeleton()

    print("\n=== Python 模板运行完成 ===")
    print(f"输出目录: {OUTPUT_ROOT}")


if __name__ == "__main__":
    print("Edit DATA_PATH and VarMap, then call example_run() or project-specific functions.")

# ============================================================================
# Paper Analysis 4SS — R 完整分析工作流模板
# 理论框架参考: model-router.md (诊断阈值/内生性判断/面板选择/空间依赖)
#
# 覆盖: cleaning → descriptives → regression → causal → export
# 使用前编辑 "00. 项目配置" 和 "vars" 列表。
# ============================================================================

# ---- 包检查 ---------------------------------------------------------------

required_packages <- c("ggplot2", "dplyr", "tidyr", "tibble", "purrr", "readr")
missing_required <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_required) > 0) {
  stop("Install required R packages first: ", paste(missing_required, collapse = ", "))
}

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr); library(tibble); library(purrr); library(readr)
})
if (requireNamespace("showtext", quietly = TRUE)) showtext::showtext_auto()

# 可选包列表（按需安装，不机械全装）
optional_packages <- c(
  # 数据处理
  "haven", "readxl", "arrow", "janitor", "skimr",
  # 回归 + FE
  "fixest", "plm", "lmtest", "sandwich", "car", "multiwayvcov",
  # 边际效应 + 表格
  "marginaleffects", "modelsummary",
  # 非线性模型
  "MASS", "pscl", "sampleSelection", "ordinal", "mlogit", "nnet",
  # 因果推断
  "did", "rdrobust", "rddensity", "MatchIt", "WeightIt", "cobalt",
  "Synth", "gsynth", "did2s",
  # 时间序列
  "forecast", "urca", "vars", "tseries",
  # 空间
  "sf", "spdep", "spatialreg", "tmap", "leaflet",
  # 可视化
  "patchwork", "cowplot", "ggrepel", "scales", "viridis",
  "ggridges", "ggdist", "ggeffects", "plotly", "htmlwidgets",
  "corrplot", "GGally",
  # 综合
  "broom", "boot", "AER", "ivreg", "sensemakr", "gt", "gtsummary"
)
missing_optional <- optional_packages[!vapply(optional_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_optional) > 0) {
  message("Optional packages not installed: ", paste(missing_optional, collapse = ", "))
}

# ============================================================================
# 00. 项目配置 — 编辑此块
# ============================================================================

project_root <- Sys.getenv("PROJECT_ROOT", ".")
output_root  <- Sys.getenv("OUTPUT_ROOT", file.path(project_root, "analysis-output"))
data_path    <- Sys.getenv("DATA_PATH", file.path(project_root, "data/raw/data.csv"))

dirs <- c("data", "scripts", "tables", "figures", "reports",
          "qual/codebooks", "qual/coded-data", "qual/anonymized", "qual/reliability")
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
purrr::walk(file.path(output_root, dirs), dir.create, recursive = TRUE, showWarnings = FALSE)

# ---- 变量映射 -------------------------------------------------------------

vars <- list(
  y         = "outcome",
  x         = "treatment",
  controls  = c("age", "gender", "education", "income"),
  fe        = c("region", "year"),
  absorb    = c("region", "year"),
  cluster   = "region",
  weight    = NULL,
  id        = "pid",
  time      = "year",
  treat     = "treated",
  post      = "post",
  gvar      = "first_treat_year",
  event     = "rel_year",
  endog     = "endog_x",
  iv        = "instrument_z",
  running   = "running_score",
  cutoff    = 0,
  mediator  = "mediator",
  moderator = "moderator"
)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ============================================================================
# 01. 数据加载与清洗
# ============================================================================

load_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    csv     = readr::read_csv(path, show_col_types = FALSE),
    tsv     = readr::read_tsv(path, show_col_types = FALSE),
    xlsx    = readxl::read_excel(path),
    xls     = readxl::read_excel(path),
    dta     = haven::read_dta(path),
    sav     = haven::read_sav(path),
    rds     = readRDS(path),
    parquet = { requireNamespace("arrow"); arrow::read_parquet(path) },
    stop("Unsupported file type: ", ext)
  )
}

clean_names_safe <- function(df) {
  if (requireNamespace("janitor", quietly = TRUE)) janitor::clean_names(df) else df
}

clean_data <- function(df, special_missing = c(-9, -8, -7, -99, -999)) {
  df %>% clean_names_safe() %>%
    mutate(across(where(is.character), ~ na_if(stringr::str_squish(.x), "")),
           across(where(is.numeric), ~ replace(.x, .x %in% special_missing, NA_real_)),
           across(where(is.numeric) & !all_of(c(vars$id, vars$time)),
                  ~ DescTools::Winsorize(.x, probs = c(0.01, 0.99), na.rm = TRUE))) %>%
    distinct()
}

write_variable_dictionary <- function(df, roles = list(), source_file = data_path) {
  dict <- tibble(
    raw_name = names(df), clean_name = names(df),
    label = purrr::map_chr(df, ~ attr(.x, "label") %||% ""),
    role  = purrr::map_chr(names(df), function(v) {
      hit <- names(roles)[vapply(roles, function(x) v %in% x, logical(1))]
      paste(hit, collapse = ";") }),
    type = purrr::map_chr(df, ~ paste(class(.x), collapse = ";")),
    missing_rule = "", transform = "", source_file = source_file, notes = "")
  readr::write_csv(dict, file.path(output_root, "data/variable-dictionary.csv"))
  dict
}

# ============================================================================
# 02. 样本构建与描述统计
# ============================================================================

make_sample_flow <- function(df, y, x, controls = character(), id = NULL, time = NULL) {
  current <- df
  rows <- list(tibble(step = 0, rule = "raw data", n_before = NA_integer_, n_after = nrow(current), dropped = NA_integer_, reason = "raw"))
  step <- 1
  for (v in c(y, x, controls)) {
    before <- nrow(current); current <- current %>% filter(!is.na(.data[[v]]))
    rows[[length(rows) + 1]] <- tibble(step = step, rule = paste0("nonmissing_", v),
      n_before = before, n_after = nrow(current), dropped = before - nrow(current), reason = "missing"); step <- step + 1
  }
  if (!is.null(id) && !is.null(time) && all(c(id, time) %in% names(current))) {
    before <- nrow(current); current <- current %>% distinct(.data[[id]], .data[[time]], .keep_all = TRUE)
    rows[[length(rows) + 1]] <- tibble(step = step, rule = "unique_id_time",
      n_before = before, n_after = nrow(current), dropped = before - nrow(current), reason = "duplicate panel key")
  }
  flow <- bind_rows(rows)
  readr::write_csv(flow, file.path(output_root, "tables/sample-flow.csv"))
  list(data = current, flow = flow)
}

make_table1 <- function(df, vars_) {
  modelsummary::datasummary_skim(df[, vars_, drop = FALSE], fmt = 3,
    output = file.path(output_root, "tables/table1-descriptives.docx"))
}

make_balance_table <- function(df, y_vars, group_var) {
  modelsummary::datasummary_balance(as.formula(paste("~", group_var)),
    data = df[, c(y_vars, group_var)], fmt = 3,
    output = file.path(output_root, "tables/table1b-balance.docx"))
}

# ============================================================================
# 03. 可视化协议
# ============================================================================

theme_paper <- function(base_size = 12, base_family = "") {
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      panel.grid.minor = element_blank(), plot.title.position = "plot",
      legend.position = "bottom", legend.title = element_text(size = base_size - 1),
      axis.title = element_text(size = base_size), axis.text = element_text(color = "black"))
}

save_plot_pair <- function(plot, stem, width = 7, height = 5, dpi = 300) {
  ggplot2::ggsave(file.path(output_root, "figures", paste0(stem, ".pdf")), plot, width = width, height = height, device = cairo_pdf)
  ggplot2::ggsave(file.path(output_root, "figures", paste0(stem, ".png")), plot, width = width, height = height, dpi = dpi)
}

# ---- 分布图 ----
plot_distribution <- function(df, var, group = NULL, bins = 30) {
  aes_args <- if (is.null(group)) aes(x = .data[[var]]) else aes(x = .data[[var]], fill = factor(.data[[group]]))
  p <- ggplot(df, aes_args) +
    geom_histogram(bins = bins, alpha = 0.78, color = "white", position = "identity") +
    scale_fill_viridis_d(option = "C", end = 0.85) + theme_paper() + labs(x = var, y = "Count", fill = group)
  save_plot_pair(p, paste0("fig-dist-", var)); p
}

# ---- 密度图 ----
plot_density <- function(df, var, group = NULL) {
  aes_args <- if (is.null(group)) aes(x = .data[[var]]) else aes(x = .data[[var]], color = factor(.data[[group]]), fill = factor(.data[[group]]))
  p <- ggplot(df, aes_args) +
    geom_density(alpha = 0.25) + scale_color_viridis_d(option = "D", end = 0.85) +
    scale_fill_viridis_d(option = "D", end = 0.85) + theme_paper() + labs(x = var, y = "Density")
  save_plot_pair(p, paste0("fig-density-", var)); p
}

# ---- 散点图 + 拟合线 ----
plot_scatter <- function(df, y, x, group = NULL) {
  aes_args <- if (is.null(group)) aes(x = .data[[x]], y = .data[[y]]) else aes(x = .data[[x]], y = .data[[y]], color = factor(.data[[group]]))
  p <- ggplot(df, aes_args) +
    geom_point(alpha = 0.4, size = 1) + geom_smooth(method = "lm", se = TRUE, alpha = 0.2) +
    scale_color_viridis_d(option = "D", end = 0.85) + theme_paper() + labs(x = x, y = y)
  save_plot_pair(p, paste0("fig-scatter-", y, "-", x)); p
}

# ---- 分组均值 + CI ----
plot_group_mean <- function(df, y, group) {
  summary <- df %>% group_by(.data[[group]]) %>%
    summarise(mean = mean(.data[[y]], na.rm = TRUE),
              se = sd(.data[[y]], na.rm = TRUE) / sqrt(n()), .groups = "drop") %>%
    mutate(lower = mean - 1.96 * se, upper = mean + 1.96 * se)
  p <- ggplot(summary, aes(x = factor(.data[[group]]), y = mean)) +
    geom_pointrange(aes(ymin = lower, ymax = upper), linewidth = 0.4, color = "#2c3e50") +
    theme_paper() + labs(x = group, y = paste0("Mean of ", y))
  save_plot_pair(p, paste0("fig-group-mean-", y, "-by-", group)); p
}

# ---- 相关矩阵图 ----
plot_correlation <- function(df, vars_, file_stem = "fig-correlation") {
  if (!requireNamespace("corrplot", quietly = TRUE)) return(NULL)
  cor_mat <- cor(df[, vars_], use = "pairwise.complete.obs")
  pdf(file.path(output_root, "figures", paste0(file_stem, ".pdf")), width = 8, height = 7)
  corrplot::corrplot(cor_mat, method = "color", type = "upper", addCoef.col = "black",
                     tl.col = "black", number.cex = 0.7, diag = FALSE)
  dev.off()
  png(file.path(output_root, "figures", paste0(file_stem, ".png")), width = 1600, height = 1400, res = 200)
  corrplot::corrplot(cor_mat, method = "color", type = "upper", addCoef.col = "black",
                     tl.col = "black", number.cex = 0.7, diag = FALSE)
  dev.off()
}

# ---- 系数图 ----
plot_model_coefficients <- function(models, file_stem = "fig-coefplot-main", coef_omit = "Intercept|^factor|^C\\(") {
  p <- modelsummary::modelplot(models, coef_omit = coef_omit) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") + theme_paper() + labs(x = "Estimate", y = NULL)
  save_plot_pair(p, file_stem); p
}

# ---- 边际效应图 ----
plot_marginal_effects <- function(model, variable, file_stem = NULL) {
  slopes <- marginaleffects::slopes(model, variables = variable)
  p <- marginaleffects::plot_slopes(model, variables = variable) + theme_paper() + labs(x = variable, y = "Marginal effect")
  save_plot_pair(p, file_stem %||% paste0("fig-marginal-effects-", variable))
  list(slopes = slopes, plot = p)
}

# ---- 事件研究图 (fixest) ----
plot_event_study_fixest <- function(model, file_stem = "fig-event-study") {
  pdf(file.path(output_root, "figures", paste0(file_stem, ".pdf")), width = 7, height = 5)
  fixest::iplot(model, ref.line = 0, main = "Event-study estimates"); dev.off()
  png(file.path(output_root, "figures", paste0(file_stem, ".png")), width = 1600, height = 1100, res = 180)
  fixest::iplot(model, ref.line = 0, main = "Event-study estimates"); dev.off()
}

# ---- OLS 诊断四图 ----
plot_diagnostics <- function(model, file_stem = "fig-diagnostics") {
  diag <- data.frame(
    fitted    = fitted(model),
    residuals = residuals(model),
    std_resid = rstandard(model),
    leverage  = hatvalues(model),
    cooks_d   = cooks.distance(model))
  diag$sqrt_abs_std <- sqrt(abs(diag$std_resid))

  p1 <- ggplot(diag, aes(fitted, residuals)) + geom_point(alpha = 0.5, size = 1) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.5) +
    theme_paper() + labs(x = "Fitted", y = "Residuals", title = "Residuals vs Fitted")

  p2 <- ggplot(diag, aes(sample = residuals)) + stat_qq(alpha = 0.5) + stat_qq_line(color = "red", alpha = 0.5) +
    theme_paper() + labs(x = "Theoretical Quantiles", y = "Sample Quantiles", title = "Q-Q Plot")

  p3 <- ggplot(diag, aes(fitted, sqrt_abs_std)) + geom_point(alpha = 0.5, size = 1) +
    geom_smooth(se = FALSE, color = "red", alpha = 0.5) + theme_paper() +
    labs(x = "Fitted", y = expression(sqrt("|Std Residuals|")), title = "Scale-Location")

  p4 <- ggplot(diag, aes(leverage, std_resid, color = cooks_d)) + geom_point(alpha = 0.5, size = 1) +
    geom_hline(yintercept = 0, linetype = "dashed", alpha = 0.5) +
    scale_color_viridis_c(option = "C") + theme_paper() +
    labs(x = "Leverage", y = "Std Residuals", title = "Residuals vs Leverage", color = "Cook's D")

  combined <- (p1 + p2) / (p3 + p4) + patchwork::plot_annotation(title = "Regression Diagnostics")
  save_plot_pair(combined, file_stem, width = 12, height = 10); combined
}

# ============================================================================
# 04. 基准回归 + 诊断
# ============================================================================

# --- 逐步回归 (OLS) ---
run_ols <- function(df, y, x, controls = character(), fe = character(), cluster = NULL, weight = NULL) {
  rhs <- paste(c(x, controls), collapse = " + ")
  fml <- if (length(fe) > 0) as.formula(paste(y, "~", rhs, "|", paste(fe, collapse = " + ")))
         else as.formula(paste(y, "~", rhs))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  w  <- if (!is.null(weight)) as.formula(paste("~", weight)) else NULL
  fixest::feols(fml, data = df, vcov = vc, weights = w)
}

# --- OLS 诊断套件 ---
run_ols_diagnostics <- function(model) {
  # 共线性
  if (requireNamespace("car", quietly = TRUE)) {
    vif_vals <- tryCatch(car::vif(model), error = function(e) NULL)
    if (!is.null(vif_vals)) { cat("\n--- VIF (Variance Inflation Factor) ---\n"); print(vif_vals)
      if (any(vif_vals > 10)) cat("[!] VIF > 10: 存在严重共线性\n") }
  }
  # 异方差 (Breusch-Pagan)
  if (requireNamespace("lmtest", quietly = TRUE)) {
    bp <- tryCatch(lmtest::bptest(model), error = function(e) NULL)
    if (!is.null(bp)) cat(sprintf("\n--- Breusch-Pagan test: BP = %.3f, p = %.4f ---\n", bp$statistic, bp$p.value))
  }
  # 自相关 (Durbin-Watson)
  dw <- tryCatch(car::durbinWatsonTest(model), error = function(e) NULL)
  if (!is.null(dw)) cat(sprintf("--- Durbin-Watson: DW = %.3f, p = %.4f ---\n", dw$dw, dw$p))
  # 正态性 (Shapiro-Wilk)
  sw <- tryCatch(shapiro.test(residuals(model)), error = function(e) NULL)
  if (!is.null(sw)) cat(sprintf("--- Shapiro-Wilk: W = %.3f, p = %.4f ---\n", sw$statistic, sw$p.value))
}

# ============================================================================
# 05. 非线性模型 (Logit/Probit/Poisson/Tobit/Heckman)
# ============================================================================

# --- 二值选择 ---
run_logit <- function(df, y, x, controls = character(), fe = character(), cluster = NULL) {
  fe_rhs <- if (length(fe) > 0) paste(sprintf("factor(%s)", fe), collapse = " + ") else NULL
  rhs <- paste(c(x, controls, fe_rhs), collapse = " + ")
  fml <- as.formula(paste(y, "~", rhs))
  mod <- glm(fml, data = df, family = binomial())
  if (!is.null(cluster) && requireNamespace("sandwich", quietly = TRUE)) {
    vcov_cl <- sandwich::vcovCL(mod, cluster = df[[cluster]], type = "HC1")
    mod$robust_vcov <- vcov_cl
  }
  mod
}

run_logit_ame <- function(df, y, x, controls = character(), fe = character(), cluster = NULL) {
  mod <- run_logit(df, y, x, controls, fe, cluster)
  ame <- marginaleffects::avg_slopes(mod, variables = x)
  list(model = mod, ame = ame)
}

# --- 有序/多分类 ---
run_ordered_logit <- function(df, y, x, controls = character()) {
  fml <- as.formula(paste("factor(", y, ") ~", paste(c(x, controls), collapse = " + ")))
  MASS::polr(fml, data = df, method = "logistic", Hess = TRUE)
}

run_multinomial_logit <- function(df, y, x, controls = character()) {
  fml <- as.formula(paste(y, "~", paste(c(x, controls), collapse = " + ")))
  nnet::multinom(fml, data = df, trace = FALSE)
}

# --- 计数模型 ---
run_poisson <- function(df, y, x, controls = character(), fe = character()) {
  fe_rhs <- if (length(fe) > 0) paste(sprintf("factor(%s)", fe), collapse = " + ") else NULL
  rhs <- paste(c(x, controls, fe_rhs), collapse = " + ")
  mod <- glm(as.formula(paste(y, "~", rhs)), data = df, family = poisson())
  # 过度离散诊断
  dispersion <- sum(residuals(mod, type = "pearson")^2) / mod$df.residual
  if (dispersion > 1.5) message(sprintf("过度离散 (dispersion = %.2f > 1.5)，考虑使用负二项回归", dispersion))
  list(model = mod, dispersion = dispersion)
}

run_nbreg <- function(df, y, x, controls = character()) {
  rhs <- paste(c(x, controls), collapse = " + ")
  MASS::glm.nb(as.formula(paste(y, "~", rhs)), data = df)
}

# --- 受限因变量 ---
run_tobit <- function(df, y, x, controls = character(), left = 0) {
  requireNamespace("AER")
  rhs <- paste(c(x, controls), collapse = " + ")
  AER::tobit(as.formula(paste(y, "~", rhs)), data = df, left = left)
}

run_heckman <- function(df, y, x, controls, select_var, select_z) {
  requireNamespace("sampleSelection")
  outcome_fml <- as.formula(paste(y, "~", paste(c(x, controls), collapse = " + ")))
  select_fml  <- as.formula(paste(select_var, "~", paste(c(select_z, controls), collapse = " + ")))
  sampleSelection::heckit(selection = select_fml, outcome = outcome_fml, data = df, method = "2step")
}

# ============================================================================
# 06. 面板数据模型
# ============================================================================

# --- 面板 FE/RE (plm) ---
run_panel_fe <- function(df, y, x, controls = character(), id, time, cluster = NULL) {
  requireNamespace("plm")
  rhs <- paste(c(x, controls), collapse = " + ")
  mod <- plm::plm(as.formula(paste(y, "~", rhs)), data = df, index = c(id, time), model = "within")
  if (!is.null(cluster)) {
    vcov_c <- plm::vcovHC(mod, type = "HC1", cluster = "group")
    mod$vcov <- vcov_c
  }
  mod
}

run_panel_re <- function(df, y, x, controls = character(), id, time) {
  requireNamespace("plm")
  rhs <- paste(c(x, controls), collapse = " + ")
  plm::plm(as.formula(paste(y, "~", rhs)), data = df, index = c(id, time), model = "random")
}

# Hausman 检验: p < 0.05 → 用 FE
run_hausman_test <- function(mod_fe, mod_re) {
  ht <- plm::phtest(mod_fe, mod_re)
  cat(sprintf("\n--- Hausman Test: chi2 = %.3f, df = %d, p = %.4f ---\n", ht$statistic, ht$parameter, ht$p.value))
  if (ht$p.value < 0.05) cat("→ 拒绝 H0，使用固定效应 (FE)\n") else cat("→ 不拒绝 H0，随机效应 (RE) 更有效\n")
  ht
}

# --- 面板 IV (fixest 内置) ---
run_panel_iv <- function(df, y, endog, instrument, controls = character(), fe = character(), cluster = NULL) {
  rhs_ctrl <- paste(controls, collapse = " + ")
  rhs_ctrl <- if (rhs_ctrl == "") "1" else rhs_ctrl
  fml <- as.formula(paste(y, "~", rhs_ctrl, "|", paste(fe, collapse = " + "), "|", endog, "~", instrument))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  fixest::feols(fml, data = df, vcov = vc)
}

# --- 动态面板 GMM (如果有 pgmm 包可用) ---
# pgmm 在 plm 包中, 仅支持平衡面板
# run_panel_gmm <- function(df, y, x, controls, id, time, lag_y = 1) { ... }

# ============================================================================
# 07. 工具变量回归 (IV/2SLS)
# ============================================================================

run_iv_2sls <- function(df, y, endog, instrument, controls = character(), fe = character(), cluster = NULL) {
  rhs_ctrl <- paste(controls, collapse = " + ")
  rhs_ctrl <- if (rhs_ctrl == "") "1" else rhs_ctrl
  fml <- as.formula(paste(y, "~", rhs_ctrl, "|", paste(fe, collapse = " + "), "|", endog, "~", instrument))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  mod <- fixest::feols(fml, data = df, vcov = vc)

  # 第一阶段
  stage1_fml <- as.formula(paste(endog, "~", instrument, "+", rhs_ctrl))
  stage1 <- fixest::feols(stage1_fml, data = df, vcov = vc)
  cat(sprintf("\n--- 第一阶段 F 统计量: %.2f ---\n", fixest::fitstat(stage1, "ivf")$ivf))

  list(iv = mod, stage1 = stage1)
}

# AER 包 IV (带诊断)
run_iv_aer <- function(df, y, endog, instrument, controls = character()) {
  requireNamespace("AER")
  requireNamespace("lmtest")
  rhs <- paste(c(endog, controls), collapse = " + ")
  iv <- paste(c(instrument, controls), collapse = " + ")
  fml <- as.formula(paste(y, "~", rhs, "|", iv))
  mod <- AER::ivreg(fml, data = df)
  # 弱IV诊断
  diag <- summary(mod, diagnostics = TRUE)
  print(diag$diagnostics)
  mod
}

# ============================================================================
# 08. 双重差分 (DID) 与事件研究
# ============================================================================

# --- 标准 2x2 DID ---
run_twfe_did <- function(df, y, treat, post, controls = character(), fe = c("id", "time"), cluster = NULL) {
  requireNamespace("fixest")
  df$treat_post <- df[[treat]] * df[[post]]
  rhs <- paste(c("treat_post", treat, post, controls), collapse = " + ")
  fml <- as.formula(paste(y, "~", rhs, "|", paste(fe, collapse = " + ")))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  fixest::feols(fml, data = df, vcov = vc)
}

# --- 事件研究法 (Sun-Abraham) ---
run_sunab_event_study <- function(df, y, gvar, time, controls = character(), id_fe, time_fe, cluster = NULL) {
  requireNamespace("fixest")
  rhs <- paste(c(sprintf("sunab(%s, %s)", gvar, time), controls), collapse = " + ")
  fml <- as.formula(paste(y, "~", rhs, "|", id_fe, "+", time_fe))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  mod <- fixest::feols(fml, data = df, vcov = vc)
  plot_event_study_fixest(mod); mod
}

# --- Callaway-Sant'Anna (did 包) ---
run_callaway_santanna <- function(df, y, gvar, id, time, xformla = NULL, cluster = NULL) {
  requireNamespace("did")
  xformla <- xformla %||% ~1
  att <- did::att_gt(yname = y, gname = gvar, idname = id, tname = time,
                     xformla = xformla, data = df, clustervars = cluster)
  list(att_gt = att, dynamic = did::aggte(att, type = "dynamic"), simple = did::aggte(att, type = "simple"))
}

# --- 平行趋势检验 (事前交互项) ---
run_parallel_trends <- function(df, y, treat, event, controls = character(), fe = c("id", "time"), cluster = NULL) {
  # 生成 event dummies 并与 treat 交互; 基准期 (如 event==-1) 设为 omitted
  df$event_f <- factor(df[[event]])
  rhs <- paste(c(sprintf("event_f:%s", treat), controls), collapse = " + ")
  fml <- as.formula(paste(y, "~", rhs, "|", paste(fe, collapse = " + ")))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  mod <- fixest::feols(fml, data = df, vcov = vc)
  plot_event_study_fixest(mod); mod
}

# ============================================================================
# 09. 断点回归 (RDD)
# ============================================================================

run_rdrobust <- function(df, y, running, cutoff = 0, covs = character(), cluster = NULL) {
  requireNamespace("rdrobust")
  x <- df[[running]] - cutoff
  covmat <- if (length(covs) > 0) as.matrix(df[, covs, drop = FALSE]) else NULL
  clus <- df[[cluster]] %||% NULL

  # 断点图
  png(file.path(output_root, "figures/rdplot.png"), width = 1600, height = 1100, res = 180)
  rdrobust::rdplot(y = df[[y]], x = x, c = 0); dev.off()

  # 密度检验
  density_test <- rdrobust::rddensity(X = x, c = 0)

  # 主估计
  rd <- rdrobust::rdrobust(y = df[[y]], x = x, c = 0, covs = covmat, cluster = clus)

  list(rd = rd, density = density_test)
}

# ============================================================================
# 10. 匹配方法 (PSM / CEM / IPW)
# ============================================================================

run_matchit <- function(df, y, treat, controls = character(), method = "nearest", ratio = 1, caliper = 0.05) {
  requireNamespace("MatchIt"); requireNamespace("cobalt")
  fml <- as.formula(paste(treat, "~", paste(controls, collapse = " + ")))
  m <- MatchIt::matchit(fml, data = df, method = method, ratio = ratio, caliper = caliper)
  bal <- cobalt::bal.tab(m)
  cobalt::love.plot(bal, threshold = 0.1)
  matched <- MatchIt::match.data(m)
  # 匹配后估计
  ate_mod <- lm(as.formula(paste(y, "~", treat)), data = matched, weights = weights)
  list(matchit = m, balance = bal, data = matched, model = ate_mod)
}

run_weightit_ipw <- function(df, y, treat, controls = character(), estimand = "ATE") {
  requireNamespace("WeightIt"); requireNamespace("cobalt")
  fml <- as.formula(paste(treat, "~", paste(controls, collapse = " + ")))
  w <- WeightIt::weightit(fml, data = df, method = "ps", estimand = estimand)
  df$ipw <- w$weights
  mod <- lm(as.formula(paste(y, "~", treat)), data = df, weights = ipw)
  list(weightit = w, balance = cobalt::bal.tab(w), model = mod)
}

# ============================================================================
# 11. 合成控制 (SCM)
# ============================================================================

run_synth <- function(df, y, predictors, treated_unit, treated_time, pre_period) {
  requireNamespace("Synth")
  dataprep_out <- Synth::dataprep(
    foo = df, predictors = predictors, predictors.op = "mean",
    dependent = y, unit.variable = "unit_id", time.variable = "time_var",
    treatment.identifier = treated_unit, controls.identifier = setdiff(unique(df$unit_id), treated_unit),
    time.predictors.prior = pre_period, time.optimize.ssr = pre_period,
    time.plot = seq(min(df$time_var), max(df$time_var)))
  synth_out <- Synth::synth(dataprep_out)
  list(dataprep = dataprep_out, synth = synth_out)
}

# ============================================================================
# 12. 分位数回归
# ============================================================================

run_quantile_reg <- function(df, y, x, controls = character(), tau = 0.5) {
  requireNamespace("quantreg")
  rhs <- paste(c(x, controls), collapse = " + ")
  quantreg::rq(as.formula(paste(y, "~", rhs)), tau = tau, data = df)
}

run_simultaneous_qr <- function(df, y, x, controls = character(), taus = c(0.25, 0.5, 0.75)) {
  requireNamespace("quantreg")
  rhs <- paste(c(x, controls), collapse = " + ")
  mod <- quantreg::rq(as.formula(paste(y, "~", rhs)), tau = taus, data = df)
  # 跨分位数系数相等检验
  anova_test <- anova(mod)
  list(model = mod, anova = anova_test)
}

# ============================================================================
# 13. 中介效应与调节效应
# ============================================================================

run_mediation <- function(df, y, x, mediator, controls = character(), fe = character(), cluster = NULL) {
  # Step 1: X → Y
  m1 <- run_ols(df, y, x, controls, fe, cluster)
  # Step 2: X → M
  m2 <- run_ols(df, mediator, x, controls, fe, cluster)
  # Step 3: X + M → Y
  m3 <- run_ols(df, y, c(x, mediator), controls, fe, cluster)
  # Bootstrap 间接效应 (mediation 包)
  if (requireNamespace("mediation", quietly = TRUE)) {
    med_fml_y <- as.formula(paste(y, "~", x, "+", mediator, "+", paste(controls, collapse = "+")))
    med_fml_m <- as.formula(paste(mediator, "~", x, "+", paste(controls, collapse = "+")))
    med_y <- lm(med_fml_y, data = df)
    med_m <- lm(med_fml_m, data = df)
    med_out <- mediation::mediate(med_m, med_y, treat = x, mediator = mediator, sims = 1000)
    summary(med_out)
    return(list(step1 = m1, step2 = m2, step3 = m3, mediation = med_out))
  }
  list(step1 = m1, step2 = m2, step3 = m3)
}

run_interaction <- function(df, y, x, moderator, controls = character(), fe = character(), cluster = NULL) {
  rhs <- paste(c(paste0(x, "*", moderator), controls), collapse = " + ")
  if (length(fe) > 0) {
    rhs <- paste(rhs, "|", paste(fe, collapse = " + "))
  }
  fml <- as.formula(paste(y, "~", rhs))
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC1"
  mod <- fixest::feols(fml, data = df, vcov = vc)
  # 边际效应图
  slopes <- marginaleffects::slopes(mod, variables = x, by = moderator)
  list(model = mod, slopes = slopes)
}

# ============================================================================
# 14. 时间序列分析
# ============================================================================

run_adf_test <- function(series, lags = 4) {
  requireNamespace("urca")
  urca::ur.df(series, type = "trend", lags = lags) %>% summary()
}

run_var_model <- function(df, vars_, lags = 2) {
  requireNamespace("vars")
  mod <- vars::VAR(df[, vars_], p = lags, type = "const")
  # Granger 因果
  causality <- vars::causality(mod, cause = vars_[1])
  # IRF
  irf <- vars::irf(mod, n.ahead = 10, boot = TRUE)
  plot(irf)
  list(var = mod, causality = causality, irf = irf)
}

# ============================================================================
# 15. 非参数/半参数估计
# ============================================================================

# 核密度
plot_kernel_density <- function(df, var, group = NULL) {
  plot_density(df, var, group)
}

# Lowess / 局部多项式
plot_lowess <- function(df, y, x, file_stem = NULL) {
  p <- ggplot(df, aes(.data[[x]], .data[[y]])) +
    geom_point(alpha = 0.3, size = 1) +
    geom_smooth(method = "loess", se = TRUE, color = "#2878B5", fill = "#2878B5", alpha = 0.2) +
    theme_paper() + labs(x = x, y = y)
  save_plot_pair(p, file_stem %||% paste0("fig-lowess-", y, "-", x)); p
}

# ============================================================================
# 16. 空间计量经济学 (sf + spdep)
# ============================================================================

run_moran_test <- function(df, var, coords = c("lon", "lat")) {
  requireNamespace("spdep"); requireNamespace("sf")
  pts <- sf::st_as_sf(df, coords = coords)
  nb <- spdep::knearneigh(sf::st_coordinates(pts), k = 5) %>% spdep::knn2nb()
  listw <- spdep::nb2listw(nb)
  moran <- spdep::moran.test(df[[var]], listw)
  cat(sprintf("\n--- Moran's I = %.4f, p = %.4f ---\n", moran$estimate[1], moran$p.value))
  moran
}

run_spatial_sar <- function(df, y, x, controls, coords = c("lon", "lat")) {
  requireNamespace("spatialreg"); requireNamespace("spdep"); requireNamespace("sf")
  pts <- sf::st_as_sf(df, coords = coords)
  nb <- spdep::knearneigh(sf::st_coordinates(pts), k = 5) %>% spdep::knn2nb()
  listw <- spdep::nb2listw(nb)
  rhs <- paste(c(x, controls), collapse = " + ")
  spatialreg::lagsarlm(as.formula(paste(y, "~", rhs)), data = df, listw = listw)
}

# ============================================================================
# 17. Bootstrap 推断
# ============================================================================

run_bootstrap <- function(df, y, x, controls, fe, cluster, R = 500) {
  requireNamespace("boot")
  boot_fn <- function(data, indices) {
    d <- data[indices, ]
    m <- run_ols(d, y, x, controls, fe, cluster)
    coef(m)[x]
  }
  boot_out <- boot::boot(df, boot_fn, R = R)
  cat(sprintf("\n--- Bootstrap SE for %s: %.4f ---\n", x, sd(boot_out$t)))
  boot_out
}

# ============================================================================
# 18. 稳健性检验包装
# ============================================================================

run_robustness <- function(df, y, x, controls, fe, cluster,
                           alt_y = NULL, alt_x = NULL, subset_cond = NULL) {
  results <- list()

  # (1) 替代因变量
  if (!is.null(alt_y)) results$alt_y <- run_ols(df, alt_y, x, controls, fe, cluster)

  # (2) 替代解释变量
  if (!is.null(alt_x)) results$alt_x <- run_ols(df, y, alt_x, controls, fe, cluster)

  # (3) 子样本
  if (!is.null(subset_cond)) {
    df_sub <- dplyr::filter(df, {{ subset_cond }})
    results$subsample <- run_ols(df_sub, y, x, controls, fe, cluster)
  }

  # (4) 无 FE（对比）
  results$nofe <- run_ols(df, y, x, controls, character(), cluster)

  results
}

# ============================================================================
# 19. 结果输出
# ============================================================================

export_models <- function(models, file_stem = "table2-main-regression") {
  for (ext in c("html", "tex", "docx", "csv")) {
    modelsummary::modelsummary(models,
      statistic = "statistic", fmt = 3, stars = c("*" = .05, "**" = .01, "***" = .001),
      notes = "括号内为 t/z 统计值；标准误类型和聚类层级见正文或表注。",
      output = file.path(output_root, "tables", paste0(file_stem, ".", ext)))
  }
}

write_model_decision <- function() {
  template <- c(
    "# 模型决策记录",
    "", "## 基础信息",
    "- 研究问题：", "- 因变量类型：", "- 数据结构：", "- 核心解释变量：",
    "", "## 模型选择",
    "- 主模型：", "- 标准误/聚类层级：", "- 固定效应：",
    "- 可解释为因果吗：",
    "", "## 诊断结果",
    "| 检验 | 统计量 | 阈值 | 通过? |", "|---|---|---|---|",
    "", "## 稳健性",
    "- 必做：", "- 已做：",
    "", "## 不足与风险")
  writeLines(template, file.path(output_root, "reports/model-decision.md"))
}

write_script_index <- function() {
  writeLines(c("# Script Index", "",
    "| Order | Script | Input | Output | Notes |",
    "|---|---|---|---|---|",
    paste("| 1 | r-analysis-template.R |", data_path, "|", output_root, "| Edit configuration |")),
    file.path(output_root, "reports/script-index.md"))
}

write_report_skeleton <- function() {
  writeLines(c("# Analysis Results", "",
    "## 1. Data and sample", "## 2. Variables and measurement",
    "## 3. Descriptive statistics", "## 4. Main results",
    "## 5. Causal design diagnostics", "## 6. Robustness and sensitivity",
    "## 7. Heterogeneity and mechanisms", "## 8. Limitations"),
    file.path(output_root, "reports/regression-results-template.md"))
}

# ============================================================================
# 20. 交互式运行示例
# ============================================================================

if (interactive()) {
  df_raw <- load_data(data_path)
  df     <- clean_data(df_raw)
  roles  <- list(Y = vars$y, X = vars$x, control = vars$controls, fe = vars$fe, cluster = vars$cluster)
  write_variable_dictionary(df, roles)
  sample <- make_sample_flow(df, vars$y, vars$x, vars$controls, vars$id, vars$time)
  df_a   <- sample$data
  readr::write_csv(df_a, file.path(output_root, "data/analysis-data.csv"))

  # 描述统计 + 图
  make_table1(df_a, c(vars$y, vars$x, vars$controls))
  plot_distribution(df_a, vars$y)
  plot_density(df_a, vars$y, vars$treat)
  plot_scatter(df_a, vars$y, vars$x)
  plot_correlation(df_a, c(vars$y, vars$x, vars$controls))

  # 基准回归
  m1 <- run_ols(df_a, vars$y, vars$x, character(), character(), vars$cluster)
  m2 <- run_ols(df_a, vars$y, vars$x, vars$controls, character(), vars$cluster)
  m3 <- run_ols(df_a, vars$y, vars$x, vars$controls, vars$fe, vars$cluster)
  run_ols_diagnostics(m2)

  export_models(list("M1:Baseline" = m1, "M2:+Controls" = m2, "M3:+FE" = m3))
  plot_model_coefficients(list("M1" = m1, "M2" = m2, "M3" = m3))
  write_model_decision()
  write_script_index()
  write_report_skeleton()

  message("\n=== R 模板运行完成 ===")
  message("输出目录: ", output_root)
}

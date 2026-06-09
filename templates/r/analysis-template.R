# Paper Analysis 4SS - R template

suppressPackageStartupMessages({
  library(tidyverse)
  library(haven)
  library(readxl)
  library(modelsummary)
  library(fixest)
  library(marginaleffects)
  library(ggplot2)
})

output_root <- Sys.getenv("OUTPUT_ROOT", "output/paper-analysis")
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
for (d in c("data", "scripts", "tables", "figures", "reports", "qual/codebooks", "qual/coded-data", "qual/reliability")) {
  dir.create(file.path(output_root, d), recursive = TRUE, showWarnings = FALSE)
}

load_data <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    csv = readr::read_csv(path, show_col_types = FALSE),
    xlsx = readxl::read_excel(path),
    xls = readxl::read_excel(path),
    dta = haven::read_dta(path),
    sav = haven::read_sav(path),
    rds = readRDS(path),
    parquet = arrow::read_parquet(path),
    stop("Unsupported file type: ", ext)
  )
}

clean_data <- function(df) {
  df %>%
    mutate(across(where(is.character), ~na_if(str_squish(.x), ""))) %>%
    distinct()
}

make_sample <- function(df, y, x, controls = character()) {
  vars <- c(y, x, controls)
  df %>%
    mutate(analysis_sample = if_all(all_of(vars), ~ !is.na(.x))) %>%
    filter(analysis_sample)
}

make_table1 <- function(df, vars) {
  datasummary_skim(
    df[, vars, drop = FALSE],
    fmt = 3,
    output = file.path(output_root, "tables/table1-descriptives.html")
  )
}

run_ols <- function(df, y, x, controls = character(), fe = NULL, cluster = NULL) {
  rhs <- paste(c(x, controls), collapse = " + ")
  if (!is.null(fe) && length(fe) > 0) {
    fml <- as.formula(paste(y, "~", rhs, "|", paste(fe, collapse = " + ")))
  } else {
    fml <- as.formula(paste(y, "~", rhs))
  }
  vc <- if (!is.null(cluster)) as.formula(paste("~", cluster)) else "HC3"
  feols(fml, data = df, vcov = vc)
}

run_logit_ame <- function(df, y, x, controls = character()) {
  fml <- as.formula(paste(y, "~", paste(c(x, controls), collapse = " + ")))
  mod <- glm(fml, data = df, family = binomial())
  ame <- avg_slopes(mod, variables = x)
  list(model = mod, ame = ame)
}

export_models <- function(models) {
  table_args <- list(
    statistic = "statistic",
    fmt = 3,
    stars = c("*" = .05, "**" = .01, "***" = .001),
    notes = "括号内为 t/z 统计值；标准误类型和聚类层级见正文或表注。"
  )
  do.call(modelsummary, c(list(models = models, output = file.path(output_root, "tables/table2-main-regression.html")), table_args))
  do.call(modelsummary, c(list(models = models, output = file.path(output_root, "tables/table2-main-regression.tex")), table_args))
  do.call(modelsummary, c(list(models = models, output = file.path(output_root, "tables/table2-main-regression.docx")), table_args))
  do.call(modelsummary, c(list(models = models, output = file.path(output_root, "tables/table2-main-regression.csv")), table_args))
}

plot_coef <- function(model) {
  p <- modelplot(model) +
    geom_vline(xintercept = 0, linetype = "dashed") +
    theme_minimal(base_size = 12) +
    labs(x = "Estimate", y = NULL)
  ggsave(file.path(output_root, "figures/coefplot-main.pdf"), p, width = 7, height = 5)
  ggsave(file.path(output_root, "figures/coefplot-main.png"), p, width = 7, height = 5, dpi = 300)
}

code_reliability <- function(coder_a, coder_b) {
  if (!requireNamespace("irr", quietly = TRUE)) {
    stop("Install irr to compute Cohen's kappa: install.packages('irr')")
  }
  irr::kappa2(data.frame(coder_a, coder_b))
}

# Example usage:
# df <- load_data("data/raw/data.csv") |> clean_data()
# df_a <- make_sample(df, y = "outcome", x = "treatment", controls = c("age", "education"))
# make_table1(df_a, c("outcome", "treatment", "age", "education"))
# m1 <- run_ols(df_a, "outcome", "treatment", c("age", "education"), fe = c("year", "region"), cluster = "region")
# export_models(list("Main" = m1))
# plot_coef(m1)

"""Paper Analysis 4SS - Python template."""

from __future__ import annotations

import os
import re
from pathlib import Path

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf


OUTPUT_ROOT = Path(os.environ.get("OUTPUT_ROOT", "output/paper-analysis"))
for sub in [
    "data",
    "scripts",
    "tables",
    "figures",
    "reports",
    "qual/codebooks",
    "qual/coded-data",
    "qual/anonymized",
    "qual/reliability",
]:
    (OUTPUT_ROOT / sub).mkdir(parents=True, exist_ok=True)


def load_data(path: str | Path) -> pd.DataFrame:
    path = Path(path)
    ext = path.suffix.lower().lstrip(".")
    if ext == "csv":
        return pd.read_csv(path)
    if ext in {"xlsx", "xls"}:
        return pd.read_excel(path)
    if ext == "dta":
        return pd.read_stata(path)
    if ext == "parquet":
        return pd.read_parquet(path)
    raise ValueError(f"Unsupported file type: {ext}")


def clean_data(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    for col in out.select_dtypes(include="object"):
        out[col] = out[col].astype(str).str.strip().replace({"": np.nan, "nan": np.nan})
    return out.drop_duplicates()


def sample_flow(df: pd.DataFrame, y: str, x: str, controls: list[str]) -> pd.DataFrame:
    vars_needed = [y, x, *controls]
    rows = []
    current = df.copy()
    rows.append({"step": "raw", "n": len(current)})
    for var in vars_needed:
        current = current[current[var].notna()]
        rows.append({"step": f"nonmissing_{var}", "n": len(current)})
    flow = pd.DataFrame(rows)
    flow.to_csv(OUTPUT_ROOT / "tables/sample-flow.csv", index=False)
    return flow


def describe_data(df: pd.DataFrame, vars_: list[str]) -> pd.DataFrame:
    table = df[vars_].describe(include="all").T
    numeric_cols = table.select_dtypes(include=[np.number]).columns
    table[numeric_cols] = table[numeric_cols].round(3)
    table.to_csv(OUTPUT_ROOT / "tables/table1-descriptives.csv")
    return table


def run_ols(df: pd.DataFrame, y: str, x: str, controls: list[str], cluster: str | None = None):
    rhs = " + ".join([x, *controls])
    model = smf.ols(f"{y} ~ {rhs}", data=df).fit()
    if cluster:
        model = model.get_robustcov_results(cov_type="cluster", groups=df[cluster])
    else:
        model = model.get_robustcov_results(cov_type="HC3")
    return model


def run_logit_ame(df: pd.DataFrame, y: str, x: str, controls: list[str]):
    rhs = " + ".join([x, *controls])
    model = smf.logit(f"{y} ~ {rhs}", data=df).fit(disp=False)
    ame = model.get_margeff(at="overall", method="dydx")
    return model, ame


def export_regression_text(model, name: str = "table2-main-regression") -> None:
    with open(OUTPUT_ROOT / f"tables/{name}.txt", "w", encoding="utf-8") as f:
        f.write(model.summary().as_text())
        f.write("\n\nNote: use the companion CSV for publication tables with t/z statistics below coefficients.\n")


def export_regression_table(model, name: str = "table2-main-regression") -> pd.DataFrame:
    """Export a publication-style table with t/z statistics below coefficients."""
    params = pd.Series(model.params, index=model.model.exog_names, name="coef")
    stat_values = pd.Series(model.tvalues, index=model.model.exog_names, name="statistic")
    pvalues = pd.Series(model.pvalues, index=model.model.exog_names, name="p")

    rows = []
    for term in params.index:
        coef = params.loc[term]
        stat = stat_values.loc[term]
        p = pvalues.loc[term]
        stars = "***" if p < 0.001 else "**" if p < 0.01 else "*" if p < 0.05 else ""
        rows.append({"term": term, "row": "coef", "estimate": f"{coef:.3f}{stars}"})
        rows.append({"term": term, "row": "t_or_z", "estimate": f"({stat:.3f})"})

    table = pd.DataFrame(rows)
    table.to_csv(OUTPUT_ROOT / f"tables/{name}.csv", index=False)
    return table


def anonymize_text(text: str) -> str:
    text = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "[EMAIL REMOVED]", text)
    text = re.sub(r"(\+?\d[\d\-\s]{7,}\d)", "[PHONE REMOVED]", text)
    text = re.sub(r"\b\d{3}-\d{2}-\d{4}\b", "[ID REMOVED]", text)
    text = re.sub(r"\b1[3-9]\d{9}\b", "[PHONE REMOVED]", text)
    text = re.sub(r"\b\d{17}[\dXx]\b", "[ID REMOVED]", text)
    text = re.sub(r"\b\d{6}(19|20)\d{2}(0[1-9]|1[0-2])([0-2]\d|3[01])\d{3}[\dXx]\b", "[ID REMOVED]", text)
    text = re.sub(r"(微信|WeChat|QQ)[:：]?\s*[A-Za-z0-9_\-]{5,}", r"\1: [ACCOUNT REMOVED]", text)
    text = re.sub(r"\d{4}[年/-]\d{1,2}[月/-]\d{1,2}日?", "[DATE REMOVED]", text)
    return text


def segment_text_file(path: str | Path, document_id: str | None = None) -> pd.DataFrame:
    path = Path(path)
    document_id = document_id or path.stem
    text = anonymize_text(path.read_text(encoding="utf-8"))
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    df = pd.DataFrame(
        {
            "document_id": document_id,
            "segment_id": [f"{document_id}-{i+1:04d}" for i in range(len(paragraphs))],
            "text": paragraphs,
        }
    )
    df.to_csv(OUTPUT_ROOT / f"qual/coded-data/segments-{document_id}.csv", index=False)
    return df


def code_frequency(coded_data: pd.DataFrame) -> pd.DataFrame:
    freq = coded_data["code"].value_counts().rename_axis("code").reset_index(name="n")
    freq["pct"] = freq["n"] / freq["n"].sum() * 100
    freq.to_csv(OUTPUT_ROOT / "tables/qual-code-frequency.csv", index=False)
    return freq


if __name__ == "__main__":
    print("Edit this template with project-specific paths and variables before running.")

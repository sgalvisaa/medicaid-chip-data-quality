# Medicaid and CHIP Enrollment: Data Quality and Trends

**Question:** How has Medicaid and CHIP enrollment changed by state, and can we trust the data?

A small, end-to-end data project in **Databricks**: profile a public CMS dataset with **SQL**, clean it in **Python (pandas)**, analyze trends, and test the cleaning logic.

## Data

- **Source:** CMS, *State Medicaid and CHIP Applications, Eligibility Determinations, and Enrollment Data* (Performance Indicator dataset, January 2026 release), from [data.medicaid.gov](https://data.medicaid.gov/).
- **Size:** 10,302 rows, 44 columns, 51 states (including DC), reporting periods September 2013 to October 2025.
- The raw CSV is not included in this repo. Download it from CMS and load it as a Delta table named `workspace.default.medicaid_enrollment`.

## Repo contents

| File | What it does |
|---|---|
| `sql/data_quality_checks.sql` | Profiling and data quality checks in Databricks SQL |
| `notebooks/medicaid_cleaning.ipynb` | Cleaning in pandas, trend analysis, and unit tests |

## Step 1: Data quality checks (SQL)

| Check | Finding |
|---|---|
| Rows per state per month | Most months have **two rows per state**: Preliminary (P) and Updated (U). Adding them together would **double count** enrollment. |
| Months with one row | September 2013 is U only (baseline month). October 2025 is P only (latest month, not yet updated). |
| Missing months | **2014 through May 2017 are absent.** Monthly trends start in June 2017. |
| Missing values | Total enrollment is NULL only for CT and ME in September 2013. |
| Impossible values | No negatives. Three **zeros** for Rhode Island (Dec 2024 P and U, Jan 2025 P), footnoted "Unable to Provide Data due to System Limitations." A zero here means "not reported," not zero people. |
| Month-over-month jumps above 10% | VA Jan 2019, ID Jan 2020, OK Jul 2021, NC Dec 2023 (all match state **Medicaid expansion** start dates); NH Apr 2023, ID Jun 2023, WY Aug 2023 (drops after continuous enrollment ended). |

The first version of the jump check failed with a divide-by-zero error, which is how the Rhode Island zeros surfaced. `NULLIF(..., 0)` fixed it.

## Step 2: Cleaning decisions (pandas)

1. Kept 7 of 44 columns and renamed them (`state`, `period`, `p_or_u`, `total_enrollment`, `total_footnote`, `medicaid_enrollment`, `chip_enrollment`).
2. Converted counts to numbers (`pd.to_numeric(errors='coerce')`).
3. **Kept Updated rows, plus Preliminary rows only for the latest month**, which has no Updated version yet. This removes the double counting.
4. **Converted zeros to missing** in total and Medicaid enrollment (the pandas equivalent of `NULLIF`). CHIP zeros were left alone, since a real zero is possible there.
5. Converted `period` (YYYYMM) to a real date and sorted by state and month.
6. Saved the result as a separate Delta table, `medicaid_enrollment_clean`. The raw table is never modified.

**Validation after cleaning:**
- 5,202 rows = 51 states x 102 months, exactly one row per state per month (0 duplicates).
- 51 Preliminary rows (latest month only).
- 3 missing values: CT and ME September 2013, RI December 2024 (footnoted). Rhode Island's January 2025 Preliminary zero was removed by the keep rule, because that month has a valid Updated row.

## Step 3: Findings

**National enrollment (June 2017 onward):**

| Point in time | Enrollment | Change |
|---|---|---|
| Feb 2020 (before COVID) | 71.4M | |
| Apr 2023 (peak) | 94.6M | +32.5% |
| Oct 2025 (latest) | 76.8M | -18.9% from peak, still about 7.5% above Feb 2020 |

- Enrollment declined slowly from 2017 to 2019, climbed steadily during the COVID continuous enrollment period, and fell quickly after states resumed eligibility reviews in April 2023 (the "unwinding").
- The month-over-month check in pandas (`pct_change` by state) returned the **same 7 state-months** as the SQL `LAG` query. Two independent methods agree.

**Unwinding by state (Apr 2023 to Oct 2025):**
- Largest declines: Montana (-36%), Utah (-32%), Colorado, Texas, Wyoming (about -30%).
- Smallest declines: Oregon (-8%), California (-9%), Maine and Connecticut (about -10%).
- **North Carolina (+17%) and South Dakota (+2%) grew,** because both expanded Medicaid during the unwinding period.

## Step 4: Tests

The cleaning rules are wrapped in a function, `clean_enrollment()`, and tested on a small hand-built dataset with a known correct answer:

1. One row per state-month after cleaning (no double counting).
2. The latest month keeps its Preliminary row.
3. Zero enrollment becomes missing.
4. The real cleaned table is complete (rows = states x months).

All 4 tests pass.

## Assumptions and limitations

- **Updated rows are treated as the best available value.** The latest month (October 2025) is Preliminary only and may be revised; its drop of about 690,000 is roughly twice the typical monthly decline and should be read with caution.
- **December 2024 national total is understated:** only 50 states reported (Rhode Island missing). The dip that month is a reporting gap, not a real decline.
- **"COVID growth" mixes two causes.** Oklahoma (+87%), Missouri (+77%), and Nebraska (+60%) also expanded Medicaid during 2020-2021, so their growth is not only from continuous enrollment.
- The 2014 to mid-2017 gap means no monthly trend is available for the years right after the original ACA expansion.
- This is a personal project using public CMS data. It is descriptive and does not explain why individual states differ.

## How to run

1. Download the CMS CSV and upload it to Databricks (Free Edition works) as `workspace.default.medicaid_enrollment`.
2. Run `sql/data_quality_checks.sql` in the Databricks SQL editor.
3. Import `notebooks/medicaid_cleaning.ipynb` into Databricks and run all cells.

/* Medicaid and CHIP enrollment: data quality checks (Databricks SQL)
   Table: workspace.default.medicaid_enrollment (raw CMS CSV loaded as a Delta table) */

/* Check #1: Size and date range */
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT `State Abbreviation`) AS states,
       MIN(`Reporting Period`) AS first_month,
       MAX(`Reporting Period`) AS last_month
FROM workspace.default.medicaid_enrollment;

/* Check #2: How many rows per state per month? */
SELECT rows_per_state_month, COUNT(*) AS how_many
FROM (
  SELECT `State Abbreviation`, `Reporting Period`, COUNT(*) AS rows_per_state_month
  FROM workspace.default.medicaid_enrollment
  GROUP BY `State Abbreviation`, `Reporting Period`
)
GROUP BY rows_per_state_month;

/* Check #2b: Which months have only one row per state, and is it P or U? */
SELECT `Reporting Period`, `Preliminary or Updated`, COUNT(*) AS state_count
FROM workspace.default.medicaid_enrollment
GROUP BY `Reporting Period`, `Preliminary or Updated`
HAVING `Reporting Period` IN (
  SELECT `Reporting Period`
  FROM workspace.default.medicaid_enrollment
  GROUP BY `State Abbreviation`, `Reporting Period`
  HAVING COUNT(*) = 1
);

/* Check #3: Are any months missing? */
SELECT LEFT(CAST(`Reporting Period` AS STRING), 4) AS year,
       COUNT(DISTINCT `Reporting Period`) AS months
FROM workspace.default.medicaid_enrollment
GROUP BY year
ORDER BY year;

/* Check #4: Missing values in the main column */
SELECT COUNT(*) AS total_rows,
       COUNT(`Total Medicaid and CHIP Enrollment`) AS has_value,
       COUNT(*) - COUNT(`Total Medicaid and CHIP Enrollment`) AS missing
FROM workspace.default.medicaid_enrollment;

/* Check #4b: Which rows are missing */
SELECT `State Abbreviation`, `Reporting Period`, `Preliminary or Updated`
FROM workspace.default.medicaid_enrollment
WHERE `Total Medicaid and CHIP Enrollment` IS NULL;

/* Check #5a: Impossible values */
SELECT MIN(`Total Medicaid and CHIP Enrollment`) AS smallest,
       MAX(`Total Medicaid and CHIP Enrollment`) AS largest,
       SUM(CASE WHEN `Total Medicaid and CHIP Enrollment` < 0 THEN 1 ELSE 0 END) AS negatives,
       SUM(CASE WHEN `Total Medicaid and CHIP Enrollment` = 0 THEN 1 ELSE 0 END) AS zeros
FROM workspace.default.medicaid_enrollment;

/* Check #5a (cont.): Which rows have zeros, and what do the footnotes say */
SELECT `State Abbreviation`, `Reporting Period`, `Preliminary or Updated`, `Total Medicaid and CHIP Enrollment - footnotes`
FROM workspace.default.medicaid_enrollment
WHERE `Total Medicaid and CHIP Enrollment` = 0;

/* Check #5b: Big jumps from one month to the next (updated rows, 2017 onward) */
SELECT `State Abbreviation`, `Reporting Period`, previous, current,
       ROUND((current - previous) / previous * 100, 1) AS pct_change
FROM (
  SELECT `State Abbreviation`, `Reporting Period`,
        NULLIF(`Total Medicaid and CHIP Enrollment`, 0) AS current,
        LAG(NULLIF(`Total Medicaid and CHIP Enrollment`, 0)) OVER (
            PARTITION BY `State Abbreviation` ORDER BY `Reporting Period`
         ) AS previous
  FROM workspace.default.medicaid_enrollment
  WHERE `Preliminary or Updated` = 'U' AND `Reporting Period` >= 201706
)
WHERE ABS((current - previous) / previous * 100) > 10
ORDER BY pct_change;

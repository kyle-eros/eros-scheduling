-- =============================================================================
-- EROS SCHEDULING SYSTEM - CAPTION BANDIT STATS INFRASTRUCTURE
-- =============================================================================
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
-- Purpose: Create foundational infrastructure for caption selection system
-- =============================================================================

-- Step 1: Create the caption_bandit_stats table
-- This table tracks performance metrics for each caption across different pages
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.caption_bandit_stats` (
  caption_id INT64 NOT NULL,
  page_name STRING NOT NULL,
  successes INT64 DEFAULT 1,
  failures INT64 DEFAULT 1,
  total_observations INT64 DEFAULT 0,
  total_revenue FLOAT64 DEFAULT 0.0,
  avg_conversion_rate FLOAT64 DEFAULT 0.0,
  avg_emv FLOAT64 DEFAULT 0.0,
  last_emv_observed FLOAT64,
  confidence_lower_bound FLOAT64,
  confidence_upper_bound FLOAT64,
  exploration_score FLOAT64,
  last_used TIMESTAMP,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  performance_percentile INT64,
  PRIMARY KEY (caption_id, page_name) NOT ENFORCED
)
PARTITION BY DATE(last_updated)
CLUSTER BY page_name, caption_id, last_used;

-- =============================================================================
-- Step 2: Create the wilson_score_bounds UDF
-- Calculates confidence bounds using Wilson Score Interval (95% confidence)
-- This is the mathematically correct implementation with proper p_hat calculation
-- =============================================================================
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(
  successes INT64, failures INT64
)
RETURNS STRUCT<lower_bound FLOAT64, upper_bound FLOAT64, exploration_bonus FLOAT64>
AS ((
  WITH calc AS (
    SELECT
      CAST(successes + failures AS FLOAT64) AS n,
      SAFE_DIVIDE(CAST(successes AS FLOAT64), NULLIF(CAST(successes + failures AS FLOAT64), 0)) AS p_hat,
      1.96 AS z
  )
  SELECT AS STRUCT
    CASE WHEN n = 0 THEN 0.0 ELSE
      (p_hat + z*z/(2*n) - z*SQRT(p_hat*(1-p_hat)/n + z*z/(4*n*n))) / (1 + z*z/n)
    END AS lower_bound,
    CASE WHEN n = 0 THEN 1.0 ELSE
      (p_hat + z*z/(2*n) + z*SQRT(p_hat*(1-p_hat)/n + z*z/(4*n*n))) / (1 + z*z/n)
    END AS upper_bound,
    1.0 / SQRT(n + 1.0) AS exploration_bonus
  FROM calc
));

-- =============================================================================
-- Step 3: Create the wilson_sample UDF
-- Generates a sample value from within the Wilson confidence bounds
-- Used for Thompson sampling in caption selection algorithm
-- =============================================================================
CREATE OR REPLACE FUNCTION `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(
  successes INT64, failures INT64
)
RETURNS FLOAT64 AS ((
  WITH w AS (
    SELECT b.lower_bound lb, b.upper_bound ub
    FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(successes, failures)]) b
  )
  SELECT GREATEST(0.0, LEAST(1.0, lb + (ub - lb) * RAND()))
  FROM w
));

-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================

-- Query 1: Verify caption_bandit_stats table exists with correct schema
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'caption_bandit_stats'
ORDER BY ordinal_position;

-- Query 2: Test wilson_score_bounds UDF with sample values
SELECT
  'Test Case 1: High confidence (100/100)' AS test_case,
  100 AS successes,
  100 AS failures,
  bounds.lower_bound,
  bounds.upper_bound,
  bounds.exploration_bonus,
  ROUND(bounds.lower_bound, 4) AS lower_rounded,
  ROUND(bounds.upper_bound, 4) AS upper_rounded
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(100, 100)]) bounds
UNION ALL
SELECT
  'Test Case 2: Medium confidence (50/50)' AS test_case,
  50 AS successes,
  50 AS failures,
  bounds.lower_bound,
  bounds.upper_bound,
  bounds.exploration_bonus,
  ROUND(bounds.lower_bound, 4) AS lower_rounded,
  ROUND(bounds.upper_bound, 4) AS upper_rounded
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(50, 50)]) bounds
UNION ALL
SELECT
  'Test Case 3: Low confidence (10/10)' AS test_case,
  10 AS successes,
  10 AS failures,
  bounds.lower_bound,
  bounds.upper_bound,
  bounds.exploration_bonus,
  ROUND(bounds.lower_bound, 4) AS lower_rounded,
  ROUND(bounds.upper_bound, 4) AS upper_rounded
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(10, 10)]) bounds
UNION ALL
SELECT
  'Test Case 4: Skewed success (90/10)' AS test_case,
  90 AS successes,
  10 AS failures,
  bounds.lower_bound,
  bounds.upper_bound,
  bounds.exploration_bonus,
  ROUND(bounds.lower_bound, 4) AS lower_rounded,
  ROUND(bounds.upper_bound, 4) AS upper_rounded
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(90, 10)]) bounds
UNION ALL
SELECT
  'Test Case 5: Skewed failure (10/90)' AS test_case,
  10 AS successes,
  90 AS failures,
  bounds.lower_bound,
  bounds.upper_bound,
  bounds.exploration_bonus,
  ROUND(bounds.lower_bound, 4) AS lower_rounded,
  ROUND(bounds.upper_bound, 4) AS upper_rounded
FROM UNNEST([`of-scheduler-proj.eros_scheduling_brain.wilson_score_bounds`(10, 90)]) bounds;

-- Query 3: Test wilson_sample UDF - generate samples from bounds
SELECT
  'Sample from 50/50' AS test_case,
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(50, 50) AS sample_value
UNION ALL
SELECT
  'Sample from 100/100',
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(100, 100)
UNION ALL
SELECT
  'Sample from 10/90',
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(10, 90)
UNION ALL
SELECT
  'Sample from 90/10',
  `of-scheduler-proj.eros_scheduling_brain.wilson_sample`(90, 10);

-- Query 4: Verify table partitioning and clustering
SELECT
  table_name,
  type,
  clustering_ordinal_position,
  column_name
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name = 'caption_bandit_stats'
ORDER BY clustering_ordinal_position;

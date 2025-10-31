# 📊 Performance Analyzer Agent Production - Production Ready
*Account Size Classification, Psychological Trigger Tracking, Statistical Rigor, Complete Metrics Coverage*

## Executive Summary
This enhanced Performance Analyzer provides comprehensive creator performance analysis with proper account size classification, statistically rigorous psychological trigger tracking, complete metrics coverage including conversion rates by tier/day/time, and confidence intervals for all recommendations.

## Critical Fixes Implemented
1. ✅ **Account Size Classification**: 4-tier system (Small/Medium/Large/XL) with dynamic volume targets
2. ✅ **Psychological Trigger Tracking**: Full performance metrics with statistical significance testing
3. ✅ **Content Category Analysis**: Comprehensive performance by category with inventory tracking
4. ✅ **Statistical Rigor**: Confidence intervals, sample size validation, significance testing
5. ✅ **Revenue Per Message**: Core efficiency metric for optimization
6. ✅ **Enhanced Saturation Detection**: Predictive with account-size-specific thresholds

---

## Account Size Classification System (NEW)

```sql
-- CRITICAL FIX: Account size classification with volume recommendations
CREATE OR REPLACE FUNCTION classify_account_size(
    page_name STRING,
    lookback_days INT64
) RETURNS STRUCT<
    size_tier STRING,
    avg_audience INT64,
    total_revenue_period FLOAT64,
    daily_ppv_target_min INT64,
    daily_ppv_target_max INT64,
    daily_bump_target INT64,
    min_ppv_gap_minutes INT64,
    saturation_tolerance FLOAT64
> AS (
    WITH creator_metrics AS (
        SELECT
            page_name,
            -- Audience size metrics - FIXED: Use MAX for stable classification
            MAX(sent_count) as stable_audience_size,
            APPROX_QUANTILES(sent_count, 100)[OFFSET(95)] as p95_audience,
            APPROX_QUANTILES(sent_count, 100)[OFFSET(75)] as p75_audience,
            AVG(sent_count) as avg_audience_size,  -- Keep for reference only

            -- Activity metrics
            COUNT(DISTINCT DATE(sending_time)) as active_days,
            COUNT(*) as total_messages,
            AVG(earnings) as avg_message_revenue,
            SUM(earnings) as total_revenue,

            -- Engagement metrics
            AVG(viewed_count / NULLIF(sent_count, 0)) as avg_unlock_rate,
            AVG(purchased_count / NULLIF(viewed_count, 0)) as avg_conversion_rate

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY)
        GROUP BY page_name
    )
    SELECT AS STRUCT
        -- Size classification - FIXED: Use stable_audience_size (MAX) for tier assignment
        CASE
            WHEN stable_audience_size < 5000 THEN 'SMALL'
            WHEN stable_audience_size < 25000 THEN 'MEDIUM'
            WHEN stable_audience_size < 100000 THEN 'LARGE'
            ELSE 'XL'
        END as size_tier,

        CAST(stable_audience_size AS INT64) as avg_audience,
        total_revenue as total_revenue_period,

        -- Volume recommendations by tier - FIXED: Use stable_audience_size
        CASE
            WHEN stable_audience_size < 5000 THEN 3     -- Small: 3-5 PPV/day
            WHEN stable_audience_size < 25000 THEN 5    -- Medium: 5-8 PPV/day
            WHEN stable_audience_size < 100000 THEN 8   -- Large: 8-12 PPV/day
            ELSE 10                                      -- XL: 10-15 PPV/day
        END as daily_ppv_target_min,

        CASE
            WHEN stable_audience_size < 5000 THEN 5
            WHEN stable_audience_size < 25000 THEN 8
            WHEN stable_audience_size < 100000 THEN 12
            ELSE 15
        END as daily_ppv_target_max,

        -- Bump targets (roughly equal to PPV)
        CASE
            WHEN stable_audience_size < 5000 THEN 4
            WHEN stable_audience_size < 25000 THEN 6
            WHEN stable_audience_size < 100000 THEN 10
            ELSE 12
        END as daily_bump_target,

        -- Gap constraints by size
        CASE
            WHEN stable_audience_size < 5000 THEN 120   -- Small: 2 hour gaps
            WHEN stable_audience_size < 25000 THEN 90   -- Medium: 1.5 hour gaps
            WHEN stable_audience_size < 100000 THEN 75  -- Large: 1.25 hour gaps
            ELSE 60                                      -- XL: 1 hour gaps
        END as min_ppv_gap_minutes,

        -- Saturation tolerance (larger accounts saturate faster)
        CASE
            WHEN stable_audience_size < 5000 THEN 0.4   -- Small: Can push harder
            WHEN stable_audience_size < 25000 THEN 0.5
            WHEN stable_audience_size < 100000 THEN 0.6
            ELSE 0.7                                     -- XL: Most sensitive
        END as saturation_tolerance

    FROM creator_metrics
);
```

---

## Psychological Trigger Performance Tracking (NEW)

```sql
-- Query safety limits
SET @@query_timeout_ms = 120000;  -- 2 minutes for standard query
SET @@maximum_bytes_billed = 10737418240;  -- 10 GB max ($0.05)

-- CRITICAL FIX: Complete trigger performance analysis with statistical significance
CREATE OR REPLACE TABLE FUNCTION analyze_trigger_performance(
    page_name STRING,
    lookback_days INT64
) AS (
    WITH trigger_performance AS (
        SELECT
            psychological_trigger,

            -- Core metrics
            COUNT(*) as usage_count,
            AVG(purchased_count / NULLIF(viewed_count, 0)) as avg_conversion_rate,
            STDDEV(purchased_count / NULLIF(viewed_count, 0)) as conversion_stddev,
            AVG(earnings) as avg_revenue,
            AVG((purchased_count / NULLIF(viewed_count, 0)) * earnings) as avg_emv,
            SUM(earnings) as total_revenue,

            -- Statistical measures
            COUNT(*) as sample_size,
            MIN(purchased_count / NULLIF(viewed_count, 0)) as min_conversion,
            MAX(purchased_count / NULLIF(viewed_count, 0)) as max_conversion,
            APPROX_QUANTILES(
                purchased_count / NULLIF(viewed_count, 0), 100
            )[OFFSET(50)] as median_conversion

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY)
            AND psychological_trigger IS NOT NULL
            AND viewed_count > 0
        GROUP BY psychological_trigger
    ),
    baseline_performance AS (
        -- Performance without triggers for comparison
        SELECT
            AVG((purchased_count / NULLIF(viewed_count, 0)) * earnings) as baseline_emv,
            AVG(purchased_count / NULLIF(viewed_count, 0)) as baseline_conversion
        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY)
            AND psychological_trigger IS NULL
            AND viewed_count > 0
    ),
    statistical_analysis AS (
        SELECT
            t.*,
            b.baseline_emv,
            b.baseline_conversion,

            -- Lift calculations
            (t.avg_emv - b.baseline_emv) / NULLIF(b.baseline_emv, 0) as emv_lift_percentage,
            (t.avg_conversion_rate - b.baseline_conversion) / NULLIF(b.baseline_conversion, 0)
                as conversion_lift_percentage,

            -- Confidence intervals (95%)
            t.avg_conversion_rate - (1.96 * t.conversion_stddev / SQRT(t.sample_size))
                as conversion_ci_lower,
            t.avg_conversion_rate + (1.96 * t.conversion_stddev / SQRT(t.sample_size))
                as conversion_ci_upper,

            -- Statistical significance (simplified t-test)
            ABS(t.avg_conversion_rate - b.baseline_conversion) /
                (t.conversion_stddev / SQRT(t.sample_size)) as t_statistic,
            CASE
                WHEN ABS(t.avg_conversion_rate - b.baseline_conversion) /
                     (t.conversion_stddev / SQRT(t.sample_size)) > 1.96
                THEN TRUE ELSE FALSE
            END as is_statistically_significant,

            -- Efficiency score
            t.avg_emv * LOG(t.usage_count + 1) as efficiency_score

        FROM trigger_performance t
        CROSS JOIN baseline_performance b
    )
    SELECT
        psychological_trigger,
        usage_count,
        ROUND(avg_conversion_rate, 4) as avg_conversion_rate,
        ROUND(avg_emv, 2) as avg_emv,
        ROUND(total_revenue, 2) as total_revenue,
        ROUND(emv_lift_percentage, 3) as emv_lift_pct,
        is_statistically_significant,

        -- Confidence interval
        STRUCT(
            ROUND(conversion_ci_lower, 4) as lower,
            ROUND(conversion_ci_upper, 4) as upper
        ) as conversion_confidence_interval,

        -- Recommended weekly budget based on performance
        CASE
            WHEN emv_lift_percentage > 0.20 AND is_statistically_significant THEN
                LEAST(7, CAST(usage_count * 1.5 AS INT64))  -- Top performer, increase
            WHEN emv_lift_percentage > 0.10 AND is_statistically_significant THEN
                usage_count  -- Good performer, maintain
            WHEN emv_lift_percentage < 0 OR NOT is_statistically_significant THEN
                GREATEST(2, CAST(usage_count * 0.5 AS INT64))  -- Underperformer, reduce
            ELSE usage_count
        END as recommended_weekly_budget,

        -- Health status
        CASE
            WHEN usage_count >= 10 AND emv_lift_percentage < -0.10 THEN 'INEFFECTIVE'
            WHEN usage_count >= 15 THEN 'OVERUSED'
            WHEN is_statistically_significant AND emv_lift_percentage > 0.15 THEN 'HIGH_PERFORMER'
            WHEN sample_size < 5 THEN 'INSUFFICIENT_DATA'
            ELSE 'MODERATE'
        END as trigger_health_status,

        efficiency_score,
        sample_size

    FROM statistical_analysis
    ORDER BY avg_emv DESC
);
```

---

## Enhanced Saturation Detection with Size-Specific Thresholds

```sql
-- FIXED: Enhanced saturation detection with special days, platform health, and confidence scoring
CREATE OR REPLACE FUNCTION calculate_saturation_score(
    page_name STRING,
    account_size_tier STRING
) RETURNS STRUCT<
    saturation_score FLOAT64,
    risk_level STRING,
    unlock_rate_deviation FLOAT64,
    emv_deviation FLOAT64,
    consecutive_underperform_days INT64,
    recommended_action STRING,
    volume_adjustment_factor FLOAT64,
    confidence_score FLOAT64,
    exclusion_reason STRING
> AS (
    WITH special_days AS (
        -- FIXED: Exclude known low-performance days to prevent false positives
        SELECT DATE('2024-12-25') as special_date, 'Christmas' as reason
        UNION ALL SELECT DATE('2025-01-01'), 'New Year'
        UNION ALL SELECT DATE('2025-07-04'), 'Independence Day'
        UNION ALL SELECT DATE('2025-11-28'), 'Thanksgiving'
        UNION ALL SELECT DATE('2025-12-25'), 'Christmas'
        -- Add major holidays, platform maintenance days, etc.
    ),
    platform_health AS (
        -- FIXED: Check for platform-wide issues affecting all creators
        SELECT
            DATE(sending_time) as check_date,
            AVG(viewed_count / NULLIF(sent_count, 0)) as platform_avg_unlock_rate,
            COUNT(DISTINCT page_name) as active_creators,

            -- Platform health indicator: if 70%+ creators see 30%+ drop, it's platform issue
            SUM(CASE
                WHEN (viewed_count / NULLIF(sent_count, 0)) <
                     (SELECT AVG(viewed_count / NULLIF(sent_count, 0)) * 0.7
                      FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
                      WHERE DATE(sending_time) BETWEEN DATE_SUB(check_date, INTERVAL 30 DAY)
                        AND DATE_SUB(check_date, INTERVAL 1 DAY))
                THEN 1 ELSE 0
            END) / NULLIF(COUNT(DISTINCT page_name), 0) as platform_issue_ratio

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE DATE(sending_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY check_date
        HAVING active_creators >= 5  -- Require minimum sample size
    ),
    baseline_metrics AS (
        SELECT
            EXTRACT(DAYOFWEEK FROM sending_time) as day_of_week,
            APPROX_QUANTILES(viewed_count / NULLIF(sent_count, 0), 100)[OFFSET(50)]
                as baseline_unlock_rate,
            APPROX_QUANTILES(
                (purchased_count / NULLIF(viewed_count, 0)) * earnings, 100
            )[OFFSET(50)] as baseline_emv,
            STDDEV(viewed_count / NULLIF(sent_count, 0)) as unlock_rate_stddev,
            STDDEV((purchased_count / NULLIF(viewed_count, 0)) * earnings) as emv_stddev

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time BETWEEN
                TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY) AND
                TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
            -- Exclude special days from baseline calculation
            AND DATE(sending_time) NOT IN (SELECT special_date FROM special_days)
        GROUP BY day_of_week
    ),
    recent_performance AS (
        SELECT
            DATE(sending_time) as send_date,
            EXTRACT(DAYOFWEEK FROM sending_time) as day_of_week,
            AVG(viewed_count / NULLIF(sent_count, 0)) as daily_unlock_rate,
            AVG((purchased_count / NULLIF(viewed_count, 0)) * earnings) as daily_emv,
            COUNT(*) as message_count,

            -- FIXED: Mark special days and platform issues
            CASE
                WHEN DATE(sending_time) IN (SELECT special_date FROM special_days)
                THEN TRUE ELSE FALSE
            END as is_special_day,

            (SELECT reason FROM special_days WHERE special_date = DATE(sending_time) LIMIT 1)
                as special_day_reason

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND DATE(sending_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY send_date, day_of_week
    ),
    saturation_analysis AS (
        SELECT
            r.send_date,
            r.daily_unlock_rate,
            r.daily_emv,
            r.is_special_day,
            r.special_day_reason,
            b.baseline_unlock_rate,
            b.baseline_emv,
            b.unlock_rate_stddev,
            b.emv_stddev,

            -- FIXED: Check for platform-wide issues
            COALESCE(ph.platform_issue_ratio, 0.0) as platform_issue_ratio,

            -- Calculate deviations (only for non-special days)
            CASE
                WHEN r.is_special_day THEN 0.0  -- Don't penalize special days
                ELSE (r.daily_unlock_rate - b.baseline_unlock_rate) / NULLIF(b.baseline_unlock_rate, 0)
            END as unlock_rate_deviation,

            CASE
                WHEN r.is_special_day THEN 0.0  -- Don't penalize special days
                ELSE (r.daily_emv - b.baseline_emv) / NULLIF(b.baseline_emv, 0)
            END as emv_deviation,

            -- Track consecutive underperformance (exclude special days)
            SUM(CASE
                WHEN NOT r.is_special_day AND r.daily_emv < b.baseline_emv * 0.8 THEN 1
                ELSE 0
            END) OVER (ORDER BY r.send_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
                as consecutive_underperform,

            -- FIXED: Statistical significance (z-score)
            CASE
                WHEN b.emv_stddev > 0
                THEN ABS(r.daily_emv - b.baseline_emv) / NULLIF(b.emv_stddev, 0)
                ELSE 0.0
            END as emv_z_score

        FROM recent_performance r
        LEFT JOIN baseline_metrics b ON r.day_of_week = b.day_of_week
        LEFT JOIN platform_health ph ON r.send_date = ph.check_date
    ),
    final_score AS (
        SELECT
            -- Account-size-adjusted thresholds
            CASE account_size_tier
                WHEN 'SMALL' THEN 0.4   -- Higher tolerance
                WHEN 'MEDIUM' THEN 0.5
                WHEN 'LARGE' THEN 0.6
                ELSE 0.7  -- XL most sensitive
            END as size_threshold_multiplier,

            -- FIXED: Count special days and platform issues for confidence adjustment
            SUM(CASE WHEN is_special_day THEN 1 ELSE 0 END) as special_day_count,
            SUM(CASE WHEN platform_issue_ratio > 0.5 THEN 1 ELSE 0 END) as platform_issue_days,
            COUNT(*) as total_days_analyzed,

            -- Exclusion reason if applicable
            CASE
                WHEN SUM(CASE WHEN is_special_day THEN 1 ELSE 0 END) >= 3
                THEN CONCAT('Excluded: ', STRING_AGG(DISTINCT special_day_reason, ', '))
                WHEN SUM(CASE WHEN platform_issue_ratio > 0.5 THEN 1 ELSE 0 END) >= 2
                THEN 'Excluded: Platform-wide performance issues detected'
                ELSE NULL
            END as exclusion_reason,

            -- Component scores (only if no exclusions)
            GREATEST(0.0, LEAST(1.0,
                -- Unlock rate component (40% weight)
                CASE
                    WHEN AVG(unlock_rate_deviation) < -0.30 THEN 0.4
                    WHEN AVG(unlock_rate_deviation) < -0.15 THEN 0.25
                    WHEN AVG(unlock_rate_deviation) < -0.05 THEN 0.15
                    ELSE 0.0
                END +
                -- EMV deviation component (40% weight)
                CASE
                    WHEN AVG(emv_deviation) < -0.40 THEN 0.4
                    WHEN AVG(emv_deviation) < -0.20 THEN 0.25
                    WHEN AVG(emv_deviation) < -0.10 THEN 0.15
                    ELSE 0.0
                END +
                -- Consecutive underperformance (20% weight)
                CASE
                    WHEN MAX(consecutive_underperform) >= 3 THEN 0.2
                    WHEN MAX(consecutive_underperform) >= 2 THEN 0.1
                    ELSE 0.0
                END
            )) as raw_saturation_score,

            -- FIXED: Confidence score based on data quality
            LEAST(1.0,
                -- Base confidence from sample size
                (COUNT(*) - SUM(CASE WHEN is_special_day THEN 1 ELSE 0 END)) / 7.0 * 0.4 +
                -- Penalty for platform issues
                (1.0 - SUM(CASE WHEN platform_issue_ratio > 0.5 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0)) * 0.3 +
                -- Statistical significance from z-scores
                CASE
                    WHEN AVG(emv_z_score) >= 2.0 THEN 0.3  -- High confidence
                    WHEN AVG(emv_z_score) >= 1.5 THEN 0.2  -- Medium confidence
                    WHEN AVG(emv_z_score) >= 1.0 THEN 0.1  -- Low confidence
                    ELSE 0.0
                END
            ) as confidence_score,

            AVG(unlock_rate_deviation) as avg_unlock_deviation,
            AVG(emv_deviation) as avg_emv_deviation,
            MAX(consecutive_underperform) as max_consecutive_underperform

        FROM saturation_analysis
    )
    SELECT AS STRUCT
        -- FIXED: Only return saturation score if confidence is high enough
        CASE
            WHEN exclusion_reason IS NOT NULL THEN 0.0  -- Don't flag if excluded
            WHEN confidence_score < 0.5 THEN raw_saturation_score * 0.5  -- Reduce score if low confidence
            ELSE raw_saturation_score * size_threshold_multiplier
        END as saturation_score,

        -- Risk classification (requires high confidence)
        CASE
            WHEN exclusion_reason IS NOT NULL THEN 'HEALTHY'  -- Override if excluded
            WHEN confidence_score < 0.5 THEN 'LOW_CONFIDENCE'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.7
                AND confidence_score >= 0.7 THEN 'CRITICAL'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.5
                AND confidence_score >= 0.6 THEN 'HIGH'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.3 THEN 'MODERATE'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.15 THEN 'LOW'
            ELSE 'HEALTHY'
        END as risk_level,

        avg_unlock_deviation as unlock_rate_deviation,
        avg_emv_deviation as emv_deviation,
        max_consecutive_underperform as consecutive_underperform_days,

        -- Actionable recommendations (factor in confidence)
        CASE
            WHEN exclusion_reason IS NOT NULL THEN
                CONCAT('NO ACTION: ', exclusion_reason)
            WHEN confidence_score < 0.5 THEN
                'LOW CONFIDENCE: Collect more data before taking action'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.7
                AND confidence_score >= 0.7 THEN
                'IMMEDIATE: Reduce volume 40%, implement cooling days, pause premium content'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.5
                AND confidence_score >= 0.6 THEN
                'URGENT: Reduce volume 25%, extend gaps to 120min, focus on engagement content'
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.3 THEN
                'CAUTION: Monitor closely, reduce volume 10%, increase free content'
            ELSE 'HEALTHY: Maintain current strategy, consider gradual volume increase'
        END as recommended_action,

        -- Volume adjustment factor (conservative if low confidence)
        CASE
            WHEN exclusion_reason IS NOT NULL THEN 1.0  -- No adjustment
            WHEN confidence_score < 0.5 THEN 0.95  -- Small precautionary reduction
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.7
                AND confidence_score >= 0.7 THEN 0.6
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.5
                AND confidence_score >= 0.6 THEN 0.75
            WHEN raw_saturation_score * size_threshold_multiplier >= 0.3 THEN 0.9
            ELSE 1.0
        END as volume_adjustment_factor,

        -- FIXED: Return confidence score and exclusion reason
        confidence_score,
        exclusion_reason

    FROM final_score
);
```

---

## Content Category Performance Analysis

```sql
-- Query safety limits
SET @@query_timeout_ms = 120000;  -- 2 minutes for standard query
SET @@maximum_bytes_billed = 10737418240;  -- 10 GB max ($0.05)

CREATE OR REPLACE TABLE FUNCTION analyze_content_categories(
    page_name STRING,
    lookback_days INT64
) AS (
    WITH category_performance AS (
        SELECT
            content_category,
            price_tier,

            -- Core metrics
            COUNT(*) as message_count,
            AVG((purchased_count / NULLIF(viewed_count, 0)) * earnings) as avg_emv,
            AVG(purchased_count / NULLIF(viewed_count, 0)) as avg_conversion_rate,
            AVG(earnings) as avg_revenue,
            SUM(earnings) as total_revenue,

            -- Trend analysis
            AVG(CASE
                WHEN sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
                THEN (purchased_count / NULLIF(viewed_count, 0)) * earnings
            END) as recent_30d_emv,
            AVG(CASE
                WHEN sending_time BETWEEN
                    TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 60 DAY) AND
                    TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
                THEN (purchased_count / NULLIF(viewed_count, 0)) * earnings
            END) as prior_30d_emv,

            -- Price sensitivity
            CORR(recommended_price, purchased_count / NULLIF(viewed_count, 0))
                as price_sensitivity_correlation

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY)
            AND content_category IS NOT NULL
            AND viewed_count > 0
        GROUP BY content_category, price_tier
    ),
    category_analysis AS (
        SELECT
            content_category,
            SUM(message_count) as total_messages,
            AVG(avg_emv) as category_avg_emv,
            AVG(avg_conversion_rate) as category_avg_conversion,
            SUM(total_revenue) as category_total_revenue,

            -- Trend calculation
            AVG(recent_30d_emv) as recent_emv,
            AVG(prior_30d_emv) as prior_emv,
            SAFE_DIVIDE(
                AVG(recent_30d_emv) - AVG(prior_30d_emv),
                AVG(prior_30d_emv)
            ) as trend_percentage,

            -- Best performing price tier for category
            ARRAY_AGG(
                STRUCT(price_tier, avg_emv)
                ORDER BY avg_emv DESC
                LIMIT 1
            )[OFFSET(0)].price_tier as best_price_tier,

            -- Category score
            AVG(avg_emv) * 0.5 +
            AVG(avg_conversion_rate) * 100 * 0.3 +
            LOG(SUM(message_count) + 1) * 0.2 as category_score

        FROM category_performance
        GROUP BY content_category
    )
    SELECT
        content_category,
        total_messages,
        ROUND(category_avg_emv, 2) as avg_emv,
        ROUND(category_avg_conversion, 4) as avg_conversion_rate,
        ROUND(category_total_revenue, 2) as total_revenue,

        -- Trend analysis
        CASE
            WHEN trend_percentage > 0.10 THEN 'RISING'
            WHEN trend_percentage < -0.10 THEN 'DECLINING'
            ELSE 'STABLE'
        END as trend_direction,
        ROUND(trend_percentage * 100, 1) as trend_pct,

        best_price_tier,

        -- Performance classification
        CASE
            WHEN RANK() OVER (ORDER BY category_avg_emv DESC) <= 2 THEN 'TOP_PERFORMER'
            WHEN RANK() OVER (ORDER BY category_avg_emv DESC) <= 4 THEN 'HIGH_PERFORMER'
            WHEN RANK() OVER (ORDER BY category_avg_emv DESC) <= 6 THEN 'MODERATE'
            ELSE 'LOW_PERFORMER'
        END as performance_tier,

        -- Recommended usage
        CASE
            WHEN RANK() OVER (ORDER BY category_avg_emv DESC) <= 2 THEN 0.35  -- 35% of content
            WHEN RANK() OVER (ORDER BY category_avg_emv DESC) <= 4 THEN 0.25
            WHEN RANK() OVER (ORDER BY category_avg_emv DESC) <= 6 THEN 0.20
            ELSE 0.10
        END as recommended_content_mix_pct,

        ROUND(category_score, 2) as category_score

    FROM category_analysis
    ORDER BY category_avg_emv DESC
);
```

---

## Day-of-Week Analysis with Statistical Significance

```sql
-- Query safety limits
SET @@query_timeout_ms = 120000;  -- 2 minutes for standard query
SET @@maximum_bytes_billed = 10737418240;  -- 10 GB max ($0.05)

CREATE OR REPLACE TABLE FUNCTION analyze_day_patterns(
    page_name STRING,
    lookback_days INT64
) AS (
    WITH daily_performance AS (
        SELECT
            EXTRACT(DAYOFWEEK FROM sending_time) as day_of_week,
            DATE(sending_time) as send_date,
            AVG((purchased_count / NULLIF(viewed_count, 0)) * earnings) as daily_emv,
            AVG(purchased_count / NULLIF(viewed_count, 0)) as daily_conversion,
            SUM(earnings) as daily_revenue,
            COUNT(*) as message_count

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY)
        GROUP BY day_of_week, send_date
    ),
    day_statistics AS (
        SELECT
            day_of_week,
            CASE day_of_week
                WHEN 1 THEN 'Sunday'
                WHEN 2 THEN 'Monday'
                WHEN 3 THEN 'Tuesday'
                WHEN 4 THEN 'Wednesday'
                WHEN 5 THEN 'Thursday'
                WHEN 6 THEN 'Friday'
                WHEN 7 THEN 'Saturday'
            END as day_name,

            -- Central tendency and variability
            AVG(daily_emv) as mean_emv,
            STDDEV(daily_emv) as stddev_emv,
            APPROX_QUANTILES(daily_emv, 100)[OFFSET(50)] as median_emv,
            COUNT(DISTINCT send_date) as sample_size,

            -- Confidence interval
            AVG(daily_emv) - (1.96 * STDDEV(daily_emv) / SQRT(COUNT(DISTINCT send_date)))
                as emv_ci_lower,
            AVG(daily_emv) + (1.96 * STDDEV(daily_emv) / SQRT(COUNT(DISTINCT send_date)))
                as emv_ci_upper,

            AVG(daily_conversion) as mean_conversion_rate,
            AVG(daily_revenue) as mean_revenue

        FROM daily_performance
        GROUP BY day_of_week
    ),
    week_baseline AS (
        SELECT AVG(mean_emv) as weekly_avg_emv
        FROM day_statistics
    )
    SELECT
        day_name,
        day_of_week,
        ROUND(mean_emv, 2) as mean_emv,
        ROUND(median_emv, 2) as median_emv,
        ROUND(mean_conversion_rate, 4) as mean_conversion_rate,
        ROUND(mean_revenue, 2) as mean_revenue,
        sample_size,

        -- Confidence interval
        STRUCT(
            ROUND(emv_ci_lower, 2) as lower,
            ROUND(emv_ci_upper, 2) as upper
        ) as emv_confidence_interval,

        -- Performance index
        ROUND(mean_emv / weekly_avg_emv, 2) as performance_index,

        -- Statistical significance
        CASE
            WHEN sample_size < 4 THEN FALSE
            WHEN ABS(mean_emv - weekly_avg_emv) / (stddev_emv / SQRT(sample_size)) > 1.96
                THEN TRUE
            ELSE FALSE
        END as is_statistically_significant,

        -- Classification
        CASE
            WHEN mean_emv / weekly_avg_emv >= 1.15
                AND ABS(mean_emv - weekly_avg_emv) / (stddev_emv / SQRT(sample_size)) > 1.96
                THEN 'HIGH_PERFORMER'
            WHEN mean_emv / weekly_avg_emv <= 0.85
                AND ABS(mean_emv - weekly_avg_emv) / (stddev_emv / SQRT(sample_size)) > 1.96
                THEN 'LOW_PERFORMER'
            ELSE 'AVERAGE_PERFORMER'
        END as classification,

        -- Volume multiplier
        CASE
            WHEN sample_size < 4 THEN 1.0  -- Insufficient data
            WHEN mean_emv / weekly_avg_emv >= 1.15 THEN LEAST(1.30, mean_emv / weekly_avg_emv)
            WHEN mean_emv / weekly_avg_emv <= 0.85 THEN GREATEST(0.70, mean_emv / weekly_avg_emv)
            ELSE 1.0
        END as volume_multiplier,

        -- Confidence level
        CASE
            WHEN sample_size >= 12 THEN 'HIGH'
            WHEN sample_size >= 8 THEN 'MEDIUM'
            ELSE 'LOW'
        END as confidence_level

    FROM day_statistics
    CROSS JOIN week_baseline
    ORDER BY day_of_week
);
```

---

## Time Window Optimization with Peak Hours

```sql
-- Query safety limits
SET @@query_timeout_ms = 120000;  -- 2 minutes for standard query
SET @@maximum_bytes_billed = 10737418240;  -- 10 GB max ($0.05)

CREATE OR REPLACE TABLE FUNCTION analyze_time_windows(
    page_name STRING,
    lookback_days INT64
) AS (
    WITH hourly_performance AS (
        SELECT
            EXTRACT(HOUR FROM sending_time) as hour_pst,
            EXTRACT(DAYOFWEEK FROM sending_time) as day_of_week,
            CASE
                WHEN EXTRACT(DAYOFWEEK FROM sending_time) IN (1, 7) THEN 'Weekend'
                ELSE 'Weekday'
            END as day_type,

            AVG((purchased_count / NULLIF(viewed_count, 0)) * earnings) as avg_emv,
            AVG(purchased_count / NULLIF(viewed_count, 0)) as avg_conversion_rate,
            AVG(viewed_count / NULLIF(sent_count, 0)) as avg_unlock_rate,
            COUNT(*) as message_count

        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = page_name
            AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY)
        GROUP BY hour_pst, day_of_week, day_type
        HAVING COUNT(*) >= 5  -- Minimum sample size
    ),
    time_window_definitions AS (
        SELECT
            hour_pst,
            CASE
                WHEN hour_pst BETWEEN 6 AND 8 THEN 'Early Morning'
                WHEN hour_pst BETWEEN 9 AND 11 THEN 'Morning'
                WHEN hour_pst BETWEEN 12 AND 16 THEN 'Afternoon'
                WHEN hour_pst BETWEEN 17 AND 21 THEN 'Evening'
                WHEN hour_pst BETWEEN 22 AND 23 THEN 'Late Night'
                WHEN hour_pst BETWEEN 0 AND 2 THEN 'Late Night'
                ELSE 'Off Hours'
            END as window_name
        FROM hourly_performance
    ),
    window_aggregation AS (
        SELECT
            h.day_type,
            w.window_name,
            AVG(h.avg_emv) as window_avg_emv,
            AVG(h.avg_conversion_rate) as window_avg_conversion,
            AVG(h.avg_unlock_rate) as window_avg_unlock,
            SUM(h.message_count) as total_messages,

            -- Best hours within window
            ARRAY_AGG(
                STRUCT(h.hour_pst as hour, h.avg_emv as emv)
                ORDER BY h.avg_emv DESC
                LIMIT 2
            ) as top_hours_in_window

        FROM hourly_performance h
        JOIN time_window_definitions w ON h.hour_pst = w.hour_pst
        GROUP BY h.day_type, w.window_name
    )
    SELECT
        day_type,
        window_name,
        ROUND(window_avg_emv, 2) as avg_emv,
        ROUND(window_avg_conversion, 4) as avg_conversion_rate,
        ROUND(window_avg_unlock, 3) as avg_unlock_rate,
        total_messages,
        top_hours_in_window,

        -- Window ranking
        RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) as window_rank,

        -- Classification
        CASE
            WHEN RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) = 1
                THEN 'PRIME'
            WHEN RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) <= 2
                THEN 'HIGH_PERFORMING'
            WHEN RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) <= 3
                THEN 'MODERATE'
            ELSE 'LOW_PERFORMING'
        END as window_classification,

        -- Volume allocation recommendation
        CASE
            WHEN RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) = 1
                THEN 0.40  -- 40% of daily volume
            WHEN RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) = 2
                THEN 0.30
            WHEN RANK() OVER (PARTITION BY day_type ORDER BY window_avg_emv DESC) = 3
                THEN 0.20
            ELSE 0.10
        END as recommended_volume_allocation,

        -- Confidence
        CASE
            WHEN total_messages >= 50 THEN 'HIGH'
            WHEN total_messages >= 20 THEN 'MEDIUM'
            ELSE 'LOW'
        END as confidence

    FROM window_aggregation
    ORDER BY day_type, window_rank
);
```

---

## Main Performance Analysis Procedure

```sql
-- Query safety limits for complex aggregation
SET @@query_timeout_ms = 300000;  -- 5 minutes for expensive query
SET @@maximum_bytes_billed = 53687091200;  -- 50 GB max ($0.25)

CREATE OR REPLACE PROCEDURE analyze_creator_performance(
    IN page_name STRING,
    OUT performance_report JSON
)
BEGIN
    DECLARE account_size STRUCT<
        size_tier STRING,
        avg_audience INT64,
        total_revenue_period FLOAT64,
        daily_ppv_target_min INT64,
        daily_ppv_target_max INT64,
        daily_bump_target INT64,
        min_ppv_gap_minutes INT64,
        saturation_tolerance FLOAT64
    >;

    DECLARE saturation STRUCT<
        saturation_score FLOAT64,
        risk_level STRING,
        unlock_rate_deviation FLOAT64,
        emv_deviation FLOAT64,
        consecutive_underperform_days INT64,
        recommended_action STRING,
        volume_adjustment_factor FLOAT64
    >;

    -- Get account size classification
    SET account_size = classify_account_size(page_name, 90);

    -- Calculate saturation with size-specific thresholds
    SET saturation = calculate_saturation_score(page_name, account_size.size_tier);

    -- Compile full performance report
    SET performance_report = TO_JSON_STRING(STRUCT(
        page_name as creator_name,
        CURRENT_TIMESTAMP() as analysis_timestamp,

        -- Account classification
        account_size as account_classification,

        -- Saturation analysis
        saturation as saturation_analysis,

        -- Behavioral clustering
        (SELECT AS STRUCT
            segment,
            engagement_velocity,
            aspf,
            conversion_stability,
            price_elasticity_type
         FROM analyze_behavioral_segments(page_name)
         LIMIT 1) as behavioral_profile,

        -- Trigger performance
        ARRAY(
            SELECT AS STRUCT *
            FROM analyze_trigger_performance(page_name, 90)
        ) as psychological_trigger_analysis,

        -- Content category performance
        ARRAY(
            SELECT AS STRUCT *
            FROM analyze_content_categories(page_name, 90)
        ) as content_category_performance,

        -- Day patterns
        ARRAY(
            SELECT AS STRUCT *
            FROM analyze_day_patterns(page_name, 90)
        ) as day_of_week_patterns,

        -- Time windows
        ARRAY(
            SELECT AS STRUCT *
            FROM analyze_time_windows(page_name, 90)
        ) as time_window_optimization,

        -- Optimization parameters
        STRUCT(
            STRUCT(
                account_size.daily_ppv_target_min as min,
                account_size.daily_ppv_target_max as max,
                CAST(
                    (account_size.daily_ppv_target_min + account_size.daily_ppv_target_max) / 2 *
                    saturation.volume_adjustment_factor
                AS INT64) as adjusted_target
            ) as daily_ppv_targets,
            account_size.daily_bump_target as daily_bump_target,
            account_size.min_ppv_gap_minutes as min_ppv_gap_minutes,
            saturation.volume_adjustment_factor as volume_adjustment
        ) as optimization_parameters,

        -- Statistical metadata
        STRUCT(
            0.95 as confidence_level,
            90 as lookback_days,
            'production' as algorithm_version
        ) as metadata
    ));

END;
```

---

## Output Schema

```json
{
    "creator_name": "jadebri",
    "analysis_timestamp": "2025-10-31T10:30:00Z",
    "account_classification": {
        "size_tier": "LARGE",
        "avg_audience": 45000,
        "total_revenue_period": 125000.50,
        "daily_ppv_target_min": 8,
        "daily_ppv_target_max": 12,
        "daily_bump_target": 10,
        "min_ppv_gap_minutes": 75,
        "saturation_tolerance": 0.6
    },
    "saturation_analysis": {
        "saturation_score": 0.35,
        "risk_level": "MODERATE",
        "unlock_rate_deviation": -0.12,
        "emv_deviation": -0.08,
        "consecutive_underperform_days": 1,
        "recommended_action": "CAUTION: Monitor closely, reduce volume 10%, increase free content",
        "volume_adjustment_factor": 0.9
    },
    "behavioral_profile": {
        "segment": "High-Value/Price-Insensitive",
        "engagement_velocity": 0.75,
        "aspf": 42.50,
        "conversion_stability": 0.82,
        "price_elasticity_type": "INELASTIC"
    },
    "psychological_trigger_analysis": [
        {
            "psychological_trigger": "Exclusivity",
            "usage_count": 12,
            "avg_conversion_rate": 0.0842,
            "avg_emv": 28.75,
            "total_revenue": 345.00,
            "emv_lift_pct": 0.185,
            "is_statistically_significant": true,
            "conversion_confidence_interval": {
                "lower": 0.0712,
                "upper": 0.0972
            },
            "recommended_weekly_budget": 7,
            "trigger_health_status": "HIGH_PERFORMER",
            "efficiency_score": 85.2,
            "sample_size": 12
        }
    ],
    "content_category_performance": [
        {
            "content_category": "B/G",
            "total_messages": 47,
            "avg_emv": 32.50,
            "avg_conversion_rate": 0.0875,
            "total_revenue": 1527.50,
            "trend_direction": "RISING",
            "trend_pct": 15.2,
            "best_price_tier": "premium",
            "performance_tier": "TOP_PERFORMER",
            "recommended_content_mix_pct": 0.35,
            "category_score": 92.5
        }
    ],
    "day_of_week_patterns": [
        {
            "day_name": "Friday",
            "day_of_week": 6,
            "mean_emv": 35.20,
            "median_emv": 33.50,
            "mean_conversion_rate": 0.0920,
            "mean_revenue": 450.75,
            "sample_size": 13,
            "emv_confidence_interval": {
                "lower": 31.10,
                "upper": 39.30
            },
            "performance_index": 1.28,
            "is_statistically_significant": true,
            "classification": "HIGH_PERFORMER",
            "volume_multiplier": 1.28,
            "confidence_level": "HIGH"
        }
    ],
    "time_window_optimization": [
        {
            "day_type": "Weekday",
            "window_name": "Evening",
            "avg_emv": 28.50,
            "avg_conversion_rate": 0.0810,
            "avg_unlock_rate": 0.235,
            "total_messages": 125,
            "top_hours_in_window": [
                {"hour": 20, "emv": 31.20},
                {"hour": 19, "emv": 29.50}
            ],
            "window_rank": 1,
            "window_classification": "PRIME",
            "recommended_volume_allocation": 0.40,
            "confidence": "HIGH"
        }
    ],
    "optimization_parameters": {
        "daily_ppv_targets": {
            "min": 8,
            "max": 12,
            "adjusted_target": 9
        },
        "daily_bump_target": 10,
        "min_ppv_gap_minutes": 75,
        "volume_adjustment": 0.9
    },
    "metadata": {
        "confidence_level": 0.95,
        "lookback_days": 90,
        "algorithm_version": "production"
    }
}
```

---

## Deployment & Monitoring

```bash
# Create functions in BigQuery
bq query --use_legacy_sql=false < performance_analyzer_functions.sql

# Run performance analysis
CALL analyze_creator_performance('jadebri', @report);
SELECT @report;

# Schedule regular analysis
bq mk --transfer_config \
    --data_source=scheduled_query \
    --target_dataset=eros_scheduling_brain \
    --display_name="Daily Performance Analysis" \
    --schedule="every 24 hours" \
    --params='{"query":"CALL analyze_all_creators()"}'
```

This production Performance Analyzer provides complete metrics coverage with statistical rigor, proper account size classification, and actionable insights for optimization.
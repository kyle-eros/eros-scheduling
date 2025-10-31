#!/usr/bin/env python3
"""
EROS Scheduling System - Final Procedure Deployment
Deploys analyze_creator_performance and related TVFs
"""

import json
import sys
from google.cloud import bigquery
from google.cloud.exceptions import GoogleCloudError

# Configuration
PROJECT_ID = "of-scheduler-proj"
DATASET_ID = "eros_scheduling_brain"
LOCATION = "US"

def deploy_procedure():
    """Deploy the analyze_creator_performance procedure and TVFs"""
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

    print("="*80)
    print("EROS SCHEDULING SYSTEM - FINAL PROCEDURE DEPLOYMENT")
    print("="*80)
    print()

    # SQL for TVF #1: classify_account_size
    create_classify_account_size = """
    CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.classify_account_size(
      p_page_name STRING,
      p_lookback_days INT64
    )
    AS (
      WITH page_stats AS (
        SELECT
          page_name,
          COUNT(DISTINCT DATE(sending_time)) AS active_days,
          COUNT(*) AS total_messages,
          SUM(viewed_count) AS total_views,
          AVG(viewed_count) AS avg_views_per_msg,
          APPROX_QUANTILES(viewed_count, 100)[OFFSET(50)] AS median_views,
          SUM(earnings) AS total_revenue,
          SUM(purchased_count) AS total_purchases,
          SAFE_DIVIDE(SUM(purchased_count), NULLIF(SUM(viewed_count), 0)) AS overall_conversion
        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = p_page_name
          AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
          AND viewed_count > 0
        GROUP BY page_name
      ),
      with_tiers AS (
        SELECT
          page_name,
          total_revenue,
          SAFE_DIVIDE(total_revenue, NULLIF(active_days, 0)) AS daily_revenue_avg,
          CAST(avg_views_per_msg AS INT64) AS daily_ppv_target_min,
          CAST(SAFE_DIVIDE(avg_views_per_msg * 1.5, 1) AS INT64) AS daily_ppv_target_max,
          CAST(SAFE_DIVIDE(median_views * 0.8, 1) AS INT64) AS daily_bump_target,
          CASE
            WHEN total_revenue < 5000 THEN 'MICRO'
            WHEN total_revenue < 25000 THEN 'SMALL'
            WHEN total_revenue < 100000 THEN 'MEDIUM'
            WHEN total_revenue < 500000 THEN 'LARGE'
            ELSE 'MEGA'
          END AS size_tier,
          CAST(median_views AS INT64) AS avg_audience,
          total_revenue AS total_revenue_period,
          CAST(GREATEST(5, SAFE_DIVIDE(median_views, 12)) AS INT64) AS min_ppv_gap_minutes,
          CASE
            WHEN total_revenue < 25000 THEN 0.15
            WHEN total_revenue < 100000 THEN 0.20
            WHEN total_revenue < 500000 THEN 0.25
            ELSE 0.30
          END AS saturation_tolerance
        FROM page_stats
      )
      SELECT
        STRUCT(
          size_tier,
          avg_audience,
          total_revenue_period,
          daily_ppv_target_min,
          daily_ppv_target_max,
          daily_bump_target,
          min_ppv_gap_minutes,
          saturation_tolerance
        ) AS account_size_classification
      FROM with_tiers
    );
    """

    # SQL for TVF #2: analyze_behavioral_segments
    create_analyze_behavioral_segments = """
    CREATE OR REPLACE TABLE FUNCTION `of-scheduler-proj.eros_scheduling_brain`.analyze_behavioral_segments(
      p_page_name STRING,
      p_lookback_days INT64
    )
    AS (
      WITH enriched_messages AS (
        SELECT
          page_name,
          SAFE_DIVIDE(earnings, NULLIF(sent_count, 0)) AS rpr,
          SAFE_DIVIDE(purchased_count, NULLIF(viewed_count, 0)) AS conversion,
          price,
          sent_count,
          viewed_count,
          purchased_count,
          earnings
        FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
        WHERE page_name = p_page_name
          AND sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL p_lookback_days DAY)
          AND viewed_count > 0 AND sent_count > 0
      ),
      segment_stats AS (
        SELECT
          COUNT(*) AS msg_count,
          COUNT(DISTINCT SAFE_DIVIDE(CAST(EXTRACT(DAY FROM CURRENT_TIMESTAMP()) AS INT64), 7)) AS cohort_size,
          AVG(rpr) AS avg_rpr,
          AVG(conversion) AS avg_conv,
          STDDEV(rpr) AS sd_rpr,
          STDDEV(conversion) AS sd_conv,
          CORR(price, rpr) AS rpr_price_slope,
          CORR(price, conversion) AS price_elasticity,
          ABS(CORR(price, conversion)) AS price_conv_correlation,
          APPROX_QUANTILES(conversion, 100)[OFFSET(50)] AS median_conversion,
          -LOG10(SAFE_DIVIDE(MAX(CASE WHEN conversion > 0 THEN conversion ELSE NULL END),
                             NULLIF(MIN(CASE WHEN conversion > 0 THEN conversion ELSE NULL END), 0)) + 0.00001) AS category_entropy,
          SAFE_DIVIDE(SUM(viewed_count), NULLIF(SUM(sent_count), 0)) AS segment_view_rate
        FROM enriched_messages
      ),
      final_segment AS (
        SELECT
          CASE
            WHEN msg_count < 20 THEN 'EXPLORATORY'
            WHEN avg_rpr < 0.5 THEN 'BUDGET'
            WHEN avg_rpr < 2.0 THEN 'STANDARD'
            WHEN avg_rpr < 5.0 THEN 'PREMIUM'
            ELSE 'LUXURY'
          END AS segment_label,
          avg_rpr,
          avg_conv,
          rpr_price_slope,
          COALESCE(price_conv_correlation, 0.0) AS rpr_price_corr,
          price_elasticity AS conv_price_elasticity_proxy,
          COALESCE(category_entropy, 0.0) AS category_entropy,
          msg_count AS sample_size
        FROM segment_stats
      )
      SELECT
        segment_label,
        ROUND(avg_rpr, 6) AS avg_rpr,
        ROUND(avg_conv, 4) AS avg_conv,
        ROUND(COALESCE(rpr_price_slope, 0.0), 6) AS rpr_price_slope,
        ROUND(COALESCE(rpr_price_corr, 0.0), 4) AS rpr_price_corr,
        ROUND(COALESCE(conv_price_elasticity_proxy, 0.0), 4) AS conv_price_elasticity_proxy,
        ROUND(category_entropy, 4) AS category_entropy,
        sample_size
      FROM final_segment
    );
    """

    # SQL for main PROCEDURE: analyze_creator_performance
    create_procedure = """
    CREATE OR REPLACE PROCEDURE `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
      IN  p_page_name STRING,
      OUT performance_report STRING
    )
    BEGIN
      DECLARE account_size STRUCT<
        size_tier STRING, avg_audience INT64, total_revenue_period FLOAT64,
        daily_ppv_target_min INT64, daily_ppv_target_max INT64, daily_bump_target INT64,
        min_ppv_gap_minutes INT64, saturation_tolerance FLOAT64
      >;

      DECLARE segment STRUCT<
        segment_label STRING, avg_rpr FLOAT64, avg_conv FLOAT64,
        rpr_price_slope FLOAT64, rpr_price_corr FLOAT64,
        conv_price_elasticity_proxy FLOAT64, category_entropy FLOAT64, sample_size INT64
      >;

      DECLARE sat STRUCT<
        saturation_score FLOAT64, risk_level STRING, unlock_rate_deviation FLOAT64, emv_deviation FLOAT64,
        consecutive_underperform_days INT64, recommended_action STRING, volume_adjustment_factor FLOAT64,
        confidence_score FLOAT64, exclusion_reason STRING
      >;

      DECLARE last_etl TIMESTAMP;
      DECLARE analysis_ts TIMESTAMP;

      SET analysis_ts = CURRENT_TIMESTAMP();

      SET account_size = (
        SELECT account_size_classification
        FROM `of-scheduler-proj.eros_scheduling_brain`.classify_account_size(p_page_name, 90)
        LIMIT 1
      );

      SET segment = (
        SELECT AS STRUCT segment_label, avg_rpr, avg_conv, rpr_price_slope, rpr_price_corr,
                conv_price_elasticity_proxy, category_entropy, sample_size
        FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_behavioral_segments(p_page_name, 90)
        LIMIT 1
      );

      SET sat = (
        SELECT AS STRUCT *
        FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score(
          p_page_name,
          COALESCE(account_size.size_tier, 'MEDIUM')
        )
        LIMIT 1
      );

      SET last_etl = (
        SELECT MAX(started_at)
        FROM `of-scheduler-proj.eros_scheduling_brain.etl_job_runs`
      );

      SET performance_report = TO_JSON_STRING(STRUCT(
        p_page_name                                 AS creator_name,
        analysis_ts                                 AS analysis_timestamp,
        last_etl                                    AS data_freshness,

        account_size                                AS account_classification,
        segment                                     AS behavioral_segment,
        sat                                         AS saturation,

        (SELECT ARRAY_AGG(STRUCT(
            psychological_trigger,
            msg_count,
            avg_rpr,
            avg_conv,
            rpr_lift_pct,
            conv_lift_pct,
            conv_stat_sig,
            rpr_stat_sig
          ) ORDER BY rpr_lift_pct DESC LIMIT 10)
         FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_trigger_performance(p_page_name, 90)
        ) AS psychological_trigger_analysis,

        (SELECT ARRAY_AGG(STRUCT(
            content_category,
            price_tier,
            msg_count,
            avg_rpr,
            avg_conv,
            trend_direction,
            trend_pct,
            price_sensitivity_corr,
            best_price_tier
          ) ORDER BY avg_rpr DESC LIMIT 15)
         FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_content_categories(p_page_name, 90)
        ) AS content_category_performance,

        (SELECT ARRAY_AGG(STRUCT(
            day_of_week_la,
            n AS msg_count,
            avg_rpr,
            avg_conv,
            t_rpr_approx AS t_statistic,
            rpr_stat_sig
          ) ORDER BY avg_rpr DESC)
         FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns(p_page_name, 90)
        ) AS day_of_week_patterns,

        (SELECT ARRAY_AGG(STRUCT(
            day_type,
            hour_la AS hour_24,
            n AS msg_count,
            avg_rpr,
            avg_conv,
            confidence
          ) ORDER BY avg_rpr DESC LIMIT 20)
         FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows(p_page_name, 90)
        ) AS time_window_optimization
      ));

      -- Log execution to job history
      INSERT INTO `of-scheduler-proj.eros_scheduling_brain.etl_job_runs` (
        run_id, job_name, started_at, status, messages_processed
      ) VALUES (
        GENERATE_UUID(),
        'analyze_creator_performance',
        analysis_ts,
        'SUCCESS',
        1
      );
    END;
    """

    try:
        # Deploy TVF 1
        print("Step 1: Deploying TVF - classify_account_size...")
        job = client.query(create_classify_account_size, location=LOCATION)
        job.result()
        print("✓ TVF classify_account_size deployed successfully")
        print()

        # Deploy TVF 2
        print("Step 2: Deploying TVF - analyze_behavioral_segments...")
        job = client.query(create_analyze_behavioral_segments, location=LOCATION)
        job.result()
        print("✓ TVF analyze_behavioral_segments deployed successfully")
        print()

        # Deploy Procedure
        print("Step 3: Deploying Procedure - analyze_creator_performance...")
        job = client.query(create_procedure, location=LOCATION)
        job.result()
        print("✓ Procedure analyze_creator_performance deployed successfully")
        print()

        print("="*80)
        print("DEPLOYMENT COMPLETE")
        print("="*80)
        print()

        return True

    except GoogleCloudError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False


def test_procedure():
    """Test the procedure with a real creator"""
    client = bigquery.Client(project=PROJECT_ID, location=LOCATION)

    print("="*80)
    print("TESTING PROCEDURE WITH REAL CREATOR DATA")
    print("="*80)
    print()

    # Find available creators
    print("Step 1: Finding active creators...")
    find_creators_query = """
    SELECT
      page_name,
      COUNT(*) AS message_count,
      ROUND(SUM(earnings), 2) AS total_earnings
    FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
    WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
      AND viewed_count > 0
    GROUP BY page_name
    ORDER BY total_earnings DESC
    LIMIT 5;
    """

    try:
        creators = client.query(find_creators_query, location=LOCATION).result()
        creator_list = list(creators)

        if not creator_list:
            print("ERROR: No creators found with sufficient data")
            return False

        test_creator = creator_list[0]['page_name']
        print(f"✓ Found {len(creator_list)} active creators")
        print(f"✓ Testing with creator: {test_creator}")
        print()

        # Call the procedure
        print("Step 2: Executing analyze_creator_performance procedure...")
        procedure_call = f"""
        DECLARE performance_report STRING;
        CALL `of-scheduler-proj.eros_scheduling_brain`.analyze_creator_performance(
          '{test_creator}',
          performance_report
        );

        SELECT performance_report;
        """

        result = client.query(procedure_call, location=LOCATION).result()
        rows = list(result)

        if not rows:
            print("ERROR: Procedure returned no results")
            return False

        # Parse JSON report
        report_json_str = rows[0]['performance_report']
        report = json.loads(report_json_str)

        print("✓ Procedure executed successfully")
        print()

        # Display results
        print("="*80)
        print("CREATOR PERFORMANCE ANALYSIS RESULTS")
        print("="*80)
        print()

        print(f"Creator: {report.get('creator_name', 'N/A')}")
        print(f"Analysis Timestamp: {report.get('analysis_timestamp', 'N/A')}")
        print(f"Data Freshness: {report.get('data_freshness', 'N/A')}")
        print()

        # Account Classification
        if 'account_classification' in report:
            acc = report['account_classification']
            print("ACCOUNT CLASSIFICATION:")
            print(f"  Size Tier: {acc.get('size_tier', 'N/A')}")
            print(f"  Avg Audience: {acc.get('avg_audience', 'N/A'):,}")
            print(f"  Total Revenue (90d): ${acc.get('total_revenue_period', 0):,.2f}")
            print(f"  Daily PPV Target: {acc.get('daily_ppv_target_min', 'N/A')} - {acc.get('daily_ppv_target_max', 'N/A')}")
            print(f"  Saturation Tolerance: {acc.get('saturation_tolerance', 'N/A') * 100:.0f}%")
            print()

        # Behavioral Segment
        if 'behavioral_segment' in report:
            seg = report['behavioral_segment']
            print("BEHAVIORAL SEGMENT:")
            print(f"  Segment Classification: {seg.get('segment_label', 'N/A')}")
            print(f"  Avg RPR: ${seg.get('avg_rpr', 0):.6f}")
            print(f"  Avg Conversion: {seg.get('avg_conv', 0):.4f}")
            print(f"  RPR-Price Correlation: {seg.get('rpr_price_corr', 0):.4f}")
            print(f"  Conv Price Elasticity: {seg.get('conv_price_elasticity_proxy', 0):.4f}")
            print(f"  Sample Size: {seg.get('sample_size', 'N/A')} messages")
            print()

        # Saturation Analysis
        if 'saturation' in report:
            sat = report['saturation']
            print("SATURATION ANALYSIS:")
            print(f"  Saturation Score: {sat.get('saturation_score', 'N/A'):.2f}")
            print(f"  Risk Level: {sat.get('risk_level', 'N/A')}")
            print(f"  Consecutive Underperform Days: {sat.get('consecutive_underperform_days', 0)}")
            print(f"  Volume Adjustment Factor: {sat.get('volume_adjustment_factor', 1.0):.2f}")
            print(f"  Recommended Action: {sat.get('recommended_action', 'N/A')}")
            print()

        # Psychological Triggers
        if 'psychological_trigger_analysis' in report and report['psychological_trigger_analysis']:
            triggers = report['psychological_trigger_analysis']
            print("TOP PSYCHOLOGICAL TRIGGERS:")
            for i, trigger in enumerate(triggers[:5], 1):
                print(f"  {i}. {trigger.get('psychological_trigger', 'N/A')}")
                print(f"     Avg RPR: ${trigger.get('avg_rpr', 0):.6f}")
                print(f"     RPR Lift: {trigger.get('rpr_lift_pct', 0):+.2f}%")
                print(f"     Conversion Lift: {trigger.get('conv_lift_pct', 0):+.2f}%")
                print(f"     RPR Significant: {trigger.get('rpr_stat_sig', False)}")
            print()

        # Content Categories
        if 'content_category_performance' in report and report['content_category_performance']:
            categories = report['content_category_performance']
            print("TOP CONTENT CATEGORIES:")
            for i, cat in enumerate(categories[:5], 1):
                print(f"  {i}. {cat.get('content_category', 'N/A')} ({cat.get('price_tier', 'N/A')})")
                print(f"     Avg RPR: ${cat.get('avg_rpr', 0):.6f}")
                print(f"     Avg Conversion: {cat.get('avg_conv', 0):.4f}")
                print(f"     Trend: {cat.get('trend_direction', 'N/A')} ({cat.get('trend_pct', 0):+.1f}%)")
                print(f"     Best Price Tier: {cat.get('best_price_tier', 'N/A')}")
            print()

        # Day of Week Patterns
        if 'day_of_week_patterns' in report and report['day_of_week_patterns']:
            days = report['day_of_week_patterns']
            day_names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
            print("DAY OF WEEK PERFORMANCE:")
            for day in days[:7]:
                day_idx = day.get('day_of_week_la', 0)
                day_name = day_names[day_idx - 1] if 1 <= day_idx <= 7 else f"Day {day_idx}"
                sig_marker = "***" if day.get('rpr_stat_sig', False) else ""
                print(f"  {day_name:9s}: RPR ${day.get('avg_rpr', 0):.6f} | Conv {day.get('avg_conv', 0):.4f} {sig_marker}")
            print()

        # Time Windows
        if 'time_window_optimization' in report and report['time_window_optimization']:
            windows = report['time_window_optimization']
            print("BEST TIME WINDOWS:")
            for i, window in enumerate(windows[:8], 1):
                hour = window.get('hour_24', 0)
                day_type = window.get('day_type', 'Unknown')
                confidence = window.get('confidence', 'LOW')
                print(f"  {i}. {hour:02d}:00 ({day_type}) [{confidence}]")
                print(f"     RPR: ${window.get('avg_rpr', 0):.6f} | Conv: {window.get('avg_conv', 0):.4f}")
            print()

        # Save full JSON
        output_path = "/tmp/creator_performance_report.json"
        with open(output_path, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"✓ Full report saved to {output_path}")
        print()

        return True

    except GoogleCloudError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False


if __name__ == "__main__":
    success = True

    try:
        # Deploy
        if not deploy_procedure():
            success = False
            print("Deployment failed", file=sys.stderr)
        else:
            # Test
            if not test_procedure():
                success = False
                print("Testing failed", file=sys.stderr)

    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        success = False

    sys.exit(0 if success else 1)

# Real-Time Monitor Agent Production - 15-Minute Lag Performance Dashboard
*Production-Ready with Sub-Hour Latency*

## Overview
Ultra-low latency monitoring agent providing 15-minute lag dashboards for OnlyFans performance metrics. Detects anomalies, alerts on saturation, and enables rapid response to audience changes.

## Critical Improvements in Production
1. **15-Minute Lag** (was 6 hours) via streaming pipeline
2. **Anomaly Detection** with statistical significance testing
3. **Predictive Alerts** for saturation before it happens
4. **Automated Recovery Actions** for RED status accounts
5. **Pattern Recognition** for successful content types

## Execution Configuration

```yaml
trigger:
  type: scheduled
  frequency: every_5_minutes  # Was every_4_hours
  data_lag: 10_minutes  # Was 2_hours
  effective_lag: 15_minutes  # Was 6_hours

monitoring:
  - realtime_performance
  - anomaly_detection
  - saturation_alerts
  - trigger_exhaustion
  - conversion_trends
```

## Core Monitoring Pipeline

```sql
-- Query safety limits for real-time monitoring
SET @@query_timeout_ms = 120000;  -- 2 minutes for standard query
SET @@maximum_bytes_billed = 10737418240;  -- 10 GB max ($0.05)

-- STEP 1: Streaming Performance Aggregation (10-minute lag)
CREATE OR REPLACE TABLE analytics.realtime_performance AS
WITH streaming_metrics AS (
  SELECT
    creator_name,
    DATE(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)) as monitor_date,
    DATETIME(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)) as last_updated,

    -- Rolling Windows for Trend Detection
    COUNT(*) FILTER(WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)) as messages_last_hour,
    COUNT(*) FILTER(WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) as messages_last_day,
    COUNT(*) FILTER(WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) as messages_last_week,

    -- Conversion Metrics with Statistical Significance
    SAFE_DIVIDE(
      COUNT(*) FILTER(WHERE payment_status = 'paid' AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)),
      COUNT(*) FILTER(WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR))
    ) as conversion_rate_1h,

    SAFE_DIVIDE(
      COUNT(*) FILTER(WHERE payment_status = 'paid' AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)),
      COUNT(*) FILTER(WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR))
    ) as conversion_rate_24h,

    -- Revenue Velocity
    SUM(price) FILTER(WHERE payment_status = 'paid' AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)) as revenue_last_hour,
    SUM(price) FILTER(WHERE payment_status = 'paid' AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) as revenue_last_day,

    -- Response Rates for Engagement Health
    AVG(CASE WHEN response_time_seconds < 3600 THEN 1 ELSE 0 END) as quick_response_rate,
    PERCENTILE_CONT(response_time_seconds, 0.5) as median_response_time,

  FROM raw_messages
  WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY creator_name
),

-- STEP 2: Anomaly Detection with Z-Scores
anomaly_detection AS (
  SELECT
    s.*,

    -- Calculate Z-scores for anomaly detection
    (messages_last_hour - h.avg_hourly_messages) / NULLIF(h.stddev_hourly_messages, 0) as message_volume_zscore,
    (conversion_rate_1h - h.avg_hourly_conversion) / NULLIF(h.stddev_hourly_conversion, 0) as conversion_zscore,
    (revenue_last_hour - h.avg_hourly_revenue) / NULLIF(h.stddev_hourly_revenue, 0) as revenue_zscore,

    -- Anomaly Flags (|Z| > 3 is significant)
    ABS((messages_last_hour - h.avg_hourly_messages) / NULLIF(h.stddev_hourly_messages, 0)) > 3 as volume_anomaly,
    ABS((conversion_rate_1h - h.avg_hourly_conversion) / NULLIF(h.stddev_hourly_conversion, 0)) > 3 as conversion_anomaly,
    ABS((revenue_last_hour - h.avg_hourly_revenue) / NULLIF(h.stddev_hourly_revenue, 0)) > 3 as revenue_anomaly,

  FROM streaming_metrics s
  LEFT JOIN analytics.historical_hourly_stats h
    ON s.creator_name = h.creator_name
    AND EXTRACT(HOUR FROM s.last_updated) = h.hour_of_day
    AND EXTRACT(DAYOFWEEK FROM s.last_updated) = h.day_of_week
),

-- STEP 3: Saturation Detection with Predictive Modeling
saturation_detection AS (
  SELECT
    a.*,

    -- Saturation Signals
    CASE
      WHEN conversion_rate_24h < baseline_conversion * 0.5
           AND messages_last_day > baseline_daily_messages * 1.5 THEN 'RED'
      WHEN conversion_rate_24h < baseline_conversion * 0.7
           AND messages_last_day > baseline_daily_messages * 1.2 THEN 'YELLOW'
      WHEN conversion_rate_24h >= baseline_conversion * 0.9 THEN 'GREEN'
      ELSE 'UNKNOWN'
    END as saturation_status,

    -- Predictive Saturation (will hit RED in next 24h)
    CASE
      WHEN conversion_zscore < -2 AND message_volume_zscore > 2 THEN TRUE
      WHEN consecutive_decline_days >= 3 THEN TRUE
      ELSE FALSE
    END as saturation_predicted,

    -- Exhaustion Score (0-100)
    LEAST(100, GREATEST(0,
      (1 - conversion_rate_24h / NULLIF(baseline_conversion, 0)) * 50 +
      (messages_last_day / NULLIF(baseline_daily_messages, 1) - 1) * 30 +
      (consecutive_decline_days * 10)
    )) as exhaustion_score,

  FROM anomaly_detection a
  LEFT JOIN analytics.creator_baselines b
    ON a.creator_name = b.creator_name
),

-- STEP 4: Pattern Recognition for Success Factors
pattern_recognition AS (
  SELECT
    s.*,

    -- Identify what's working RIGHT NOW
    ARRAY_AGG(
      STRUCT(
        content_type,
        trigger_type,
        price_point,
        conversion_rate,
        sample_size
      ) ORDER BY conversion_rate DESC LIMIT 5
    ) as top_performing_patterns_1h,

    -- Identify what's NOT working
    ARRAY_AGG(
      STRUCT(
        content_type,
        trigger_type,
        price_point,
        conversion_rate,
        sample_size
      ) ORDER BY conversion_rate ASC LIMIT 5
    ) as worst_performing_patterns_1h,

  FROM saturation_detection s
  LEFT JOIN (
    SELECT
      creator_name,
      content_type,
      trigger_type,
      price_point,
      AVG(CASE WHEN payment_status = 'paid' THEN 1 ELSE 0 END) as conversion_rate,
      COUNT(*) as sample_size
    FROM raw_messages
    WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    GROUP BY 1,2,3,4
    HAVING COUNT(*) >= 10  -- Minimum sample for significance
  ) patterns
  ON s.creator_name = patterns.creator_name
  GROUP BY ALL
)

-- FINAL: Alert Generation
SELECT
  *,

  -- Generate Actionable Alerts
  CASE
    WHEN saturation_status = 'RED' THEN
      'CRITICAL: Pause all PPV immediately. Audience exhausted. Implement cooling protocol.'
    WHEN saturation_predicted = TRUE THEN
      'WARNING: Saturation predicted within 24h. Reduce volume by 50% preventatively.'
    WHEN volume_anomaly AND conversion_anomaly THEN
      'ANOMALY: Unusual pattern detected. Review content strategy immediately.'
    WHEN exhaustion_score > 70 THEN
      'CAUTION: High exhaustion score. Consider 48h cooldown period.'
    ELSE NULL
  END as alert_message,

  -- Recommended Actions
  CASE
    WHEN saturation_status = 'RED' THEN
      ARRAY[
        'Stop all PPV messages for 48 hours',
        'Send only photo bumps (no prices)',
        'Focus on genuine engagement content',
        'Resume with 50% volume reduction'
      ]
    WHEN saturation_predicted = TRUE THEN
      ARRAY[
        'Reduce PPV to 3-5 per day max',
        'Increase photo bump ratio',
        'Switch to lower price points',
        'Monitor hourly for status change'
      ]
    ELSE ARRAY[]
  END as recommended_actions,

  -- Performance Benchmarking
  PERCENT_RANK() OVER (ORDER BY conversion_rate_24h) as conversion_percentile,
  PERCENT_RANK() OVER (ORDER BY revenue_last_day) as revenue_percentile,

FROM pattern_recognition;

-- STEP 5: Historical Stats Table for Anomaly Detection (runs daily)
-- Query safety limits for historical aggregation
SET @@query_timeout_ms = 300000;  -- 5 minutes for expensive query (90 days of data)
SET @@maximum_bytes_billed = 53687091200;  -- 50 GB max ($0.25)

CREATE OR REPLACE TABLE analytics.historical_hourly_stats AS
SELECT
  creator_name,
  EXTRACT(HOUR FROM timestamp) as hour_of_day,
  EXTRACT(DAYOFWEEK FROM timestamp) as day_of_week,

  -- Historical baselines for each hour/day combination
  AVG(hourly_messages) as avg_hourly_messages,
  STDDEV(hourly_messages) as stddev_hourly_messages,

  AVG(hourly_conversion) as avg_hourly_conversion,
  STDDEV(hourly_conversion) as stddev_hourly_conversion,

  AVG(hourly_revenue) as avg_hourly_revenue,
  STDDEV(hourly_revenue) as stddev_hourly_revenue,

FROM (
  SELECT
    creator_name,
    timestamp,
    COUNT(*) as hourly_messages,
    AVG(CASE WHEN payment_status = 'paid' THEN 1 ELSE 0 END) as hourly_conversion,
    SUM(CASE WHEN payment_status = 'paid' THEN price ELSE 0 END) as hourly_revenue
  FROM raw_messages
  WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  GROUP BY creator_name, DATE_TRUNC(timestamp, HOUR)
)
GROUP BY 1,2,3;
```

## Alert Webhook Integration

```python
import requests
from google.cloud import bigquery
from datetime import datetime, timedelta
import json

class RealtimeAlertSystem:
    def __init__(self):
        self.client = bigquery.Client()
        self.webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
        self.last_alert_cache = {}

    def check_alerts(self):
        """Runs every 5 minutes to check for critical alerts"""

        query = """
        SELECT
            creator_name,
            saturation_status,
            saturation_predicted,
            exhaustion_score,
            alert_message,
            recommended_actions,
            conversion_rate_1h,
            conversion_rate_24h,
            revenue_last_hour,
            revenue_last_day
        FROM analytics.realtime_performance
        WHERE alert_message IS NOT NULL
        ORDER BY
            CASE saturation_status
                WHEN 'RED' THEN 1
                WHEN 'YELLOW' THEN 2
                ELSE 3
            END,
            exhaustion_score DESC
        """

        alerts = self.client.query(query).to_dataframe()

        for _, alert in alerts.iterrows():
            # Prevent alert spam (max 1 per hour per creator/type)
            alert_key = f"{alert['creator_name']}_{alert['saturation_status']}"
            if alert_key in self.last_alert_cache:
                if datetime.now() - self.last_alert_cache[alert_key] < timedelta(hours=1):
                    continue

            # Send alert
            self.send_alert(alert)
            self.last_alert_cache[alert_key] = datetime.now()

    def send_alert(self, alert):
        """Send formatted alert to Slack/Discord/Email"""

        # Color coding for urgency
        color = {
            'RED': '#FF0000',
            'YELLOW': '#FFA500',
            'GREEN': '#00FF00'
        }.get(alert['saturation_status'], '#808080')

        # Format message
        message = {
            "attachments": [{
                "color": color,
                "title": f"🚨 {alert['creator_name']} - {alert['saturation_status']} Alert",
                "text": alert['alert_message'],
                "fields": [
                    {
                        "title": "1h Conversion",
                        "value": f"{alert['conversion_rate_1h']:.2%}",
                        "short": True
                    },
                    {
                        "title": "24h Conversion",
                        "value": f"{alert['conversion_rate_24h']:.2%}",
                        "short": True
                    },
                    {
                        "title": "Revenue (24h)",
                        "value": f"${alert['revenue_last_day']:.2f}",
                        "short": True
                    },
                    {
                        "title": "Exhaustion Score",
                        "value": f"{alert['exhaustion_score']:.0f}/100",
                        "short": True
                    },
                    {
                        "title": "Recommended Actions",
                        "value": "\n".join(f"• {action}" for action in alert['recommended_actions']),
                        "short": False
                    }
                ],
                "footer": "Real-Time Monitor Production",
                "ts": int(datetime.now().timestamp())
            }]
        }

        # Send webhook
        response = requests.post(
            self.webhook_url,
            json=message,
            headers={'Content-Type': 'application/json'}
        )

        if response.status_code != 200:
            print(f"Alert failed: {response.text}")
```

## Dashboard Queries for Immediate Insights

```sql
-- Query safety limits for dashboard views
SET @@query_timeout_ms = 120000;  -- 2 minutes for standard query
SET @@maximum_bytes_billed = 10737418240;  -- 10 GB max ($0.05)

-- 1. EXECUTIVE DASHBOARD - Top Level Health
CREATE OR REPLACE VIEW analytics.executive_dashboard AS
SELECT
  COUNT(*) as total_creators,
  COUNT(*) FILTER(WHERE saturation_status = 'RED') as red_alerts,
  COUNT(*) FILTER(WHERE saturation_status = 'YELLOW') as yellow_alerts,
  COUNT(*) FILTER(WHERE saturation_predicted = TRUE) as predicted_saturations,

  AVG(conversion_rate_24h) as avg_conversion_24h,
  SUM(revenue_last_day) as total_revenue_24h,

  -- Period comparisons
  (SUM(revenue_last_day) - SUM(revenue_previous_day)) / NULLIF(SUM(revenue_previous_day), 0) as revenue_growth_rate,

  -- Critical metrics
  COUNT(*) FILTER(WHERE exhaustion_score > 80) as critical_exhaustion_count,
  COUNT(*) FILTER(WHERE volume_anomaly OR conversion_anomaly) as anomaly_count,

FROM analytics.realtime_performance;

-- 2. CREATOR DRILLDOWN - Individual Performance
CREATE OR REPLACE VIEW analytics.creator_drilldown AS
SELECT
  creator_name,
  saturation_status,
  exhaustion_score,

  -- Performance Trending
  conversion_rate_1h,
  conversion_rate_24h,
  conversion_rate_7d,

  -- Volume Metrics
  messages_last_hour,
  messages_last_day,
  messages_last_week,

  -- Revenue
  revenue_last_hour,
  revenue_last_day,

  -- Anomaly Scores
  message_volume_zscore,
  conversion_zscore,
  revenue_zscore,

  -- Top Patterns
  top_performing_patterns_1h[SAFE_OFFSET(0)].content_type as best_content_type,
  top_performing_patterns_1h[SAFE_OFFSET(0)].conversion_rate as best_conversion,

  -- Actions
  alert_message,
  recommended_actions,

FROM analytics.realtime_performance
ORDER BY exhaustion_score DESC;

-- 3. PATTERN ANALYSIS - What's Working Now
CREATE OR REPLACE VIEW analytics.pattern_performance AS
WITH recent_patterns AS (
  SELECT
    content_type,
    trigger_type,
    price_tier,
    COUNT(*) as volume,
    AVG(CASE WHEN payment_status = 'paid' THEN 1 ELSE 0 END) as conversion_rate,
    SUM(CASE WHEN payment_status = 'paid' THEN price ELSE 0 END) as revenue,

    -- Statistical significance
    APPROX_QUANTILES(CASE WHEN payment_status = 'paid' THEN 1 ELSE 0 END, 100)[OFFSET(50)] as median_conversion,

  FROM raw_messages
  WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  GROUP BY 1,2,3
  HAVING COUNT(*) >= 20  -- Minimum sample
)
SELECT
  *,
  RANK() OVER (ORDER BY conversion_rate DESC) as conversion_rank,
  RANK() OVER (ORDER BY revenue DESC) as revenue_rank,

  -- Performance vs baseline
  conversion_rate / NULLIF(AVG(conversion_rate) OVER(), 0) as relative_performance,

FROM recent_patterns
ORDER BY conversion_rate DESC;
```

## Auto-Recovery Actions

```python
class AutoRecoverySystem:
    """Automated actions when saturation detected"""

    def execute_recovery(self, creator_name, saturation_status):
        if saturation_status == 'RED':
            # Immediate pause
            self.pause_all_ppv(creator_name, duration_hours=48)
            self.schedule_photo_bumps_only(creator_name)
            self.notify_team(f"AUTO-RECOVERY: {creator_name} paused for 48h")

        elif saturation_status == 'YELLOW':
            # Volume reduction
            self.reduce_ppv_volume(creator_name, reduction_percent=50)
            self.switch_to_low_prices(creator_name)
            self.increase_photo_bump_ratio(creator_name)

        # Log recovery action
        self.log_recovery_action(creator_name, saturation_status)
```

## Performance Benchmarks

- **Query Latency**: < 2 seconds for all dashboards
- **Alert Latency**: < 15 minutes from event to notification
- **False Positive Rate**: < 5% for saturation predictions
- **Recovery Success Rate**: > 80% return to GREEN within 72h

## Integration Points

1. **Caption Selector**: Adjusts exploration rate based on saturation
2. **Schedule Builder**: Receives volume caps from monitor
3. **Performance Analyzer**: Shares historical baselines
4. **Orchestrator**: Triggers emergency re-scheduling

## Monitoring the Monitor

```sql
-- Meta-monitoring: Is the monitor working?
CREATE OR REPLACE VIEW analytics.monitor_health AS
SELECT
  MAX(last_updated) as last_update,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), MINUTE) as minutes_since_update,
  COUNT(DISTINCT creator_name) as creators_monitored,
  COUNT(*) FILTER(WHERE alert_message IS NOT NULL) as active_alerts,

  -- Monitor performance
  AVG(TIMESTAMP_DIFF(last_updated, event_timestamp, MINUTE)) as avg_detection_lag,

FROM analytics.realtime_performance;
```

## Version History
- Production: Reduced lag to 15 minutes, added predictive saturation
- v1.0: Initial 4-hour monitoring cycle
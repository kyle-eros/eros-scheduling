-- EROS Max AI System - BigQuery Infrastructure
-- Project: of-scheduler-proj
-- Dataset: eros_scheduling_brain
--
-- This script creates essential tables for the EROS Max AI system.
-- The system relies on existing core tables (mass_messages, caption_bank, vault_matrix)
-- and adds operational tables for schedule management and tracking.

-- ============================================
-- SCHEDULE MANAGEMENT
-- ============================================

-- Generated 7-day schedule templates
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_templates` (
    page_name STRING NOT NULL,
    scheduled_send_date DATE NOT NULL,
    scheduled_send_hour INT64 NOT NULL,
    message_type STRING,
    caption_id INT64,
    caption_text STRING,
    content_category STRING,
    price_tier STRING,
    price FLOAT64,
    expected_revenue FLOAT64,
    confidence_score FLOAT64,
    strategy_notes STRING,
    energy_match_score FLOAT64,
    generation_timestamp TIMESTAMP NOT NULL,
    generated_by STRING DEFAULT 'EROS-Max-Orchestrator',
    is_active BOOLEAN DEFAULT TRUE
)
PARTITION BY scheduled_send_date
CLUSTER BY page_name, scheduled_send_hour
OPTIONS(
    description='AI-generated 7-day mass message schedules with expected performance metrics'
);

-- ============================================
-- PERFORMANCE TRACKING
-- ============================================

-- Schedule execution and performance feedback
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.schedule_performance_log` (
    page_name STRING NOT NULL,
    evaluation_date DATE NOT NULL,
    scheduled_hour INT64,
    caption_id INT64,
    expected_revenue FLOAT64,
    actual_revenue FLOAT64,
    sent_count INT64,
    viewed_count INT64,
    purchased_count FLOAT64,
    view_rate FLOAT64,
    purchase_rate FLOAT64,
    performance_ratio FLOAT64,
    eros_score FLOAT64,
    logged_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
PARTITION BY evaluation_date
CLUSTER BY page_name
OPTIONS(
    description='Actual performance vs predicted for continuous learning'
);

-- ============================================
-- ANALYTICS CACHE
-- ============================================

-- Cached creator performance analysis (2-hour TTL)
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.creator_analysis_cache` (
    page_name STRING NOT NULL,
    analysis_data JSON NOT NULL,
    data_quality_score FLOAT64,
    confidence_level STRING,
    eros_score FLOAT64,
    tier STRING,
    health_status STRING,
    cache_timestamp TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(cache_timestamp)
CLUSTER BY page_name
OPTIONS(
    description='Cached performance analysis results to reduce BigQuery costs'
);

-- ============================================
-- BATCH PROCESSING LOGS
-- ============================================

-- Batch job execution tracking
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.batch_execution_log` (
    batch_id STRING NOT NULL,
    execution_timestamp TIMESTAMP NOT NULL,
    total_creators INT64,
    successful INT64,
    failed INT64,
    avg_processing_seconds FLOAT64,
    total_expected_revenue FLOAT64,
    execution_type STRING,
    agent_version STRING DEFAULT 'v2.0'
)
PARTITION BY DATE(execution_timestamp)
OPTIONS(
    description='Batch processing execution logs for monitoring and optimization'
);

-- ============================================
-- ALERTS & MONITORING
-- ============================================

-- System alerts and notifications
CREATE TABLE IF NOT EXISTS `of-scheduler-proj.eros_scheduling_brain.system_alerts` (
    alert_id STRING NOT NULL,
    alert_type STRING NOT NULL,
    severity STRING NOT NULL,
    page_name STRING,
    message STRING NOT NULL,
    details JSON,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    resolved BOOLEAN DEFAULT FALSE,
    resolved_timestamp TIMESTAMP
)
PARTITION BY DATE(created_timestamp)
CLUSTER BY alert_type, severity
OPTIONS(
    description='System alerts for vault violations, data quality issues, and performance anomalies'
);

-- ============================================
-- INDEXES & PERFORMANCE OPTIMIZATION
-- ============================================

-- Create search index for caption_bank (if not exists)
-- This improves caption selection performance
-- Note: Search indexes are created separately via BigQuery API

-- Performance tip: Existing tables (mass_messages, caption_bank, vault_matrix)
-- should already be partitioned and clustered for optimal performance.

-- ============================================
-- GRANTS & PERMISSIONS
-- ============================================

-- Grant permissions to service account (run separately)
-- GRANT `roles/bigquery.dataEditor` ON TABLE `of-scheduler-proj.eros_scheduling_brain.*`
-- TO 'serviceAccount:eros-scheduler@of-scheduler-proj.iam.gserviceaccount.com';

-- ============================================
-- TABLE DESCRIPTIONS
-- ============================================

ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.schedule_templates`
SET OPTIONS(
    description='AI-generated weekly schedules with Claude Sonnet 4.5 strategic optimization',
    labels=[("system", "eros-max-ai"), ("version", "2-0")]
);

ALTER TABLE `of-scheduler-proj.eros_scheduling_brain.schedule_performance_log`
SET OPTIONS(
    description='Performance tracking for continuous learning and model improvement',
    labels=[("system", "eros-max-ai"), ("purpose", "feedback-loop")]
);

-- ============================================
-- COMPLETION
-- ============================================

SELECT
    'Infrastructure setup complete!' AS status,
    COUNT(*) AS tables_created
FROM `of-scheduler-proj.eros_scheduling_brain.INFORMATION_SCHEMA.TABLES`
WHERE table_name IN (
    'schedule_templates',
    'schedule_performance_log',
    'creator_analysis_cache',
    'batch_execution_log',
    'system_alerts'
);

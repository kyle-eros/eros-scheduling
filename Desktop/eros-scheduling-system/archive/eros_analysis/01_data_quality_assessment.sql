-- =====================================================
-- EROS SCHEDULING BRAIN - DATA QUALITY ASSESSMENT
-- =====================================================
-- Purpose: Comprehensive data quality checks across all tables
-- Author: Data Analyst Agent
-- Date: 2025-10-31

-- =====================================================
-- 1. DATA COMPLETENESS PROFILE
-- =====================================================

-- Caption Bank Completeness
WITH caption_completeness AS (
  SELECT
    COUNT(*) as total_captions,
    COUNTIF(caption_text IS NULL) as null_caption_text,
    COUNTIF(content_category IS NULL) as null_content_category,
    COUNTIF(price_tier IS NULL) as null_price_tier,
    COUNTIF(conversion_score IS NULL) as null_conversion_score,
    COUNTIF(revenue_score IS NULL) as null_revenue_score,
    COUNTIF(efficiency_score IS NULL) as null_efficiency_score,
    COUNTIF(overall_performance_score IS NULL) as null_overall_score,
    COUNTIF(last_used IS NULL) as null_last_used,
    COUNTIF(total_sends = 0) as zero_sends,
    COUNTIF(total_reach = 0) as zero_reach,
    -- Check for business logic violations
    COUNTIF(conversion_score < 0 OR conversion_score > 1) as invalid_conversion_score,
    COUNTIF(avg_conversion_rate < 0 OR avg_conversion_rate > 1) as invalid_conversion_rate,
    COUNTIF(total_conversions > total_reach) as conversions_exceed_reach,
    COUNTIF(total_sends < pages_used_count) as sends_less_than_pages,
    COUNTIF(max_revenue < min_revenue) as max_less_than_min_revenue,
    COUNTIF(avg_price < min_price OR avg_price > max_price) as avg_price_out_of_bounds
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`
)
SELECT
  *,
  ROUND(100.0 * null_caption_text / NULLIF(total_captions, 0), 2) as pct_null_caption_text,
  ROUND(100.0 * null_content_category / NULLIF(total_captions, 0), 2) as pct_null_content_category,
  ROUND(100.0 * null_price_tier / NULLIF(total_captions, 0), 2) as pct_null_price_tier,
  ROUND(100.0 * zero_sends / NULLIF(total_captions, 0), 2) as pct_zero_sends,
  ROUND(100.0 * (invalid_conversion_score + invalid_conversion_rate + conversions_exceed_reach +
                 sends_less_than_pages + max_less_than_min_revenue + avg_price_out_of_bounds)
        / NULLIF(total_captions, 0), 2) as pct_data_anomalies
FROM caption_completeness;

-- =====================================================
-- 2. CAPTION PERFORMANCE TRACKING QUALITY
-- =====================================================

WITH performance_quality AS (
  SELECT
    COUNT(*) as total_records,
    COUNTIF(caption_hash IS NULL OR caption_text IS NULL) as missing_required_fields,
    COUNTIF(lifetime_conversion IS NULL) as null_lifetime_conversion,
    COUNTIF(total_uses IS NULL OR total_uses = 0) as null_or_zero_uses,
    COUNTIF(last_used_date IS NULL) as null_last_used_date,
    COUNTIF(performance_tier IS NULL) as null_performance_tier,
    -- Data quality checks
    COUNTIF(lifetime_conversion < 0 OR lifetime_conversion > 1) as invalid_conversion_rates,
    COUNTIF(recent_7d_conversion < 0 OR recent_7d_conversion > 1) as invalid_7d_conversion,
    COUNTIF(recent_30d_conversion < 0 OR recent_30d_conversion > 1) as invalid_30d_conversion,
    COUNTIF(conversion_variance < 0) as negative_variance,
    COUNTIF(unique_pages_used > total_uses) as pages_exceed_uses,
    COUNTIF(last_used_date > CURRENT_DATE()) as future_dates,
    COUNTIF(fatigue_score < 0 OR fatigue_score > 1) as invalid_fatigue_score,
    -- Check for stale data
    COUNTIF(DATE_DIFF(CURRENT_DATE(), last_used_date, DAY) > 90) as stale_over_90_days,
    COUNTIF(is_active = TRUE AND DATE_DIFF(CURRENT_DATE(), last_used_date, DAY) > 180) as active_but_stale
  FROM `of-scheduler-proj.eros_scheduling_brain.caption_performance_tracking`
)
SELECT
  *,
  ROUND(100.0 * missing_required_fields / NULLIF(total_records, 0), 2) as pct_missing_required,
  ROUND(100.0 * (invalid_conversion_rates + invalid_7d_conversion + invalid_30d_conversion +
                 negative_variance + pages_exceed_uses + future_dates + invalid_fatigue_score)
        / NULLIF(total_records, 0), 2) as pct_invalid_data,
  ROUND(100.0 * stale_over_90_days / NULLIF(total_records, 0), 2) as pct_stale_data
FROM performance_quality;

-- =====================================================
-- 3. SCHEDULE RECOMMENDATIONS DATA QUALITY
-- =====================================================

WITH rec_quality AS (
  SELECT
    COUNT(*) as total_recommendations,
    COUNTIF(recommendation_id IS NULL) as null_rec_id,
    COUNTIF(page_name IS NULL) as null_page_name,
    COUNTIF(schedule_id IS NULL) as null_schedule_id,
    COUNTIF(recommendation_data IS NULL) as null_rec_data,
    COUNTIF(confidence_score IS NULL) as null_confidence,
    COUNTIF(uniqueness_score IS NULL) as null_uniqueness,
    COUNTIF(status IS NULL) as null_status,
    -- Quality checks
    COUNTIF(confidence_score < 0 OR confidence_score > 1) as invalid_confidence,
    COUNTIF(uniqueness_score < 0 OR uniqueness_score > 1) as invalid_uniqueness,
    COUNTIF(caption_quality_score < 0 OR caption_quality_score > 1) as invalid_quality_score,
    COUNTIF(imported_at < generated_at) as imported_before_generated,
    COUNTIF(DATE_DIFF(CURRENT_DATE(), created_date, DAY) > 30 AND status = 'pending') as old_pending_recs,
    -- Status distribution
    COUNTIF(status = 'pending') as status_pending,
    COUNTIF(status = 'imported') as status_imported,
    COUNTIF(status = 'rejected') as status_rejected,
    COUNTIF(status NOT IN ('pending', 'imported', 'rejected')) as status_unknown
  FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
)
SELECT
  *,
  ROUND(100.0 * status_imported / NULLIF(total_recommendations, 0), 2) as import_rate,
  ROUND(100.0 * status_rejected / NULLIF(total_recommendations, 0), 2) as rejection_rate,
  ROUND(100.0 * old_pending_recs / NULLIF(status_pending, 0), 2) as pct_stale_pending
FROM rec_quality;

-- =====================================================
-- 4. CREATOR DATA QUALITY
-- =====================================================

-- Active Creators Check
SELECT
  COUNT(DISTINCT page_name) as total_active_creators,
  COUNT(*) as total_records,
  COUNTIF(page_name IS NULL OR page_name = '') as null_or_empty_page_names
FROM `of-scheduler-proj.eros_scheduling_brain.active_creators`;

-- Creator Content Inventory Quality
WITH inventory_quality AS (
  SELECT
    COUNT(*) as total_inventory_records,
    COUNT(DISTINCT page_name) as unique_creators,
    COUNTIF(page_name IS NULL) as null_page_name,
    COUNTIF(total_content_pieces IS NULL OR total_content_pieces = 0) as null_or_zero_content,
    COUNTIF(inventory_quality_score IS NULL) as null_quality_score,
    COUNTIF(inventory_quality_score < 0 OR inventory_quality_score > 1) as invalid_quality_score,
    COUNTIF(ARRAY_LENGTH(available_categories) = 0) as no_categories,
    COUNTIF(vault_audit_date > inventory_date) as audit_after_inventory,
    COUNTIF(DATE_DIFF(CURRENT_DATE(), inventory_date, DAY) > 7) as inventory_over_7_days,
    COUNTIF(DATE_DIFF(CURRENT_DATE(), vault_audit_date, DAY) > 30) as audit_over_30_days,
    -- Get latest inventory per creator
    COUNT(DISTINCT CONCAT(page_name, '-', inventory_date)) as unique_creator_dates
  FROM `of-scheduler-proj.eros_scheduling_brain.creator_content_inventory`
)
SELECT
  *,
  ROUND(100.0 * inventory_over_7_days / NULLIF(total_inventory_records, 0), 2) as pct_stale_inventory,
  ROUND(100.0 * audit_over_30_days / NULLIF(total_inventory_records, 0), 2) as pct_stale_audits
FROM inventory_quality;

-- =====================================================
-- 5. DUPLICATE DETECTION
-- =====================================================

-- Check for duplicate captions in caption_bank
SELECT
  'caption_bank_duplicates' as check_name,
  COUNT(*) - COUNT(DISTINCT caption_id) as duplicate_ids,
  COUNT(*) - COUNT(DISTINCT caption_text) as duplicate_texts,
  COUNT(*) - COUNT(DISTINCT caption_key) as duplicate_keys
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`

UNION ALL

-- Check for duplicate performance tracking entries
SELECT
  'performance_tracking_duplicates' as check_name,
  COUNT(*) - COUNT(DISTINCT caption_hash) as duplicate_hashes,
  COUNT(*) - COUNT(DISTINCT caption_text) as duplicate_texts,
  0 as duplicate_keys
FROM `of-scheduler-proj.eros_scheduling_brain.caption_performance_tracking`

UNION ALL

-- Check for duplicate recommendations
SELECT
  'schedule_recommendations_duplicates' as check_name,
  COUNT(*) - COUNT(DISTINCT recommendation_id) as duplicate_ids,
  COUNT(*) - COUNT(DISTINCT CONCAT(page_name, schedule_id, CAST(generated_at AS STRING))) as duplicate_combos,
  0 as duplicate_keys
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`;

-- =====================================================
-- 6. REFERENTIAL INTEGRITY CHECKS
-- =====================================================

-- Captions without performance tracking
SELECT
  COUNT(DISTINCT cb.caption_id) as captions_in_bank,
  COUNT(DISTINCT cpt.caption_hash) as captions_in_tracking,
  COUNT(DISTINCT cb.caption_id) - COUNT(DISTINCT cpt.caption_hash) as captions_without_tracking
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb
LEFT JOIN `of-scheduler-proj.eros_scheduling_brain.caption_performance_tracking` cpt
  ON cb.caption_key = cpt.caption_hash;

-- Recommendations for inactive creators
WITH inactive_creators AS (
  SELECT DISTINCT page_name
  FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
  WHERE page_name NOT IN (
    SELECT page_name
    FROM `of-scheduler-proj.eros_scheduling_brain.active_creators`
    WHERE page_name IS NOT NULL
  )
)
SELECT
  COUNT(*) as recommendations_for_inactive_creators,
  COUNT(DISTINCT page_name) as unique_inactive_creators
FROM inactive_creators;

-- =====================================================
-- 7. DATA FRESHNESS CHECK
-- =====================================================

SELECT
  'caption_bank' as table_name,
  MAX(updated_at) as latest_update,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(updated_at), HOUR) as hours_since_update,
  MAX(last_used) as latest_caption_use,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(last_used), HOUR) as hours_since_last_use
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank`

UNION ALL

SELECT
  'caption_performance_tracking' as table_name,
  MAX(last_updated) as latest_update,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(last_updated), HOUR) as hours_since_update,
  MAX(TIMESTAMP(last_used_date)) as latest_caption_use,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(TIMESTAMP(last_used_date)), HOUR) as hours_since_last_use
FROM `of-scheduler-proj.eros_scheduling_brain.caption_performance_tracking`

UNION ALL

SELECT
  'schedule_recommendations' as table_name,
  MAX(updated_at) as latest_update,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(updated_at), HOUR) as hours_since_update,
  MAX(generated_at) as latest_caption_use,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(generated_at), HOUR) as hours_since_last_use
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`

UNION ALL

SELECT
  'creator_content_inventory' as table_name,
  MAX(updated_at) as latest_update,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(updated_at), HOUR) as hours_since_update,
  MAX(TIMESTAMP(inventory_date)) as latest_caption_use,
  DATE_DIFF(CURRENT_TIMESTAMP(), MAX(TIMESTAMP(inventory_date)), HOUR) as hours_since_last_use
FROM `of-scheduler-proj.eros_scheduling_brain.creator_content_inventory`;

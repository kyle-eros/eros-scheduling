# 📈 BigQuery Audit Report
## Dataset: `of-scheduler-proj.eros_scheduling_brain`
**Report Generated**: 2025-10-31 14:05:08 UTC

---

## 🎯 Executive Summary

### Overview
- **Total Database Objects**: 32
  - 📊 Tables: 18
  - 👁️ Views: 14
  - 🤖 ML Models: 0
- **Total Rows Across All Tables**: 119,452
- **Total Storage Used**: 41.17 MB (0.04 GB)
- **Average Table Size**: 2.29 MB
- **Average Rows per Table**: 6,636

### 📊 Data Distribution
**Tables by Size Category**:
  - Tiny: 15 tables
  - Small: 3 tables

### 📅 Data Freshness
**Last Modified**:
  - This: 7 tables
  - Today: 5 tables
  - Yesterday: 6 tables

### 🏆 Top Tables by Size
|   Rank | Table                        | Rows   | Size     | Category   |
|--------|------------------------------|--------|----------|------------|
|      1 | `caption_bank`               | 44,651 | 19.34 MB | 📁 Small    |
|      2 | `mass_messages`              | 63,411 | 15.45 MB | 📁 Small    |
|      3 | `caption_bank_staging`       | 10,991 | 6.29 MB  | 📁 Small    |
|      4 | `active_caption_assignments` | 153    | 0.03 MB  | 📄 Tiny     |
|      5 | `schedule_recommendations`   | 4      | 0.03 MB  | 📄 Tiny     |

### 📊 Top Tables by Row Count
|   Rank | Table                        | Rows   | Size     |
|--------|------------------------------|--------|----------|
|      1 | `mass_messages`              | 63,411 | 15.45 MB |
|      2 | `caption_bank`               | 44,651 | 19.34 MB |
|      3 | `caption_bank_staging`       | 10,991 | 6.29 MB  |
|      4 | `active_caption_assignments` | 153    | 0.03 MB  |
|      5 | `mass_messages_stage`        | 132    | 0.02 MB  |

### 🔗 Potential Table Relationships

*Detected potential foreign key relationships based on column naming patterns:*
  - `active_caption_assignments`.`caption_id` → `caption_bandit_stats`
  - `active_caption_assignments`.`caption_id` → `caption_bank`
  - `active_caption_assignments`.`caption_id` → `caption_bank_staging`
  - `active_caption_assignments`.`caption_id` → `caption_filter_audit_log`
  - `active_caption_assignments`.`caption_id` → `caption_performance_tracking`
  - `active_caption_assignments`.`caption_id` → `creator_caption_restrictions`
  - `active_caption_assignments`.`schedule_id` → `schedule_recommendations`
  - `caption_bandit_stats`.`caption_id` → `active_caption_assignments`
  - `caption_bandit_stats`.`caption_id` → `caption_bank`
  - `caption_bandit_stats`.`caption_id` → `caption_bank_staging`

---

## 📊 Tables and Views in `of-scheduler-proj.eros_scheduling_brain` (32 total)


### 👁️ VIEW: `active_assignments_7day`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.active_assignments_7day`
- **Created**: 2025-10-28 13:10:20 UTC
- **Last Modified**: 2025-10-28 13:10:20 UTC 📅 This Week
- **View Query**:
```sql
SELECT
  *
FROM `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments`
WHERE is_active = true
  AND scheduled_send_date >= CURRENT_DATE('America/Los_Angeles')
  AND scheduled_send_date <= DATE_ADD(CURRENT_DATE('America/Los_Angeles'), INTERVAL 7 DAY)
```
- **Schema** (10 columns):
| Name                | Type      | Mode     | Description   |
|---------------------|-----------|----------|---------------|
| page_name           | STRING    | NULLABLE |               |
| caption_id          | INTEGER   | NULLABLE |               |
| caption_text        | STRING    | NULLABLE |               |
| assigned_date       | DATE      | NULLABLE |               |
| scheduled_send_date | DATE      | NULLABLE |               |
| scheduled_send_hour | INTEGER   | NULLABLE |               |
| price_tier          | STRING    | NULLABLE |               |
| is_active           | BOOLEAN   | NULLABLE |               |
| assigned_at         | TIMESTAMP | NULLABLE |               |
| assignment_key      | STRING    | NULLABLE |               |

---

### 📊 TABLE: `active_caption_assignments`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.active_caption_assignments`
- **Created**: 2025-10-27 04:22:20 UTC
- **Last Modified**: 2025-10-29 09:55:39 UTC 📅 This Week
- **Description**: Tracks active caption assignments to prevent agency-wide overlaps
- **Total Rows**: 153 | **Size**: 0.03 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (98.8%)
      ███████████████████░ 98.8%
    - **Field Completeness Analysis**:
      - `page_name`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `caption_id`: 🟢 Excellent (100.0% complete, 90 unique values)
      - `caption_text`: 🟢 Excellent (100.0% complete, 118 unique values)
      - `assigned_date`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `scheduled_send_date`: 🟢 Excellent (100.0% complete, 9 unique values)
  - **Sample Data** (showing 5 of 153 rows):
    ```
page_name              caption_id  caption_text                                        assigned_date    scheduled_send_date      scheduled_send_hour  price_tier    is_active
-----------  --------------------  --------------------------------------------------  ---------------  ---------------------  ---------------------  ------------  -----------
del          -2194714712821639177  🎊 WINNER’S REWARD 🎊 I saved $450 worth of my rawes  2025-10-28       2025-10-28                                 1  budget        True
del          -2941286856032768693  NEW CONTENT! 🔥 I know you've been waiting for this  2025-10-28       2025-10-29                                 8  budget        True
del          -5940440286943999537  To be completely honest I’ve been thinking about m  2025-10-28       2025-10-31                                 9  budget        True
del          -1224654913747942074  OMG :) My pussy has never been so sore today 💦 my   2025-10-28       2025-10-28                                 9  mid           True
del          -2198800343255082568  the nudes I would send you if you were my BF 💦      2025-10-28       2025-10-28                                 5  mid           True
    ```
- **Schema** (11 columns):
| Name                | Type      | Mode     | Description                                                 |
|---------------------|-----------|----------|-------------------------------------------------------------|
| page_name           | STRING    | REQUIRED |                                                             |
| caption_id          | INTEGER   | REQUIRED |                                                             |
| caption_text        | STRING    | REQUIRED |                                                             |
| assigned_date       | DATE      | REQUIRED |                                                             |
| scheduled_send_date | DATE      | NULLABLE |                                                             |
| scheduled_send_hour | INTEGER   | NULLABLE |                                                             |
| price_tier          | STRING    | NULLABLE |                                                             |
| is_active           | BOOLEAN   | NULLABLE |                                                             |
| assigned_at         | TIMESTAMP | NULLABLE |                                                             |
| assignment_key      | STRING    | NULLABLE | Hash of (page_name, caption_id, date, hour) for idempotency |
| schedule_id         | STRING    | NULLABLE |                                                             |

---

### 👁️ VIEW: `active_creator_caption_restrictions_v`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.active_creator_caption_restrictions_v`
- **Created**: 2025-10-30 06:59:28 UTC
- **Last Modified**: 2025-10-30 06:59:28 UTC 🆕 Yesterday
- **View Query**:
```sql
SELECT
  -- Creator identification
  page_name,

  -- Scope control
  applies_to_scope,                              -- 'PPV_ONLY' | 'BUMP_ONLY' | 'ALL'

  -- Pool size guardrails with defaults
  COALESCE(min_ppv_pool, 200) AS min_ppv_pool,   -- Default: 200 captions for PPV pool
  COALESCE(min_bump_pool, 50) AS min_bump_pool,  -- Default: 50 captions for BUMP pool

  -- Filter definitions (arrays may be NULL if no restrictions in that category)
  hard_patterns,                                 -- ARRAY<STRING> of RE2 patterns for HARD exclusion
  soft_patterns,                                 -- ARRAY<STRING> of RE2 patterns for SOFT penalty
  restricted_categories,                         -- ARRAY<STRING> of content categories to exclude
  restricted_price_tiers                         -- ARRAY<STRING> of price tiers to exclude

FROM `of-scheduler-proj.eros_scheduling_brain.creator_caption_restrictions`

-- Only return active restrictions (master switch)
WHERE is_active = TRUE
```
- **Schema** (8 columns):
| Name                   | Type    | Mode     | Description   |
|------------------------|---------|----------|---------------|
| page_name              | STRING  | NULLABLE |               |
| applies_to_scope       | STRING  | NULLABLE |               |
| min_ppv_pool           | INTEGER | NULLABLE |               |
| min_bump_pool          | INTEGER | NULLABLE |               |
| hard_patterns          | STRING  | REPEATED |               |
| soft_patterns          | STRING  | REPEATED |               |
| restricted_categories  | STRING  | REPEATED |               |
| restricted_price_tiers | STRING  | REPEATED |               |

---

### 📊 TABLE: `active_creators`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.active_creators`
- **Created**: 2025-10-18 00:23:25 UTC
- **Last Modified**: 2025-10-30 10:14:56 UTC 🆕 Yesterday
- **Total Rows**: 38 | **Size**: 0.00 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (100.0%)
      ████████████████████ 100.0%
    - **Field Completeness Analysis**:
      - `page_name`: 🟢 Excellent (100.0% complete, 38 unique values)
  - **Sample Data** (showing 5 of 38 rows):
    ```
page_name
---------------
mayahill
jadebri
del
dianagrace
taylorwild_paid
    ```
- **Schema** (1 columns):
| Name      | Type   | Mode     | Description   |
|-----------|--------|----------|---------------|
| page_name | STRING | NULLABLE |               |

---

### 📊 TABLE: `audit_log`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.audit_log`
- **Created**: 2025-10-31 17:53:56 UTC
- **Last Modified**: 2025-10-31 17:53:56 UTC ✨ Today
- **Description**: Audit log for tracking system actions and caption assignment operations
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (8 columns):
| Name          | Type      | Mode     | Description   |
|---------------|-----------|----------|---------------|
| action        | STRING    | REQUIRED |               |
| entity_type   | STRING    | REQUIRED |               |
| entity_id     | STRING    | REQUIRED |               |
| page_name     | STRING    | NULLABLE |               |
| details       | STRING    | NULLABLE |               |
| timestamp     | TIMESTAMP | REQUIRED |               |
| user_agent    | STRING    | NULLABLE |               |
| error_message | STRING    | NULLABLE |               |

---

### 👁️ VIEW: `available_captions`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.available_captions`
- **Created**: 2025-10-28 13:10:19 UTC
- **Last Modified**: 2025-10-28 13:10:19 UTC 📅 This Week
- **View Query**:
```sql
SELECT
  c.*,
  `of-scheduler-proj.eros_scheduling_brain`.caption_key(c.caption_text) AS caption_key_norm
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` c
WHERE c.usage_status IN ('available', 'moderate_recency')
  AND c.overall_performance_score > 0
```
- **Schema** (41 columns):
| Name                      | Type      | Mode     | Description   |
|---------------------------|-----------|----------|---------------|
| caption_id                | INTEGER   | NULLABLE |               |
| caption_text              | STRING    | NULLABLE |               |
| content_category          | STRING    | NULLABLE |               |
| price_tier                | STRING    | NULLABLE |               |
| has_urgency               | BOOLEAN   | NULLABLE |               |
| conversion_score          | FLOAT     | NULLABLE |               |
| revenue_score             | FLOAT     | NULLABLE |               |
| efficiency_score          | FLOAT     | NULLABLE |               |
| overall_performance_score | FLOAT     | NULLABLE |               |
| avg_revenue               | FLOAT     | NULLABLE |               |
| max_revenue               | FLOAT     | NULLABLE |               |
| min_revenue               | FLOAT     | NULLABLE |               |
| avg_conversion_rate       | FLOAT     | NULLABLE |               |
| best_conversion_rate      | FLOAT     | NULLABLE |               |
| avg_revenue_per_recipient | FLOAT     | NULLABLE |               |
| avg_purchase_rate         | FLOAT     | NULLABLE |               |
| total_sends               | INTEGER   | NULLABLE |               |
| pages_used_count          | INTEGER   | NULLABLE |               |
| sample_pages_used         | STRING    | REPEATED |               |
| total_reach               | INTEGER   | NULLABLE |               |
| total_conversions         | INTEGER   | NULLABLE |               |
| lifetime_revenue          | FLOAT     | NULLABLE |               |
| caption_length            | INTEGER   | NULLABLE |               |
| question_count            | FLOAT     | NULLABLE |               |
| exclamation_count         | FLOAT     | NULLABLE |               |
| emoji_count               | FLOAT     | NULLABLE |               |
| successful_days           | STRING    | REPEATED |               |
| successful_hours          | INTEGER   | REPEATED |               |
| min_price                 | FLOAT     | NULLABLE |               |
| max_price                 | FLOAT     | NULLABLE |               |
| avg_price                 | FLOAT     | NULLABLE |               |
| first_used                | TIMESTAMP | NULLABLE |               |
| last_used                 | TIMESTAMP | NULLABLE |               |
| days_since_last_use       | INTEGER   | NULLABLE |               |
| usage_status              | STRING    | NULLABLE |               |
| validation_level          | STRING    | NULLABLE |               |
| created_at                | TIMESTAMP | NULLABLE |               |
| updated_at                | TIMESTAMP | NULLABLE |               |
| is_long_form              | BOOLEAN   | NULLABLE |               |
| caption_key               | STRING    | NULLABLE |               |
| caption_key_norm          | STRING    | NULLABLE |               |

---

### 📊 TABLE: `caption_bandit_stats`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_bandit_stats`
- **Created**: 2025-10-31 16:56:32 UTC
- **Last Modified**: 2025-10-31 18:43:52 UTC ✨ Today
- **Total Rows**: 28 | **Size**: 0.00 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (100.0%)
      ████████████████████ 100.0%
    - **Field Completeness Analysis**:
      - `caption_id`: 🟢 Excellent (100.0% complete, 28 unique values)
      - `page_name`: 🟢 Excellent (100.0% complete, 14 unique values)
      - `successes`: 🟢 Excellent (100.0% complete, 2 unique values)
      - `failures`: 🟢 Excellent (100.0% complete, 2 unique values)
      - `total_observations`: 🟢 Excellent (100.0% complete, 1 unique values)
  - **Sample Data** (showing 5 of 28 rows):
    ```
          caption_id  page_name            successes    failures    total_observations    total_revenue    avg_conversion_rate    avg_emv
--------------------  -----------------  -----------  ----------  --------------------  ---------------  ---------------------  ---------
 9222337751997516893  jadebri                      1           3                     2                0                      0          0
 8044460054888879679  miaharper                    1           3                     2                0                      0          0
-2659062595238294652  miaharper                    1           3                     2                0                      0          0
 9222337751997516807  neenah                       1           3                     2                0                      0          0
 2258911065558240856  itskassielee_free            1           3                     2                0                      0          0
    ```
- **Schema** (15 columns):
| Name                   | Type      | Mode     | Description   |
|------------------------|-----------|----------|---------------|
| caption_id             | INTEGER   | REQUIRED |               |
| page_name              | STRING    | REQUIRED |               |
| successes              | INTEGER   | NULLABLE |               |
| failures               | INTEGER   | NULLABLE |               |
| total_observations     | INTEGER   | NULLABLE |               |
| total_revenue          | FLOAT     | NULLABLE |               |
| avg_conversion_rate    | FLOAT     | NULLABLE |               |
| avg_emv                | FLOAT     | NULLABLE |               |
| last_emv_observed      | FLOAT     | NULLABLE |               |
| confidence_lower_bound | FLOAT     | NULLABLE |               |
| confidence_upper_bound | FLOAT     | NULLABLE |               |
| exploration_score      | FLOAT     | NULLABLE |               |
| last_used              | TIMESTAMP | NULLABLE |               |
| last_updated           | TIMESTAMP | NULLABLE |               |
| performance_percentile | INTEGER   | NULLABLE |               |

---

### 📊 TABLE: `caption_bank`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_bank`
- **Created**: 2025-10-27 04:20:42 UTC
- **Last Modified**: 2025-10-28 13:06:17 UTC 📅 This Week
- **Description**: High-performing caption bank for OnlyFans schedule optimization. Only includes captions with 50+ revenue per send.
- **Total Rows**: 44,651 | **Size**: 19.34 MB 📁 Small
  - **Data Quality Metrics**:
    - Overall Completeness: 🟠 Fair (74.8%)
      ██████████████░░░░░░ 74.8%
    - **Field Completeness Analysis**:
      - `caption_id`: 🟢 Excellent (100.0% complete, 44,651 unique values)
      - `caption_text`: 🟢 Excellent (100.0% complete, 37,271 unique values)
      - `content_category`: 🟢 Excellent (100.0% complete, 15 unique values)
      - `price_tier`: 🟢 Excellent (100.0% complete, 7 unique values)
      - `has_urgency`: 🟢 Excellent (100.0% complete, 2 unique values)
  - **Sample Data** (showing 5 of 44,651 rows):
    ```
          caption_id  caption_text                                        content_category    price_tier    has_urgency    conversion_score    revenue_score    efficiency_score
--------------------  --------------------------------------------------  ------------------  ------------  -------------  ------------------  ---------------  ------------------
 9222337751997510840  If you look, you're in trouble ��                   General             bump          False          NULL                NULL             NULL
-4130807093063077072  🚿 SHOWER SECRETS UNVEILED 🚿                         General             premium       False          0.01                0.14             0.0
                      bringing you into my s
 -250338399493694600  imagine your hands over my gorgeous pussy, babe 😈💋  General             mid           False          0.01                0.12             0.0
-3879691605486526973  I don’t normally do this, but I couldn’t resist go  General             mid           True           0.02                0.22             0.0
 5403285199639304730  I hope my feet are enough to make you hard 🙈 Are y  G/G                 mid           True           0.02                0.45             0.0
    ```
- **Schema** (40 columns):
| Name                      | Type      | Mode     | Description                                      |
|---------------------------|-----------|----------|--------------------------------------------------|
| caption_id                | INTEGER   | REQUIRED |                                                  |
| caption_text              | STRING    | REQUIRED |                                                  |
| content_category          | STRING    | NULLABLE |                                                  |
| price_tier                | STRING    | NULLABLE |                                                  |
| has_urgency               | BOOLEAN   | NULLABLE |                                                  |
| conversion_score          | FLOAT     | NULLABLE |                                                  |
| revenue_score             | FLOAT     | NULLABLE |                                                  |
| efficiency_score          | FLOAT     | NULLABLE |                                                  |
| overall_performance_score | FLOAT     | NULLABLE |                                                  |
| avg_revenue               | FLOAT     | NULLABLE |                                                  |
| max_revenue               | FLOAT     | NULLABLE |                                                  |
| min_revenue               | FLOAT     | NULLABLE |                                                  |
| avg_conversion_rate       | FLOAT     | NULLABLE |                                                  |
| best_conversion_rate      | FLOAT     | NULLABLE |                                                  |
| avg_revenue_per_recipient | FLOAT     | NULLABLE |                                                  |
| avg_purchase_rate         | FLOAT     | NULLABLE |                                                  |
| total_sends               | INTEGER   | NULLABLE |                                                  |
| pages_used_count          | INTEGER   | NULLABLE |                                                  |
| sample_pages_used         | STRING    | REPEATED |                                                  |
| total_reach               | INTEGER   | NULLABLE |                                                  |
| total_conversions         | INTEGER   | NULLABLE |                                                  |
| lifetime_revenue          | FLOAT     | NULLABLE |                                                  |
| caption_length            | INTEGER   | NULLABLE |                                                  |
| question_count            | FLOAT     | NULLABLE |                                                  |
| exclamation_count         | FLOAT     | NULLABLE |                                                  |
| emoji_count               | FLOAT     | NULLABLE |                                                  |
| successful_days           | STRING    | REPEATED |                                                  |
| successful_hours          | INTEGER   | REPEATED |                                                  |
| min_price                 | FLOAT     | NULLABLE |                                                  |
| max_price                 | FLOAT     | NULLABLE |                                                  |
| avg_price                 | FLOAT     | NULLABLE |                                                  |
| first_used                | TIMESTAMP | NULLABLE |                                                  |
| last_used                 | TIMESTAMP | NULLABLE |                                                  |
| days_since_last_use       | INTEGER   | NULLABLE |                                                  |
| usage_status              | STRING    | NULLABLE |                                                  |
| validation_level          | STRING    | NULLABLE |                                                  |
| created_at                | TIMESTAMP | NULLABLE |                                                  |
| updated_at                | TIMESTAMP | NULLABLE |                                                  |
| is_long_form              | BOOLEAN   | NULLABLE |                                                  |
| caption_key               | STRING    | NULLABLE | Normalized hash of caption_text for stable joins |

---

### 👁️ VIEW: `caption_bank_enriched`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_bank_enriched`
- **Created**: 2025-10-31 16:56:20 UTC
- **Last Modified**: 2025-10-31 16:56:20 UTC ✨ Today
- **View Query**:
```sql
SELECT
  cb.*,
  CASE
    WHEN has_urgency AND REGEXP_CONTAINS(caption_text, r'(?i)(now|today|limited|expir)') THEN 'Urgency'
    WHEN REGEXP_CONTAINS(caption_text, r'(?i)(exclusive|vip|special|members only)') THEN 'Exclusivity'
    WHEN REGEXP_CONTAINS(caption_text, r'(?i)(only \d+ left|last chance)') THEN 'Scarcity'
    WHEN REGEXP_CONTAINS(caption_text, r'(?i)(everyone|fans love|popular)') THEN 'Social Proof'
    WHEN caption_text LIKE '%?%' THEN 'Curiosity'
    ELSE 'General'
  END as psychological_trigger
FROM `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb
```
- **Schema** (41 columns):
| Name                      | Type      | Mode     | Description   |
|---------------------------|-----------|----------|---------------|
| caption_id                | INTEGER   | NULLABLE |               |
| caption_text              | STRING    | NULLABLE |               |
| content_category          | STRING    | NULLABLE |               |
| price_tier                | STRING    | NULLABLE |               |
| has_urgency               | BOOLEAN   | NULLABLE |               |
| conversion_score          | FLOAT     | NULLABLE |               |
| revenue_score             | FLOAT     | NULLABLE |               |
| efficiency_score          | FLOAT     | NULLABLE |               |
| overall_performance_score | FLOAT     | NULLABLE |               |
| avg_revenue               | FLOAT     | NULLABLE |               |
| max_revenue               | FLOAT     | NULLABLE |               |
| min_revenue               | FLOAT     | NULLABLE |               |
| avg_conversion_rate       | FLOAT     | NULLABLE |               |
| best_conversion_rate      | FLOAT     | NULLABLE |               |
| avg_revenue_per_recipient | FLOAT     | NULLABLE |               |
| avg_purchase_rate         | FLOAT     | NULLABLE |               |
| total_sends               | INTEGER   | NULLABLE |               |
| pages_used_count          | INTEGER   | NULLABLE |               |
| sample_pages_used         | STRING    | REPEATED |               |
| total_reach               | INTEGER   | NULLABLE |               |
| total_conversions         | INTEGER   | NULLABLE |               |
| lifetime_revenue          | FLOAT     | NULLABLE |               |
| caption_length            | INTEGER   | NULLABLE |               |
| question_count            | FLOAT     | NULLABLE |               |
| exclamation_count         | FLOAT     | NULLABLE |               |
| emoji_count               | FLOAT     | NULLABLE |               |
| successful_days           | STRING    | REPEATED |               |
| successful_hours          | INTEGER   | REPEATED |               |
| min_price                 | FLOAT     | NULLABLE |               |
| max_price                 | FLOAT     | NULLABLE |               |
| avg_price                 | FLOAT     | NULLABLE |               |
| first_used                | TIMESTAMP | NULLABLE |               |
| last_used                 | TIMESTAMP | NULLABLE |               |
| days_since_last_use       | INTEGER   | NULLABLE |               |
| usage_status              | STRING    | NULLABLE |               |
| validation_level          | STRING    | NULLABLE |               |
| created_at                | TIMESTAMP | NULLABLE |               |
| updated_at                | TIMESTAMP | NULLABLE |               |
| is_long_form              | BOOLEAN   | NULLABLE |               |
| caption_key               | STRING    | NULLABLE |               |
| psychological_trigger     | STRING    | NULLABLE |               |

---

### 📊 TABLE: `caption_bank_staging`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_bank_staging`
- **Created**: 2025-10-28 04:58:00 UTC
- **Last Modified**: 2025-10-28 04:58:00 UTC 📅 This Week
- **Total Rows**: 10,991 | **Size**: 6.29 MB 📁 Small
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (100.0%)
      ████████████████████ 100.0%
    - **Field Completeness Analysis**:
      - `created_at`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `validation_level`: 🟢 Excellent (100.0% complete, 3 unique values)
      - `usage_status`: 🟢 Excellent (100.0% complete, 2 unique values)
      - `days_since_last_use`: 🟢 Excellent (100.0% complete, 1,479 unique values)
      - `avg_price`: 🟢 Excellent (100.0% complete, 723 unique values)
  - **Sample Data** (showing 5 of 10,991 rows):
    ```
created_at                        validation_level    usage_status      days_since_last_use    avg_price    max_price  updated_at                          min_price
--------------------------------  ------------------  --------------  ---------------------  -----------  -----------  --------------------------------  -----------
2025-10-28 04:57:10.287000+00:00  low                 available                         192            3            3  2025-10-28 04:57:10.287000+00:00            3
2025-10-28 04:57:10.287000+00:00  low                 available                         212            3            3  2025-10-28 04:57:10.287000+00:00            3
2025-10-28 04:57:10.287000+00:00  low                 available                         240            3            3  2025-10-28 04:57:10.287000+00:00            3
2025-10-28 04:57:10.287000+00:00  low                 available                         246            3            3  2025-10-28 04:57:10.287000+00:00            3
2025-10-28 04:57:10.287000+00:00  low                 available                         217            3            3  2025-10-28 04:57:10.287000+00:00            3
    ```
- **Schema** (38 columns):
| Name                      | Type      | Mode     | Description   |
|---------------------------|-----------|----------|---------------|
| created_at                | TIMESTAMP | NULLABLE |               |
| validation_level          | STRING    | NULLABLE |               |
| usage_status              | STRING    | NULLABLE |               |
| days_since_last_use       | INTEGER   | NULLABLE |               |
| avg_price                 | FLOAT     | NULLABLE |               |
| max_price                 | FLOAT     | NULLABLE |               |
| updated_at                | TIMESTAMP | NULLABLE |               |
| min_price                 | FLOAT     | NULLABLE |               |
| successful_days           | STRING    | REPEATED |               |
| emoji_count               | FLOAT     | NULLABLE |               |
| lifetime_revenue          | FLOAT     | NULLABLE |               |
| total_conversions         | FLOAT     | NULLABLE |               |
| question_count            | FLOAT     | NULLABLE |               |
| total_sends               | INTEGER   | NULLABLE |               |
| avg_conversion_rate       | FLOAT     | NULLABLE |               |
| avg_purchase_rate         | FLOAT     | NULLABLE |               |
| overall_performance_score | FLOAT     | NULLABLE |               |
| total_reach               | INTEGER   | NULLABLE |               |
| avg_revenue_per_recipient | FLOAT     | NULLABLE |               |
| best_conversion_rate      | FLOAT     | NULLABLE |               |
| efficiency_score          | FLOAT     | NULLABLE |               |
| conversion_score          | FLOAT     | NULLABLE |               |
| last_used                 | TIMESTAMP | NULLABLE |               |
| price_tier                | STRING    | NULLABLE |               |
| caption_length            | INTEGER   | NULLABLE |               |
| pages_used_count          | INTEGER   | NULLABLE |               |
| first_used                | TIMESTAMP | NULLABLE |               |
| exclamation_count         | FLOAT     | NULLABLE |               |
| revenue_score             | FLOAT     | NULLABLE |               |
| min_revenue               | FLOAT     | NULLABLE |               |
| max_revenue               | FLOAT     | NULLABLE |               |
| caption_id                | INTEGER   | NULLABLE |               |
| avg_revenue               | FLOAT     | NULLABLE |               |
| successful_hours          | INTEGER   | REPEATED |               |
| content_category          | STRING    | NULLABLE |               |
| sample_pages_used         | STRING    | REPEATED |               |
| has_urgency               | BOOLEAN   | NULLABLE |               |
| caption_text              | STRING    | NULLABLE |               |

---

### 📊 TABLE: `caption_filter_audit_log`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_filter_audit_log`
- **Created**: 2025-10-30 06:56:02 UTC
- **Last Modified**: 2025-10-30 06:56:02 UTC 🆕 Yesterday
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (14 columns):
| Name                     | Type      | Mode     | Description   |
|--------------------------|-----------|----------|---------------|
| workflow_id              | STRING    | NULLABLE |               |
| schedule_id              | STRING    | NULLABLE |               |
| page_name                | STRING    | NULLABLE |               |
| caption_id               | STRING    | NULLABLE |               |
| caption_text             | STRING    | NULLABLE |               |
| content_category         | STRING    | NULLABLE |               |
| price_tier               | STRING    | NULLABLE |               |
| rule_type                | STRING    | NULLABLE |               |
| rule_value               | STRING    | NULLABLE |               |
| enforcement              | STRING    | NULLABLE |               |
| stage                    | STRING    | NULLABLE |               |
| filtered_at              | TIMESTAMP | REQUIRED |               |
| total_pool_before_filter | INTEGER   | NULLABLE |               |
| total_pool_after_filter  | INTEGER   | NULLABLE |               |

---

### 👁️ VIEW: `caption_pattern_analysis`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_pattern_analysis`
- **Created**: 2025-10-27 04:22:58 UTC
- **Last Modified**: 2025-10-27 04:22:58 UTC 📅 This Week
- **View Query**:
```sql
WITH pattern_extraction AS (
    SELECT
        content_category,
        price_tier,
        CASE
            WHEN REGEXP_CONTAINS(caption_text, r'\\?') THEN 'question_hook'
            WHEN REGEXP_CONTAINS(LOWER(caption_text), r'^(hey |hi |hello )') THEN 'greeting_opener'
            WHEN REGEXP_CONTAINS(caption_text, r'\\.\\.\\.') THEN 'ellipsis_suspense'
            WHEN REGEXP_CONTAINS(caption_text, r'! ') THEN 'exclamation_heavy'
            ELSE 'standard'
        END as opening_pattern,
        CASE
            WHEN emoji_count >= 5 THEN 'emoji_rich'
            WHEN emoji_count >= 2 THEN 'emoji_moderate'
            ELSE 'emoji_minimal'
        END as emoji_usage,
        CASE
            WHEN caption_length < 100 THEN 'short'
            WHEN caption_length < 200 THEN 'medium'
            ELSE 'long'
        END as length_category,
        has_urgency,
        avg_conversion_rate,
        avg_revenue,
        overall_performance_score
    FROM
        `of-scheduler-proj.eros_scheduling_brain.caption_bank`
)
SELECT
    content_category,
    price_tier,
    opening_pattern,
    emoji_usage,
    length_category,
    has_urgency,
    COUNT(*) as caption_count,
    ROUND(AVG(avg_conversion_rate), 4) as avg_conversion_rate,
    ROUND(AVG(avg_revenue), 2) as avg_revenue,
    ROUND(AVG(overall_performance_score), 2) as avg_performance_score
FROM
    pattern_extraction
GROUP BY
    content_category, price_tier, opening_pattern, emoji_usage, length_category, has_urgency
ORDER BY
    avg_performance_score DESC
```
- **Schema** (10 columns):
| Name                  | Type    | Mode     | Description   |
|-----------------------|---------|----------|---------------|
| content_category      | STRING  | NULLABLE |               |
| price_tier            | STRING  | NULLABLE |               |
| opening_pattern       | STRING  | NULLABLE |               |
| emoji_usage           | STRING  | NULLABLE |               |
| length_category       | STRING  | NULLABLE |               |
| has_urgency           | BOOLEAN | NULLABLE |               |
| caption_count         | INTEGER | NULLABLE |               |
| avg_conversion_rate   | FLOAT   | NULLABLE |               |
| avg_revenue           | FLOAT   | NULLABLE |               |
| avg_performance_score | FLOAT   | NULLABLE |               |

---

### 👁️ VIEW: `caption_performance_by_creator`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_performance_by_creator`
- **Created**: 2025-10-28 13:10:21 UTC
- **Last Modified**: 2025-10-28 13:10:21 UTC 📅 This Week
- **View Query**:
```sql
WITH caption_usage AS (
  SELECT
    mm.page_name,
    cb.caption_id,
    cb.caption_text,
    cb.content_category,
    cb.price_tier,
    mm.sending_time,
    mm.purchased_count,
    mm.sent_count,
    mm.earnings
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
  JOIN `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb
    ON `of-scheduler-proj.eros_scheduling_brain`.caption_key(mm.message) =
       `of-scheduler-proj.eros_scheduling_brain`.caption_key(cb.caption_text)
  WHERE mm.sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
)
SELECT
  page_name,
  caption_id,
  caption_text,
  content_category,
  price_tier,
  COUNT(*) as times_used,
  SAFE_DIVIDE(SUM(purchased_count), SUM(sent_count)) as creator_conversion_rate,
  SUM(earnings) as creator_total_revenue,
  MAX(sending_time) as last_used_by_creator
FROM caption_usage
GROUP BY page_name, caption_id, caption_text, content_category, price_tier
```
- **Schema** (9 columns):
| Name                    | Type      | Mode     | Description   |
|-------------------------|-----------|----------|---------------|
| page_name               | STRING    | NULLABLE |               |
| caption_id              | INTEGER   | NULLABLE |               |
| caption_text            | STRING    | NULLABLE |               |
| content_category        | STRING    | NULLABLE |               |
| price_tier              | STRING    | NULLABLE |               |
| times_used              | INTEGER   | NULLABLE |               |
| creator_conversion_rate | FLOAT     | NULLABLE |               |
| creator_total_revenue   | FLOAT     | NULLABLE |               |
| last_used_by_creator    | TIMESTAMP | NULLABLE |               |

---

### 📊 TABLE: `caption_performance_tracking`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_performance_tracking`
- **Created**: 2025-10-26 23:52:05 UTC
- **Last Modified**: 2025-10-26 23:52:05 UTC 📅 This Week
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (17 columns):
| Name                  | Type      | Mode     | Description   |
|-----------------------|-----------|----------|---------------|
| caption_hash          | STRING    | REQUIRED |               |
| caption_text          | STRING    | REQUIRED |               |
| message_type          | STRING    | NULLABLE |               |
| lifetime_conversion   | FLOAT     | NULLABLE |               |
| conversion_variance   | FLOAT     | NULLABLE |               |
| recent_7d_conversion  | FLOAT     | NULLABLE |               |
| recent_30d_conversion | FLOAT     | NULLABLE |               |
| total_uses            | INTEGER   | NULLABLE |               |
| unique_pages_used     | INTEGER   | NULLABLE |               |
| last_used_date        | DATE      | NULLABLE |               |
| performance_tier      | STRING    | NULLABLE |               |
| best_hours            | JSON      | NULLABLE |               |
| creator_performance   | JSON      | NULLABLE |               |
| first_seen_date       | DATE      | NULLABLE |               |
| last_updated          | TIMESTAMP | NULLABLE |               |
| is_active             | BOOLEAN   | NULLABLE |               |
| fatigue_score         | FLOAT     | NULLABLE |               |

---

### 👁️ VIEW: `caption_tracking_view`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.caption_tracking_view`
- **Created**: 2025-10-28 17:28:59 UTC
- **Last Modified**: 2025-10-28 17:28:59 UTC 📅 This Week
- **View Query**:
```sql
SELECT
    aca.page_name,
    aca.caption_id,
    aca.scheduled_send_date,
    cb.overall_performance_score as predicted_score,
    SAFE_DIVIDE(mm.purchased_count, mm.sent_count) as actual_conversion,
    mm.earnings as actual_revenue,
    CASE
        WHEN mm.earnings IS NOT NULL THEN
            ROUND(1 - ABS(cb.avg_revenue - mm.earnings) / NULLIF(cb.avg_revenue, 0), 2)
        ELSE NULL
    END as prediction_accuracy
FROM
    `of-scheduler-proj.eros_scheduling_brain.active_caption_assignments` aca
JOIN
    `of-scheduler-proj.eros_scheduling_brain.caption_bank` cb
    ON aca.caption_id = cb.caption_id
LEFT JOIN
    `of-scheduler-proj.eros_scheduling_brain.mass_messages` mm
    ON aca.page_name = mm.page_name
    AND aca.caption_text = mm.message
    AND DATE(mm.sending_time) = aca.scheduled_send_date
WHERE
    aca.is_active = TRUE
ORDER BY
    aca.scheduled_send_date DESC,
    aca.page_name
```
- **Schema** (7 columns):
| Name                | Type    | Mode     | Description   |
|---------------------|---------|----------|---------------|
| page_name           | STRING  | NULLABLE |               |
| caption_id          | INTEGER | NULLABLE |               |
| scheduled_send_date | DATE    | NULLABLE |               |
| predicted_score     | FLOAT   | NULLABLE |               |
| actual_conversion   | FLOAT   | NULLABLE |               |
| actual_revenue      | FLOAT   | NULLABLE |               |
| prediction_accuracy | FLOAT   | NULLABLE |               |

---

### 📊 TABLE: `creator_allowed_profile`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.creator_allowed_profile`
- **Created**: 2025-10-30 06:55:59 UTC
- **Last Modified**: 2025-10-30 06:55:59 UTC 🆕 Yesterday
- **Description**: Creator allowed content profiles - defines permitted categories and price tiers per creator. NULL/empty arrays = allow all. Applied before hard restrictions.
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (11 columns):
| Name                     | Type      | Mode     | Description                                                                                   |
|--------------------------|-----------|----------|-----------------------------------------------------------------------------------------------|
| page_name                | STRING    | REQUIRED | Creator OnlyFans page name (lowercase)                                                        |
| ppv_allowed_categories   | STRING    | REPEATED | Allowed PPV content categories (NULL/empty = allow all). Examples: ['solo', 'b/g', 'fantasy'] |
| ppv_allowed_price_tiers  | STRING    | REPEATED | Allowed PPV price tiers (NULL/empty = allow all). Examples: ['tier_1', 'tier_2', 'tier_3']    |
| bump_allowed_categories  | STRING    | REPEATED | Allowed BUMP content categories (NULL/empty = allow all). Examples: ['solo', 'tease']         |
| bump_allowed_price_tiers | STRING    | REPEATED | Allowed BUMP price tiers (NULL/empty = allow all). Examples: ['tier_1', 'tier_2']             |
| is_active                | BOOLEAN   | REQUIRED | Whether this profile is currently active                                                      |
| feature_enabled          | BOOLEAN   | REQUIRED | Whether caption_restrictions_enabled flag is true for this creator                            |
| created_at               | TIMESTAMP | REQUIRED | When this profile was created                                                                 |
| updated_at               | TIMESTAMP | REQUIRED | When this profile was last updated                                                            |
| updated_by               | STRING    | NULLABLE | User or system that last updated this profile                                                 |
| notes                    | STRING    | NULLABLE | Admin notes about this profile configuration                                                  |

---

### 👁️ VIEW: `creator_allowed_profile_v`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.creator_allowed_profile_v`
- **Created**: 2025-10-30 06:59:30 UTC
- **Last Modified**: 2025-10-30 06:59:30 UTC 🆕 Yesterday
- **View Query**:
```sql
WITH ranked_profiles AS (
  SELECT
    page_name,
    ppv_allowed_categories,
    ppv_allowed_price_tiers,
    bump_allowed_categories,
    bump_allowed_price_tiers,
    is_active,
    feature_enabled,
    created_at,
    updated_at,
    updated_by,
    notes,
    -- Rank by most recent update per page_name
    ROW_NUMBER() OVER (
      PARTITION BY page_name
      ORDER BY updated_at DESC
    ) AS rn
  FROM `of-scheduler-proj.eros_scheduling_brain.creator_allowed_profile`
  WHERE is_active = TRUE  -- Only consider active profiles
)
SELECT
  page_name,
  ppv_allowed_categories,
  ppv_allowed_price_tiers,
  bump_allowed_categories,
  bump_allowed_price_tiers,
  is_active,
  feature_enabled,
  created_at,
  updated_at,
  updated_by,
  notes
FROM ranked_profiles
WHERE rn = 1
```
- **Schema** (11 columns):
| Name                     | Type      | Mode     | Description   |
|--------------------------|-----------|----------|---------------|
| page_name                | STRING    | NULLABLE |               |
| ppv_allowed_categories   | STRING    | REPEATED |               |
| ppv_allowed_price_tiers  | STRING    | REPEATED |               |
| bump_allowed_categories  | STRING    | REPEATED |               |
| bump_allowed_price_tiers | STRING    | REPEATED |               |
| is_active                | BOOLEAN   | NULLABLE |               |
| feature_enabled          | BOOLEAN   | NULLABLE |               |
| created_at               | TIMESTAMP | NULLABLE |               |
| updated_at               | TIMESTAMP | NULLABLE |               |
| updated_by               | STRING    | NULLABLE |               |
| notes                    | STRING    | NULLABLE |               |

---

### 📊 TABLE: `creator_caption_restrictions`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.creator_caption_restrictions`
- **Created**: 2025-10-30 06:55:58 UTC
- **Last Modified**: 2025-10-30 06:55:58 UTC 🆕 Yesterday
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (13 columns):
| Name                   | Type      | Mode     | Description   |
|------------------------|-----------|----------|---------------|
| page_name              | STRING    | REQUIRED |               |
| restriction_text       | STRING    | NULLABLE |               |
| hard_patterns          | STRING    | REPEATED |               |
| soft_patterns          | STRING    | REPEATED |               |
| restricted_categories  | STRING    | REPEATED |               |
| restricted_price_tiers | STRING    | REPEATED |               |
| applies_to_scope       | STRING    | NULLABLE |               |
| min_ppv_pool           | INTEGER   | NULLABLE |               |
| min_bump_pool          | INTEGER   | NULLABLE |               |
| is_active              | BOOLEAN   | REQUIRED |               |
| updated_at             | TIMESTAMP | REQUIRED |               |
| updated_by             | STRING    | NULLABLE |               |
| version                | INTEGER   | REQUIRED |               |

---

### 📊 TABLE: `creator_content_inventory`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.creator_content_inventory`
- **Created**: 2025-10-28 18:55:01 UTC
- **Last Modified**: 2025-10-28 18:55:57 UTC 📅 This Week
- **Description**: Creator vault content inventory for validating caption selection against available content
- **Total Rows**: 36 | **Size**: 0.01 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (100.0%)
      ████████████████████ 100.0%
    - **Field Completeness Analysis**:
      - `page_name`: 🟢 Excellent (100.0% complete, 36 unique values)
      - `inventory_date`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `total_content_pieces`: 🟢 Excellent (100.0% complete, 36 unique values)
      - `inventory_quality_score`: 🟢 Excellent (100.0% complete, 26 unique values)
      - `vault_audit_date`: 🟢 Excellent (100.0% complete, 2 unique values)
  - **Sample Data** (showing 5 of 36 rows):
    ```
page_name         inventory_date    available_categories                                  total_content_pieces    inventory_quality_score  vault_audit_date    created_at                        updated_at
----------------  ----------------  --------------------------------------------------  ----------------------  -------------------------  ------------------  --------------------------------  --------------------------------
tessathomas       2025-10-28        ['B/G', 'Boobs', 'Custom', 'G/G', 'Solo', 'Threeso                    2793                       0.93  2025-10-28          2025-10-28 18:55:56.482662+00:00  2025-10-28 18:55:56.482662+00:00
calilove          2025-10-28        ['General']                                                              0                       0     2024-10-28          2025-10-28 18:55:56.482662+00:00  2025-10-28 18:55:56.482662+00:00
ashlyroux         2025-10-28        ['B/G', 'Boobs', 'Custom', 'G/G', 'General']                           129                       0.65  2025-10-28          2025-10-28 18:55:56.482662+00:00  2025-10-28 18:55:56.482662+00:00
misslexafreepage  2025-10-28        ['Anal', 'B/G', 'Custom', 'Solo', 'General']                           321                       0.7   2025-10-28          2025-10-28 18:55:56.482662+00:00  2025-10-28 18:55:56.482662+00:00
norarhodes        2025-10-28        ['B/G', 'Boobs', 'Custom', 'General']                                  352                       0.71  2025-10-28          2025-10-28 18:55:56.482662+00:00  2025-10-28 18:55:56.482662+00:00
    ```
- **Schema** (10 columns):
| Name                    | Type      | Mode     | Description   |
|-------------------------|-----------|----------|---------------|
| page_name               | STRING    | REQUIRED |               |
| inventory_date          | DATE      | REQUIRED |               |
| available_categories    | STRING    | REPEATED |               |
| total_content_pieces    | INTEGER   | REQUIRED |               |
| inventory_quality_score | FLOAT     | REQUIRED |               |
| vault_audit_date        | DATE      | REQUIRED |               |
| created_at              | TIMESTAMP | NULLABLE |               |
| updated_at              | TIMESTAMP | NULLABLE |               |
| notes                   | STRING    | NULLABLE |               |
| audited_by              | STRING    | NULLABLE |               |

---

### 👁️ VIEW: `day_of_week_performance`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.day_of_week_performance`
- **Created**: 2025-10-28 13:10:22 UTC
- **Last Modified**: 2025-10-28 13:10:22 UTC 📅 This Week
- **View Query**:
```sql
WITH recent_ppv AS (
  SELECT
    page_name,
    `of-scheduler-proj.eros_scheduling_brain`.la_dayofweek(sending_time) as day_num,
    FORMAT_TIMESTAMP('%A', DATETIME(sending_time, "America/Los_Angeles")) as day_name,
    sent_count,
    purchased_count,
    earnings
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND message_type = 'PPV'
),
day_stats AS (
  SELECT
    page_name,
    day_num,
    day_name,
    COUNT(*) as sample_size,
    SAFE_DIVIDE(SUM(purchased_count), SUM(sent_count)) as avg_conversion,
    AVG(earnings) as avg_revenue
  FROM recent_ppv
  GROUP BY page_name, day_num, day_name
  HAVING sample_size >= 3
),
overall_stats AS (
  SELECT
    page_name,
    AVG(avg_conversion) as overall_avg_conversion
  FROM day_stats
  GROUP BY page_name
)
SELECT
  d.page_name,
  d.day_num,
  d.day_name,
  d.sample_size,
  d.avg_conversion,
  d.avg_revenue,
  o.overall_avg_conversion,
  SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) as performance_index,
  CASE
    WHEN SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) > 1.20 THEN 'HIGH_PERFORMER'
    WHEN SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) < 0.80 THEN 'LOW_PERFORMER'
    ELSE 'NORMAL'
  END as classification,
  CASE
    WHEN SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) > 1.40 THEN 1.30
    WHEN SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) > 1.20 THEN 1.20
    WHEN SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) >= 0.90 THEN 1.00
    WHEN SAFE_DIVIDE(d.avg_conversion, o.overall_avg_conversion) >= 0.70 THEN 0.85
    ELSE 0.70
  END as volume_allocation_multiplier
FROM day_stats d
JOIN overall_stats o USING (page_name)
```
- **Schema** (10 columns):
| Name                         | Type    | Mode     | Description   |
|------------------------------|---------|----------|---------------|
| page_name                    | STRING  | NULLABLE |               |
| day_num                      | INTEGER | NULLABLE |               |
| day_name                     | STRING  | NULLABLE |               |
| sample_size                  | INTEGER | NULLABLE |               |
| avg_conversion               | FLOAT   | NULLABLE |               |
| avg_revenue                  | FLOAT   | NULLABLE |               |
| overall_avg_conversion       | FLOAT   | NULLABLE |               |
| performance_index            | FLOAT   | NULLABLE |               |
| classification               | STRING  | NULLABLE |               |
| volume_allocation_multiplier | FLOAT   | NULLABLE |               |

---

### 📊 TABLE: `etl_job_runs`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.etl_job_runs`
- **Created**: 2025-10-18 07:56:24 UTC
- **Last Modified**: 2025-10-31 18:36:22 UTC ✨ Today
- **Description**: ETL job execution tracking for intelligent freshness checking
- **Total Rows**: 7 | **Size**: 0.00 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (95.7%)
      ███████████████████░ 95.7%
    - **Field Completeness Analysis**:
      - `run_id`: 🟢 Excellent (100.0% complete, 7 unique values)
      - `job_name`: 🟢 Excellent (100.0% complete, 2 unique values)
      - `started_at`: 🟢 Excellent (100.0% complete, 7 unique values)
      - `status`: 🟢 Excellent (100.0% complete, 2 unique values)
      - `messages_found`: 🟢 Excellent (100.0% complete, 5 unique values)
  - **Sample Data** (showing 5 of 7 rows):
    ```
run_id                                job_name                     started_at                        completed_at                      status      messages_found    messages_processed    messages_failed
------------------------------------  ---------------------------  --------------------------------  --------------------------------  --------  ----------------  --------------------  -----------------
2895a777-f79a-40c8-ace6-def3b7dc6f09  analyze_creator_performance  2025-10-31 18:34:14.137682+00:00  NULL                              SUCCESS                  0                     1                  0
2c10a1ce-5a68-4bea-85f7-8325fcc0f0f3  gmail-etl                    2025-10-16 10:39:37.101433+00:00  2025-10-16 10:40:09.227943+00:00  success                109                     0                 23
93dfb616-c0e9-49f5-97e5-743ba4f6f966  gmail-etl                    2025-10-26 05:09:37.310311+00:00  2025-10-26 05:13:15.056943+00:00  success                 96                    36                 20
d37ea893-48db-469a-8e87-655bb3bab263  analyze_creator_performance  2025-10-31 18:35:02.571875+00:00  NULL                              SUCCESS                  0                     1                  0
b612bd68-5973-4093-85f3-ec058c564143  gmail-etl                    2025-10-20 17:37:32.712552+00:00  2025-10-20 17:43:01.587615+00:00  success                162                    41                 35
    ```
- **Schema** (18 columns):
| Name                       | Type      | Mode     | Description   |
|----------------------------|-----------|----------|---------------|
| run_id                     | STRING    | REQUIRED |               |
| job_name                   | STRING    | REQUIRED |               |
| started_at                 | TIMESTAMP | REQUIRED |               |
| completed_at               | TIMESTAMP | NULLABLE |               |
| status                     | STRING    | REQUIRED |               |
| messages_found             | INTEGER   | NULLABLE |               |
| messages_processed         | INTEGER   | NULLABLE |               |
| messages_failed            | INTEGER   | NULLABLE |               |
| rows_loaded                | INTEGER   | NULLABLE |               |
| duplicates_skipped         | INTEGER   | NULLABLE |               |
| latest_data_timestamp      | TIMESTAMP | NULLABLE |               |
| data_date_range_start      | TIMESTAMP | NULLABLE |               |
| data_date_range_end        | TIMESTAMP | NULLABLE |               |
| error_message              | STRING    | NULLABLE |               |
| error_details              | STRING    | NULLABLE |               |
| environment                | STRING    | NULLABLE |               |
| execution_duration_seconds | FLOAT     | NULLABLE |               |
| cloud_run_job_execution_id | STRING    | NULLABLE |               |

---

### 📊 TABLE: `feature_flags`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.feature_flags`
- **Created**: 2025-10-30 06:55:17 UTC
- **Last Modified**: 2025-10-30 06:59:38 UTC 🆕 Yesterday
- **Total Rows**: 1 | **Size**: 0.00 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟠 Fair (75.0%)
      ███████████████░░░░░ 75.0%
    - **Field Completeness Analysis**:
      - `flag`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `is_enabled`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `updated_at`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `updated_by`: 🔴 Poor (0.0% complete, 0 unique values)
  - **Sample Data** (showing 1 of 1 rows):
    ```
flag                          is_enabled    updated_at                        updated_by
----------------------------  ------------  --------------------------------  ------------
caption_restrictions_enabled  True          2025-10-30 06:59:36.266788+00:00  NULL
    ```
- **Schema** (4 columns):
| Name       | Type      | Mode     | Description   |
|------------|-----------|----------|---------------|
| flag       | STRING    | REQUIRED |               |
| is_enabled | BOOLEAN   | REQUIRED |               |
| updated_at | TIMESTAMP | REQUIRED |               |
| updated_by | STRING    | NULLABLE |               |

---

### 📊 TABLE: `holiday_calendar`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.holiday_calendar`
- **Created**: 2025-10-31 18:11:39 UTC
- **Last Modified**: 2025-10-31 18:11:39 UTC ✨ Today
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (2 columns):
| Name         | Type   | Mode     | Description   |
|--------------|--------|----------|---------------|
| holiday_date | DATE   | REQUIRED |               |
| name         | STRING | NULLABLE |               |

---

### 📊 TABLE: `import_history`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.import_history`
- **Created**: 2025-10-26 23:52:19 UTC
- **Last Modified**: 2025-10-29 05:33:16 UTC 📅 This Week
- **Total Rows**: 0 | **Size**: 0.00 MB 📄 Tiny
  - ⚠️ **Empty Table** - No data quality metrics available
- **Schema** (15 columns):
| Name              | Type      | Mode     | Description   |
|-------------------|-----------|----------|---------------|
| import_id         | STRING    | REQUIRED |               |
| recommendation_id | STRING    | REQUIRED |               |
| page_name         | STRING    | REQUIRED |               |
| schedule_id       | STRING    | REQUIRED |               |
| imported_at       | TIMESTAMP | REQUIRED |               |
| imported_by       | STRING    | REQUIRED |               |
| sheet_url         | STRING    | NULLABLE |               |
| messages_imported | INTEGER   | NULLABLE |               |
| captions_imported | INTEGER   | NULLABLE |               |
| prices_imported   | INTEGER   | NULLABLE |               |
| import_status     | STRING    | NULLABLE |               |
| error_details     | STRING    | NULLABLE |               |
| day_1_performance | JSON      | NULLABLE |               |
| day_7_performance | JSON      | NULLABLE |               |
| created_date      | DATE      | REQUIRED |               |

---

### 👁️ VIEW: `latest_recommendations`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.latest_recommendations`
- **Created**: 2025-10-29 05:41:23 UTC
- **Last Modified**: 2025-10-29 05:41:23 UTC 📅 This Week
- **View Query**:
```sql
SELECT
  r.*
FROM (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY page_name, schedule_id
      ORDER BY generated_at DESC
    ) as rn
  FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
  WHERE status != 'archived'
) r
WHERE rn = 1
```
- **Schema** (18 columns):
| Name                  | Type      | Mode     | Description   |
|-----------------------|-----------|----------|---------------|
| recommendation_id     | STRING    | NULLABLE |               |
| page_name             | STRING    | NULLABLE |               |
| schedule_id           | STRING    | NULLABLE |               |
| generated_at          | TIMESTAMP | NULLABLE |               |
| imported_at           | TIMESTAMP | NULLABLE |               |
| updated_at            | TIMESTAMP | NULLABLE |               |
| recommendation_data   | JSON      | NULLABLE |               |
| confidence_score      | FLOAT     | NULLABLE |               |
| uniqueness_score      | FLOAT     | NULLABLE |               |
| caption_quality_score | FLOAT     | NULLABLE |               |
| status                | STRING    | NULLABLE |               |
| import_result         | STRING    | NULLABLE |               |
| generated_by          | STRING    | NULLABLE |               |
| imported_by           | STRING    | NULLABLE |               |
| created_date          | DATE      | NULLABLE |               |
| notes                 | STRING    | NULLABLE |               |
| version               | STRING    | NULLABLE |               |
| rn                    | INTEGER   | NULLABLE |               |

---

### 📊 TABLE: `mass_messages`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.mass_messages`
- **Created**: 2025-10-28 04:12:07 UTC
- **Last Modified**: 2025-10-31 16:57:37 UTC ✨ Today
- **Total Rows**: 63,411 | **Size**: 15.45 MB 📁 Small
  - **Data Quality Metrics**:
    - Overall Completeness: 🟢 Excellent (99.0%)
      ███████████████████░ 99.0%
    - **Field Completeness Analysis**:
      - `row_id`: 🟢 Excellent (100.0% complete, 63,411 unique values)
      - `page_name`: 🟢 Excellent (100.0% complete, 39 unique values)
      - `sending_time`: 🟢 Excellent (100.0% complete, 40,875 unique values)
      - `sent_count`: 🟢 Excellent (100.0% complete, 15,672 unique values)
      - `viewed_count`: 🟢 Excellent (100.0% complete, 6,947 unique values)
  - **Sample Data** (showing 5 of 63,411 rows):
    ```
  row_id  page_name          message                                        sending_time               price      sent_count    viewed_count  purchased_count
--------  -----------------  ---------------------------------------------  -------------------------  -------  ------------  --------------  -----------------
    2191  itskassielee_paid  ## **WANT** ***FREE*** **DAILY BUNDLES?? 👀**   2024-04-22 01:24:52+00:00  NULL             7890             359  NULL
                             ###
    2229  itskassielee_paid  ## 😈😽 ***𝐅𝐑𝐄𝐄*** 𝐓𝐀𝐏𝐄 🙈💦 **𝘓𝘐𝘔𝘐𝘛𝘌𝘋 𝘖𝘍𝘍𝘌𝘙** 😱   2024-04-23 14:16:25+00:00  NULL             2959             137  NULL
                             if y
    2266  itskassielee_paid  ### BIG TITTY STEPMOM 🥵                        2024-04-26 00:00:26+00:00  NULL             9915             792  NULL
                             my **SLUTTY STEPMOM** ✨ @o
    2255  itskassielee_paid  ### FREE DOGGYSTYLE BUNDLE 🔞                   2024-04-25 04:20:26+00:00  NULL             3969             624  NULL
                             I am sending a **FREE
    2260  itskassielee_paid  ### FREE DOGGYSTYLE BUNDLE 🔞                   2024-04-25 15:00:20+00:00  NULL             3998             339  NULL
                             I am sending a **FREE
    ```
- **Schema** (11 columns):
| Name            | Type      | Mode     | Description   |
|-----------------|-----------|----------|---------------|
| row_id          | INTEGER   | NULLABLE |               |
| page_name       | STRING    | NULLABLE |               |
| message         | STRING    | NULLABLE |               |
| sending_time    | TIMESTAMP | NULLABLE |               |
| price           | FLOAT     | NULLABLE |               |
| sent_count      | INTEGER   | NULLABLE |               |
| viewed_count    | INTEGER   | NULLABLE |               |
| purchased_count | FLOAT     | NULLABLE |               |
| earnings        | FLOAT     | NULLABLE |               |
| message_type    | STRING    | NULLABLE |               |
| caption_id      | INTEGER   | NULLABLE |               |

---

### 📊 TABLE: `mass_messages_stage`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.mass_messages_stage`
- **Created**: 2025-10-30 08:51:26 UTC
- **Last Modified**: 2025-10-30 08:54:26 UTC 🆕 Yesterday
- **Total Rows**: 132 | **Size**: 0.02 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟡 Good (91.3%)
      ██████████████████░░ 91.3%
    - **Field Completeness Analysis**:
      - `row_id`: 🟢 Excellent (100.0% complete, 132 unique values)
      - `page_name`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `message`: 🟢 Excellent (100.0% complete, 122 unique values)
      - `sending_time`: 🟢 Excellent (100.0% complete, 132 unique values)
      - `sent_count`: 🟢 Excellent (100.0% complete, 130 unique values)
  - **Sample Data** (showing 5 of 132 rows):
    ```
              row_id  page_name    message                                             sending_time               price      sent_count    viewed_count    purchased_count
--------------------  -----------  --------------------------------------------------  -------------------------  -------  ------------  --------------  -----------------
-5996396979981365577  mayahill     i have a VERY exciting stream planned for tonightt  2025-10-26 02:23:00+00:00  NULL            47099             874                  0
 7745489918345142008  mayahill     are you busy rn? 👀 i want to take all this offf     2025-10-26 01:02:00+00:00  NULL            46958            1066                  0
 7572214810510380285  mayahill     I’ve been craving your attention so bad lately, ba  2025-10-25 22:59:00+00:00  NULL            47108             662                  0
 6605719552083774943  mayahill     Do you want to find the hero's weakness, baby? 😉🙈   2025-10-24 20:35:00+00:00  NULL            47263             601                  0
-2251850460988218797  mayahill     doggy or missionary, let me know which one is your  2025-10-24 12:52:00+00:00  NULL            43690             758                  0
    ```
- **Schema** (10 columns):
| Name            | Type      | Mode     | Description   |
|-----------------|-----------|----------|---------------|
| row_id          | INTEGER   | NULLABLE |               |
| page_name       | STRING    | NULLABLE |               |
| message         | STRING    | NULLABLE |               |
| sending_time    | TIMESTAMP | NULLABLE |               |
| price           | FLOAT     | NULLABLE |               |
| sent_count      | INTEGER   | NULLABLE |               |
| viewed_count    | INTEGER   | NULLABLE |               |
| purchased_count | FLOAT     | NULLABLE |               |
| earnings        | FLOAT     | NULLABLE |               |
| message_type    | STRING    | NULLABLE |               |

---

### 👁️ VIEW: `performance_summary_7d`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.performance_summary_7d`
- **Created**: 2025-10-28 13:10:20 UTC
- **Last Modified**: 2025-10-28 13:10:20 UTC 📅 This Week
- **View Query**:
```sql
WITH recent_messages AS (
  SELECT
    page_name,
    sending_time,
    price,
    sent_count,
    viewed_count,
    purchased_count,
    earnings,
    message_type,
    `of-scheduler-proj.eros_scheduling_brain`.la_date(sending_time) as send_date_la,
    `of-scheduler-proj.eros_scheduling_brain`.la_hour(sending_time) as send_hour_la,
    `of-scheduler-proj.eros_scheduling_brain`.la_dayofweek(sending_time) as day_of_week_la
  FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`
  WHERE sending_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND sending_time < CURRENT_TIMESTAMP()
)
SELECT
  page_name,
  -- Volume metrics
  COUNT(*) as total_messages,
  COUNTIF(message_type = 'PPV') as ppv_count,
  COUNTIF(message_type = 'Bump') as bump_count,

  -- Performance metrics (aggregated)
  SAFE_DIVIDE(SUM(purchased_count), SUM(sent_count)) as conversion_rate,
  SAFE_DIVIDE(SUM(viewed_count), SUM(sent_count)) as unlock_rate,
  SUM(earnings) as total_revenue,
  SAFE_DIVIDE(SUM(earnings), COUNTIF(message_type = 'PPV')) as avg_revenue_per_ppv,

  -- Account size
  MAX(sent_count) as max_sent_count,
  CASE
    WHEN MAX(sent_count) < 10000 THEN 'small'
    WHEN MAX(sent_count) >= 10000 AND MAX(sent_count) < 50000 THEN 'medium'
    WHEN MAX(sent_count) >= 50000 AND MAX(sent_count) < 100000 THEN 'large'
    ELSE 'very_large'
  END as account_size_tier,

  -- Date range
  MIN(send_date_la) as first_date,
  MAX(send_date_la) as last_date
FROM recent_messages
GROUP BY page_name
```
- **Schema** (12 columns):
| Name                | Type    | Mode     | Description   |
|---------------------|---------|----------|---------------|
| page_name           | STRING  | NULLABLE |               |
| total_messages      | INTEGER | NULLABLE |               |
| ppv_count           | INTEGER | NULLABLE |               |
| bump_count          | INTEGER | NULLABLE |               |
| conversion_rate     | FLOAT   | NULLABLE |               |
| unlock_rate         | FLOAT   | NULLABLE |               |
| total_revenue       | FLOAT   | NULLABLE |               |
| avg_revenue_per_ppv | FLOAT   | NULLABLE |               |
| max_sent_count      | INTEGER | NULLABLE |               |
| account_size_tier   | STRING  | NULLABLE |               |
| first_date          | DATE    | NULLABLE |               |
| last_date           | DATE    | NULLABLE |               |

---

### 👁️ VIEW: `recent_caption_usage_v`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.recent_caption_usage_v`
- **Created**: 2025-10-30 06:57:54 UTC
- **Last Modified**: 2025-10-30 06:57:54 UTC 🆕 Yesterday
- **View Query**:
```sql
SELECT
        CAST(NULL AS STRING) AS page_name,
        CAST(NULL AS STRING) AS caption_id,
        CAST(NULL AS TIMESTAMP) AS last_used_at,
        CAST(NULL AS INT64) AS usage_count,
        CAST(NULL AS INT64) AS days_since_last_use
      FROM (SELECT 1) WHERE FALSE
```
- **Schema** (5 columns):
| Name                | Type      | Mode     | Description   |
|---------------------|-----------|----------|---------------|
| page_name           | STRING    | NULLABLE |               |
| caption_id          | STRING    | NULLABLE |               |
| last_used_at        | TIMESTAMP | NULLABLE |               |
| usage_count         | INTEGER   | NULLABLE |               |
| days_since_last_use | INTEGER   | NULLABLE |               |

---

### 👁️ VIEW: `recommendation_analytics`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.recommendation_analytics`
- **Created**: 2025-10-29 05:41:23 UTC
- **Last Modified**: 2025-10-29 05:41:23 UTC 📅 This Week
- **View Query**:
```sql
SELECT
  DATE(generated_at) as generation_date,
  page_name,
  COUNT(*) as recommendations_generated,
  AVG(confidence_score) as avg_confidence,
  AVG(uniqueness_score) as avg_uniqueness,
  AVG(caption_quality_score) as avg_caption_quality,
  SUM(CASE WHEN status = "imported" THEN 1 ELSE 0 END) as imported_count,
  SUM(CASE WHEN status = "rejected" THEN 1 ELSE 0 END) as rejected_count,
  SUM(CASE WHEN status = "pending" THEN 1 ELSE 0 END) as pending_count,
  STRING_AGG(DISTINCT schedule_id) as schedule_ids
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations`
WHERE created_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```
- **Schema** (10 columns):
| Name                      | Type    | Mode     | Description   |
|---------------------------|---------|----------|---------------|
| generation_date           | DATE    | NULLABLE |               |
| page_name                 | STRING  | NULLABLE |               |
| recommendations_generated | INTEGER | NULLABLE |               |
| avg_confidence            | FLOAT   | NULLABLE |               |
| avg_uniqueness            | FLOAT   | NULLABLE |               |
| avg_caption_quality       | FLOAT   | NULLABLE |               |
| imported_count            | INTEGER | NULLABLE |               |
| rejected_count            | INTEGER | NULLABLE |               |
| pending_count             | INTEGER | NULLABLE |               |
| schedule_ids              | STRING  | NULLABLE |               |

---

### 📊 TABLE: `schedule_recommendations`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.schedule_recommendations`
- **Created**: 2025-10-29 05:34:22 UTC
- **Last Modified**: 2025-10-29 05:41:58 UTC 📅 This Week
- **Total Rows**: 4 | **Size**: 0.03 MB 📄 Tiny
  - **Data Quality Metrics**:
    - Overall Completeness: 🟠 Fair (75.0%)
      ███████████████░░░░░ 75.0%
    - **Field Completeness Analysis**:
      - `recommendation_id`: 🟢 Excellent (100.0% complete, 4 unique values)
      - `page_name`: 🟢 Excellent (100.0% complete, 1 unique values)
      - `schedule_id`: 🟢 Excellent (100.0% complete, 3 unique values)
      - `generated_at`: 🟢 Excellent (100.0% complete, 4 unique values)
      - `confidence_score`: 🟢 Excellent (100.0% complete, 3 unique values)
  - **Sample Data** (showing 4 of 4 rows):
    ```
recommendation_id                     page_name    schedule_id      generated_at                      imported_at                       updated_at                        recommendation_data                                   confidence_score
------------------------------------  -----------  ---------------  --------------------------------  --------------------------------  --------------------------------  --------------------------------------------------  ------------------
abde5992-47f0-4d20-9536-abb5a1dd912c  del          #1A-20251028-v2  2025-10-28 09:08:29.997978+00:00  NULL                              NULL                              {"import_instructions":{"google_sheets":{"creator_                0.82
911690e8-67bc-4b06-a7ff-862219edbf81  del          #1A              2025-10-28 01:09:37.782753+00:00  2025-10-28 09:14:55.627226+00:00  2025-10-28 09:14:55.627226+00:00  {"configuration_recommendations":{"crisis_mode":"A                0.82
53b0723a-e69a-468e-be83-81c5db63eb2e  del          #1A-20251028     2025-10-28 12:07:07.619435+00:00  NULL                              NULL                              {"caption_analytics":{"avg_performance_score":18.9                0.78
sched_#1A-20251028_1761652045         del          #1A-20251028     2025-10-28 05:47:25.873615+00:00  NULL                              NULL                              {"account_metrics":{"conversion_rate":0.0001,"fan_                0.75
    ```
- **Schema** (17 columns):
| Name                  | Type      | Mode     | Description   |
|-----------------------|-----------|----------|---------------|
| recommendation_id     | STRING    | NULLABLE |               |
| page_name             | STRING    | NULLABLE |               |
| schedule_id           | STRING    | NULLABLE |               |
| generated_at          | TIMESTAMP | NULLABLE |               |
| imported_at           | TIMESTAMP | NULLABLE |               |
| updated_at            | TIMESTAMP | NULLABLE |               |
| recommendation_data   | JSON      | NULLABLE |               |
| confidence_score      | FLOAT     | NULLABLE |               |
| uniqueness_score      | FLOAT     | NULLABLE |               |
| caption_quality_score | FLOAT     | NULLABLE |               |
| status                | STRING    | NULLABLE |               |
| import_result         | STRING    | NULLABLE |               |
| generated_by          | STRING    | NULLABLE |               |
| imported_by           | STRING    | NULLABLE |               |
| created_date          | DATE      | NULLABLE |               |
| notes                 | STRING    | NULLABLE |               |
| version               | STRING    | NULLABLE |               |

---

### 👁️ VIEW: `schedule_recommendations_messages`
- **Full ID**: `of-scheduler-proj:eros_scheduling_brain.schedule_recommendations_messages`
- **Created**: 2025-10-29 09:55:42 UTC
- **Last Modified**: 2025-10-29 09:55:42 UTC 📅 This Week
- **View Query**:
```sql
SELECT
  r.page_name,
  r.schedule_id,
  TIMESTAMP(JSON_VALUE(m, '$.send_at'))                                 AS send_at,
  JSON_VALUE(m, '$.message_type')                                       AS message_type,
  JSON_VALUE(m, '$.schedule_type')                                      AS schedule_type,
  JSON_VALUE(m, '$.caption')                                            AS caption,
  CAST(JSON_VALUE(m, '$.recommended_price') AS FLOAT64)                 AS recommended_price,
  JSON_VALUE(m, '$.caption_id')                                         AS caption_id,
  SAFE_CAST(JSON_VALUE(m, '$.row_number') AS INT64)                     AS row_number,
  r.generated_at,
  r.updated_at
FROM `of-scheduler-proj.eros_scheduling_brain.schedule_recommendations` r,
UNNEST(JSON_EXTRACT_ARRAY(r.recommendation_data, '$.messages')) AS m
```
- **Schema** (11 columns):
| Name              | Type      | Mode     | Description   |
|-------------------|-----------|----------|---------------|
| page_name         | STRING    | NULLABLE |               |
| schedule_id       | STRING    | NULLABLE |               |
| send_at           | TIMESTAMP | NULLABLE |               |
| message_type      | STRING    | NULLABLE |               |
| schedule_type     | STRING    | NULLABLE |               |
| caption           | STRING    | NULLABLE |               |
| recommended_price | FLOAT     | NULLABLE |               |
| caption_id        | STRING    | NULLABLE |               |
| row_number        | INTEGER   | NULLABLE |               |
| generated_at      | TIMESTAMP | NULLABLE |               |
| updated_at        | TIMESTAMP | NULLABLE |               |

---

- No ML models found in the dataset.
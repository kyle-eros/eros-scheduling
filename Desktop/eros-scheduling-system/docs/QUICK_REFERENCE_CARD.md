# BigQuery Infrastructure - Quick Reference Card

**Project:** of-scheduler-proj
**Dataset:** eros_scheduling_brain
**Status:** PRODUCTION READY

---

## Essential Queries

### Check Data Freshness
```sql
SELECT
  COUNT(*) as message_count,
  MAX(DATE(sending_time)) as latest_data,
  DATE_DIFF(CURRENT_DATE(), MAX(DATE(sending_time)), DAY) as days_old
FROM `of-scheduler-proj.eros_scheduling_brain.mass_messages`;
```

### Check Caption Pool Health
```sql
SELECT
  price_tier,
  COUNT(*) as available_count
FROM `of-scheduler-proj.eros_scheduling_brain.available_captions`
GROUP BY price_tier
ORDER BY price_tier;
```

### Check Feature Flags
```sql
SELECT flag, is_enabled, updated_at
FROM `of-scheduler-proj.eros_scheduling_brain.feature_flags`
WHERE flag = 'caption_restrictions_enabled';
```

---

## Key Tables

| Table | Purpose |
|-------|---------|
| **mass_messages** | Historical message data |
| **caption_bank** | Shared caption pool |
| **active_caption_assignments** | Caption locking |
| **schedule_recommendations** | Generated schedules |
| **active_creators** | Creator status |

---

## Key Views

| View | Purpose |
|-----|---------|
| **available_captions** | Pre-filtered captions |
| **latest_recommendations** | Most recent schedules |
| **active_creator_caption_restrictions_v** | Active restrictions |
| **creator_allowed_profile_v** | Allowed profiles |

---

## Feature Flags

### Check Caption Restrictions Flag
```sql
SELECT flag, is_enabled, updated_at
FROM `of-scheduler-proj.eros_scheduling_brain.feature_flags`
WHERE flag = 'caption_restrictions_enabled';
```

### Enable Feature Flag
```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.feature_flags`
SET is_enabled = true, updated_at = CURRENT_TIMESTAMP()
WHERE flag = 'caption_restrictions_enabled';
```

### Disable Feature Flag (Emergency)
```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.feature_flags`
SET is_enabled = false, updated_at = CURRENT_TIMESTAMP()
WHERE flag = 'caption_restrictions_enabled';
```

---

## Emergency Commands

### Emergency Disable All Restrictions
```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET is_active = FALSE WHERE is_active = TRUE;
```

### Emergency Enable All Restrictions
```sql
UPDATE `of-scheduler-proj.eros_scheduling_brain.caption_restrictions`
SET is_active = TRUE WHERE is_active = FALSE;
```

---

## Environment Variables

```bash
export PROJECT_ID="of-scheduler-proj"
export DATASET="eros_scheduling_brain"
export PAGE_NAME="jadebri"
export SCHEDULE_ID="schedule_2025-10-31_v1"
export LOCATION="US"
```

---

## Troubleshooting

### Table Not Found
```bash
bq ls of-scheduler-proj:eros_scheduling_brain
bq show of-scheduler-proj:eros_scheduling_brain.table_name
```

### Permission Denied
```bash
gcloud auth list
gcloud auth application-default login
./scripts/validate_iam.sh
```

---

**Version:** 1.0
**Last Updated:** October 31, 2025

# TVF Agent #3 Quick Start Guide

**Deployment Date:** 2025-10-31
**Status:** All 3 TVFs DEPLOYED and OPERATIONAL
**Project:** of-scheduler-proj / eros_scheduling_brain

---

## Quick Reference Card

### TVF #1: analyze_day_patterns
**Find best days to send messages**

```sql
SELECT
  CASE day_of_week_la
    WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday'
    WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday'
    ELSE 'Saturday' END AS day,
  n, ROUND(avg_rpr * 1000000, 2) AS rpr_per_1m,
  CASE WHEN rpr_stat_sig THEN 'SIGNIFICANT' ELSE 'NOT_SIG' END AS sig
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('page_name', 90)
ORDER BY avg_rpr DESC;
```

**Returns:** 7 rows (Sun-Sat) with RPR, conversion, t-statistic, significance flag

---

### TVF #2: analyze_time_windows
**Find best hours to send messages**

```sql
SELECT
  day_type, hour_la, n,
  ROUND(avg_rpr * 1000000, 2) AS rpr_per_1m,
  confidence
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('page_name', 90)
WHERE confidence IN ('HIGH_CONF', 'MED_CONF')
ORDER BY avg_rpr DESC LIMIT 10;
```

**Returns:** Up to 48 rows (24 hours × Weekday/Weekend) with confidence scoring

---

### TVF #3: calculate_saturation_score
**Check account messaging saturation risk**

```sql
SELECT
  saturation_score, risk_level,
  CONCAT('Score: ', ROUND(saturation_score, 2), ' - ', recommended_action) AS action
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('page_name', 'LARGE');
```

**Returns:** 1 row with saturation assessment, risk level, and volume recommendations
- Risk: HIGH (>=0.6) = Cut 30%, MEDIUM (0.3-0.6) = Cut 15%, LOW (<0.3) = No change

---

## Integration Pattern: Optimal Scheduling

Combine all three TVFs for complete strategy:

```sql
-- Get best day-hour combinations accounting for saturation
WITH saturation AS (
  SELECT volume_adjustment_factor FROM
    `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('itskassielee_paid', 'LARGE')
),
day_perf AS (
  SELECT day_of_week_la,
    CASE day_of_week_la WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday'
      WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday' ELSE 'Saturday' END day_name,
    ROUND(avg_rpr, 6) rpr, rpr_stat_sig
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('itskassielee_paid', 90)
),
hour_perf AS (
  SELECT day_type, hour_la,
    ROUND(avg_rpr, 6) rpr, confidence,
    ROW_NUMBER() OVER (PARTITION BY day_type ORDER BY avg_rpr DESC) rk
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('itskassielee_paid', 90)
)
SELECT
  d.day_name, h.hour_la,
  ROUND((d.rpr + h.rpr) * 1000000, 2) combined_rpr_per_1m,
  CASE
    WHEN d.rpr_stat_sig AND h.confidence = 'HIGH_CONF' THEN 'PRIME SLOT'
    WHEN h.confidence = 'HIGH_CONF' THEN 'GOOD SLOT'
    ELSE 'MONITOR' END slot_quality,
  CONCAT('Use ', ROUND(s.volume_adjustment_factor * 100, 0), '% volume') action
FROM day_perf d
CROSS JOIN hour_perf h
LEFT JOIN saturation s ON TRUE
WHERE (h.day_type = 'Weekday' AND d.day_of_week_la NOT IN (1,7)
    OR h.day_type = 'Weekend' AND d.day_of_week_la IN (1,7))
  AND h.rk <= 5
ORDER BY combined_rpr_per_1m DESC;
```

---

## Function Parameters

| Parameter | Type | Example | Notes |
|-----------|------|---------|-------|
| p_page_name | STRING | 'itskassielee_paid' | Creator page/account name |
| p_lookback_days | INT64 | 7, 30, 90 | Analysis window (days) |
| p_account_size_tier | STRING | 'XL', 'LARGE', 'MEDIUM', 'SMALL' | Affects saturation weighting |

---

## Output Interpretation

### Day Patterns
- **rpr_stat_sig = true**: Day significantly outperforms baseline (95% confidence)
- **n**: Number of messages sent on this day
- **avg_rpr**: Average earnings per recipient sent to

### Time Windows
- **HIGH_CONF**: n >= 10 messages (reliable data)
- **MED_CONF**: n = 5-9 messages (moderate reliability)
- **LOW_CONF**: n < 5 messages (insufficient data)

### Saturation Score
- **HIGH (>=0.6)**: Account is over-saturated, cut volume 30%
- **MEDIUM (0.3-0.6)**: Approaching saturation, cut volume 15%
- **LOW (<0.3)**: Healthy saturation levels, no change needed

---

## Common Queries

### Q: Which are my top 3 sending windows?
```sql
SELECT day_type, hour_la, ROUND(avg_rpr * 1000000, 0) rpr
FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('your_page', 90)
WHERE confidence = 'HIGH_CONF'
ORDER BY avg_rpr DESC LIMIT 3;
```

### Q: Should I send less frequently?
```sql
SELECT CASE
  WHEN saturation_score >= 0.6 THEN 'YES - Cut 30% of messages'
  WHEN saturation_score >= 0.3 THEN 'YES - Cut 15% of messages'
  ELSE 'NO - Continue current volume' END advice
FROM `of-scheduler-proj.eros_scheduling_brain`.calculate_saturation_score('your_page', 'LARGE');
```

### Q: What's the total revenue impact of optimal scheduling?
```sql
WITH stats AS (
  SELECT 'DAY' type, AVG(avg_rpr) avg_rpr
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_day_patterns('your_page', 90)
  WHERE rpr_stat_sig = true
  UNION ALL
  SELECT 'HOUR', AVG(avg_rpr)
  FROM `of-scheduler-proj.eros_scheduling_brain`.analyze_time_windows('your_page', 90)
  WHERE confidence = 'HIGH_CONF'
)
SELECT
  MAX(CASE WHEN type='DAY' THEN avg_rpr END) best_day_rpr,
  MAX(CASE WHEN type='HOUR' THEN avg_rpr END) best_hour_rpr
FROM stats;
```

---

## File Locations

| File | Purpose |
|------|---------|
| deploy_tvf_agent3.sql | Deployment script (CREATE OR REPLACE) |
| test_tvf_agent3.sql | Comprehensive test suite (15+ tests) |
| TVF_AGENT3_REFERENCE.sql | Detailed usage guide (20+ examples) |
| TVF_AGENT3_DEPLOYMENT_SUMMARY.md | Complete technical documentation |
| TVF_QUICK_START_GUIDE.md | This quick reference |

---

## Testing Status

All TVFs deployed successfully:
- analyze_day_patterns: OPERATIONAL
- analyze_time_windows: OPERATIONAL
- calculate_saturation_score: OPERATIONAL

Latest test run: 2025-10-31
- Day patterns: 7 days analyzed, all tests PASS
- Time windows: 48 hour-slots analyzed, all tests PASS
- Saturation score: 4 tiers tested, all tests PASS

---

## Next Steps

1. **Identify Optimal Schedule**: Run analyze_day_patterns + analyze_time_windows
2. **Check Saturation**: Run calculate_saturation_score to get volume multiplier
3. **Adjust Volume**: Apply volume_adjustment_factor to planned message count
4. **Schedule Sends**: Use recommended day-hour combinations for best performance

---

## Support Resources

For detailed documentation, see:
- TVF_AGENT3_REFERENCE.sql (20+ example queries)
- TVF_AGENT3_DEPLOYMENT_SUMMARY.md (complete technical specs)

For quick answers, use queries above or contact the Agent #3 deployment team.

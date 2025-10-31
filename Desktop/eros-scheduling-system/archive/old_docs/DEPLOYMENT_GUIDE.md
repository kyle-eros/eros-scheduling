# EROS Platform v2 - Production Deployment Guide
*Staged Rollout Plan with Monitoring & Rollback Procedures*

## 🚀 Deployment Overview

This guide provides step-by-step instructions for deploying EROS Platform v2 to production with minimal risk through staged rollout, comprehensive monitoring, and instant rollback capability.

## 📋 Pre-Deployment Checklist

### ✅ Code Readiness
- [ ] All 6 agent files in `eros-platform-v2/agents/` directory
- [ ] Integration tests passing with >95% success rate
- [ ] BigQuery tables created and permissions set
- [ ] Apps Script deployed to Google Sheets
- [ ] Webhook endpoints configured

### ✅ Infrastructure Requirements
- [ ] BigQuery project with 100GB+ storage
- [ ] Google Sheets with Apps Script enabled
- [ ] Python 3.9+ environment
- [ ] API rate limits increased to 1000/min
- [ ] Monitoring dashboards configured

### ✅ Backup Procedures
- [ ] Current production code backed up
- [ ] Database snapshots taken
- [ ] Caption assignments exported
- [ ] Current schedules archived

## 📊 Stage 1: Canary Deployment (Day 1-3)

Deploy to 10% of creators (lowest risk profiles)

### Select Canary Creators
```sql
-- Select 10% of creators with stable metrics for canary
SELECT creator_name, account_size, avg_conversion_30d
FROM creator_metrics
WHERE saturation_status = 'GREEN'
  AND avg_conversion_30d > 0.03
  AND message_volume_variance < 0.2
ORDER BY account_value DESC
LIMIT CEIL(total_creators * 0.1);
```

### Deploy to Canary
```bash
# 1. Set environment to canary
export EROS_ENV=canary
export EROS_CREATORS=canary_list.txt

# 2. Deploy v2 agents
python deploy.py --stage canary --creators-file canary_list.txt

# 3. Enable monitoring
python monitor.py --stage canary --alert-threshold high
```

### Canary Success Metrics
- Conversion rate within 5% of baseline
- No RED saturation events
- Schedule generation < 20 minutes
- Zero critical errors
- Caption uniqueness 100%

### Canary Rollback Trigger
If ANY of these occur:
- Conversion drop > 10%
- Multiple RED saturations
- System errors > 5%
- Schedule generation fails

```bash
# Emergency rollback
python rollback.py --stage canary --restore v1
```

## 📈 Stage 2: Limited Rollout (Day 4-7)

Expand to 50% of creators

### Expand Deployment
```bash
# 1. Analyze canary metrics
python analyze_canary.py --min-days 3

# 2. If successful, expand to 50%
export EROS_ENV=limited
python deploy.py --stage limited --percent 50

# 3. Enable gradual migration
python migrate.py --source v1 --target v2 --rate 10_per_hour
```

### Limited Rollout Monitoring
```python
# Real-time monitoring script
import time
from monitoring import MetricsCollector

collector = MetricsCollector()

while True:
    metrics = collector.get_realtime_metrics()

    # Check thresholds
    if metrics['conversion_rate'] < BASELINE * 0.9:
        alert("Conversion drop detected!")

    if metrics['red_saturation_count'] > 2:
        alert("Multiple saturation events!")

    if metrics['error_rate'] > 0.02:
        alert("Error rate exceeding 2%!")

    time.sleep(300)  # Check every 5 minutes
```

## 🎯 Stage 3: Full Production (Day 8+)

Complete migration to v2

### Final Deployment
```bash
# 1. Final validation
python validate_deployment.py --check all

# 2. Full deployment
export EROS_ENV=production
python deploy.py --stage production --percent 100

# 3. Decommission v1 (keep for 30 days)
python decommission.py --version v1 --archive-days 30
```

## 📊 Monitoring Dashboard

### Key Metrics to Track

```sql
-- Real-time Performance Dashboard
CREATE OR REPLACE VIEW deployment_monitor AS
WITH v2_metrics AS (
  SELECT
    DATE(timestamp) as date,
    'v2' as version,
    COUNT(DISTINCT creator_name) as creators,
    AVG(conversion_rate) as avg_conversion,
    SUM(revenue) as total_revenue,
    COUNT(*) FILTER(WHERE saturation_status = 'RED') as red_count,
    AVG(schedule_generation_time) as avg_gen_time,

  FROM analytics.v2_performance
  WHERE timestamp > CURRENT_TIMESTAMP() - INTERVAL 7 DAY
  GROUP BY 1
),
v1_baseline AS (
  SELECT
    AVG(conversion_rate) as baseline_conversion,
    AVG(revenue) as baseline_revenue,
    AVG(schedule_generation_time) as baseline_gen_time
  FROM analytics.v1_performance
  WHERE date BETWEEN DATE_SUB(deployment_date, INTERVAL 30 DAY)
                  AND deployment_date
)
SELECT
  v2.*,
  v1.baseline_conversion,
  (v2.avg_conversion - v1.baseline_conversion) / v1.baseline_conversion * 100 as conversion_change_pct,
  (v2.total_revenue - v1.baseline_revenue) / v1.baseline_revenue * 100 as revenue_change_pct,

  -- Alert flags
  CASE
    WHEN v2.avg_conversion < v1.baseline_conversion * 0.9 THEN 'ALERT'
    WHEN v2.avg_conversion < v1.baseline_conversion * 0.95 THEN 'WARNING'
    ELSE 'OK'
  END as conversion_status,

  CASE
    WHEN v2.red_count > 3 THEN 'ALERT'
    WHEN v2.red_count > 1 THEN 'WARNING'
    ELSE 'OK'
  END as saturation_status,

  CASE
    WHEN v2.avg_gen_time > 1200 THEN 'ALERT'  -- >20 min
    WHEN v2.avg_gen_time > 900 THEN 'WARNING'  -- >15 min
    ELSE 'OK'
  END as performance_status

FROM v2_metrics v2
CROSS JOIN v1_baseline v1
ORDER BY date DESC;
```

### Automated Alerts

```python
# alert_system.py
class DeploymentAlertSystem:
    def __init__(self):
        self.alert_thresholds = {
            'conversion_drop': 0.10,  # 10% drop
            'revenue_drop': 0.15,      # 15% drop
            'red_saturation': 3,        # 3+ RED creators
            'generation_time': 1200,    # 20 minutes
            'error_rate': 0.05          # 5% errors
        }

    def check_alerts(self):
        metrics = self.get_current_metrics()
        alerts = []

        # Check each threshold
        if metrics['conversion_change'] < -self.alert_thresholds['conversion_drop']:
            alerts.append({
                'level': 'CRITICAL',
                'message': f"Conversion dropped {abs(metrics['conversion_change']):.1%}",
                'action': 'Consider rollback'
            })

        if metrics['red_count'] > self.alert_thresholds['red_saturation']:
            alerts.append({
                'level': 'HIGH',
                'message': f"{metrics['red_count']} creators in RED saturation",
                'action': 'Reduce messaging volume'
            })

        return alerts
```

## 🔄 Rollback Procedures

### Automatic Rollback Triggers
```python
# Auto-rollback on critical metrics
if (conversion_rate < baseline * 0.85 or
    error_rate > 0.10 or
    red_saturation_count > 5):

    print("CRITICAL: Initiating automatic rollback!")
    execute_rollback()
```

### Manual Rollback Steps
```bash
# 1. Stop v2 orchestrator
systemctl stop eros-orchestrator-v2

# 2. Restore v1 code
git checkout v1-stable
python restore_backup.py --version v1

# 3. Clear v2 schedules
python clear_schedules.py --version v2 --preserve-history

# 4. Restart v1 orchestrator
systemctl start eros-orchestrator-v1

# 5. Verify rollback
python verify_rollback.py --check all
```

## 📝 Post-Deployment Tasks

### Week 1
- [ ] Daily performance reviews at 9am, 2pm, 6pm
- [ ] Check all alert channels every 2 hours
- [ ] Review failed schedules and retry
- [ ] Collect user feedback

### Week 2
- [ ] Analyze performance trends
- [ ] Optimize based on learnings
- [ ] Document any issues
- [ ] Plan v2.1 improvements

### Week 3+
- [ ] Weekly performance reports
- [ ] Monthly optimization review
- [ ] Quarterly strategy assessment

## 🛠️ Troubleshooting Guide

### Common Issues & Solutions

#### Issue: High Caption Duplication
```sql
-- Check for duplicate captions
SELECT caption_id, COUNT(*) as usage_count
FROM active_caption_assignments
WHERE is_active = TRUE
GROUP BY caption_id
HAVING COUNT(*) > 1;
```
**Solution**: Run caption deduplication script
```bash
python fix_captions.py --deduplicate --reassign
```

#### Issue: Schedule Generation Timeout
```python
# Increase timeout and reduce batch size
orchestrator.timeout = 3600  # 1 hour
orchestrator.batch_size = 3  # Process 3 creators at a time
```

#### Issue: RED Saturation Spike
```sql
-- Identify affected creators
SELECT creator_name, saturation_status, last_message_time
FROM realtime_performance
WHERE saturation_status = 'RED'
ORDER BY exhaustion_score DESC;
```
**Solution**: Implement immediate cooling
```python
for creator in red_creators:
    pause_ppv(creator, hours=48)
    send_photo_bumps_only(creator)
```

## 📞 Emergency Contacts

- **Technical Lead**: [Your Name] - [Phone]
- **Database Admin**: [DBA Name] - [Phone]
- **On-Call Engineer**: [Engineer] - [Phone]
- **Escalation**: [Manager] - [Phone]

## ✅ Deployment Verification

Run final verification after full deployment:

```python
# deployment_verification.py
def verify_deployment():
    checks = {
        'All agents deployed': check_agent_deployment(),
        'BigQuery tables created': check_bigquery_tables(),
        'Apps Script installed': check_apps_script(),
        'Monitoring active': check_monitoring(),
        'Alerts configured': check_alerts(),
        'Backup available': check_backup(),
        'Documentation updated': check_docs()
    }

    failed = [k for k, v in checks.items() if not v]

    if failed:
        print(f"❌ Deployment incomplete: {failed}")
        return False
    else:
        print("✅ Deployment verified successfully!")
        return True

if __name__ == "__main__":
    if verify_deployment():
        print("\n🎉 EROS Platform v2 is LIVE!")
        print("Monitor dashboard: https://your-dashboard-url")
    else:
        print("\n⚠️ Complete failed checks before going live")
```

## 🎯 Success Metrics (Target after 30 days)

- **Conversion Rate**: +15% improvement
- **Revenue**: +20% increase
- **Saturation Events**: -50% reduction
- **Schedule Generation**: 3x faster (15min vs 45min)
- **Caption Uniqueness**: 100% (no duplicates)
- **System Uptime**: 99.9%

## 📅 Deployment Timeline

| Day | Stage | Actions | Success Criteria |
|-----|-------|---------|------------------|
| 1-3 | Canary | Deploy to 10% | No critical issues |
| 4-7 | Limited | Expand to 50% | Metrics within 5% |
| 8-10 | Production | Deploy to 100% | All metrics green |
| 11-30 | Monitoring | Daily reviews | Continuous improvement |
| 31+ | Optimization | Weekly updates | Revenue growth |

---

**Remember**: Move slowly, monitor constantly, and rollback immediately if metrics degrade. The goal is zero-downtime deployment with improved performance.
# Pre-Deployment Checklist - EROS Scheduling System

## Overview
This checklist ensures safe, systematic deployment of EROS Scheduling System enhancements including critical bug fixes and performance optimizations.

**Deployment Date:** _________________
**Deployment Lead:** _________________
**Backup Location:** gs://eros-platform-backups/YYYY-MM-DD_HHMMSS/

---

## Phase 0: Pre-Deployment Preparation

### 1. Team Notification (T-24 hours)

**Email Template:**
```
Subject: EROS Scheduling System Deployment - [DATE] at [TIME]

Team,

We will be deploying EROS Scheduling System enhancements on [DATE] at [TIME UTC].

Deployment Window: [START_TIME] - [END_TIME] (Estimated 2 hours)

Changes Include:
- Phase 1: Critical bug fixes (Wilson Score, Thompson Sampling, Caption Locking, SQL Injection)
- Phase 2: Performance optimizations (Feedback Loop, Account Classification, Query Timeouts)

Expected Impact:
- No downtime expected
- Improved caption distribution accuracy
- Enhanced system performance and reliability
- Better cost management through query optimizations

Rollback Plan: Automated rollback available if issues detected

Point of Contact: [DEPLOYMENT_LEAD_NAME] - [EMAIL] - [PHONE]

Thank you,
EROS Scheduling System Team
```

### 2. Stakeholder Sign-Off

- [ ] Product Owner approval received
- [ ] Technical Lead approval received
- [ ] Database Administrator notified
- [ ] On-call engineer identified and briefed
- [ ] Rollback authority designated

### 3. Environment Verification

- [ ] BigQuery project ID confirmed: `________________`
- [ ] Dataset name confirmed: `________________`
- [ ] Service account has necessary permissions
- [ ] `bq` CLI installed and authenticated: `bq show`
- [ ] Backup storage bucket exists: `gsutil ls gs://eros-platform-backups/`
- [ ] Network connectivity to BigQuery verified

### 4. Pre-Deployment Testing

- [ ] All deployment scripts tested in staging environment
- [ ] Backup script verified in staging
- [ ] Rollback script tested in staging
- [ ] Validation queries prepared and tested
- [ ] Performance benchmarks captured for comparison

---

## Phase 1: Backup Procedures

### Critical Tables to Backup

1. **caption_bank** - Master caption repository
2. **caption_bandit_stats** - Performance tracking data
3. **active_caption_assignments** - Current caption assignments

### Backup Execution

**Script:** `./backup_tables.sh`

**Pre-Backup Checklist:**
- [ ] Backup storage location verified: `gs://eros-platform-backups/`
- [ ] Storage quota checked (ensure sufficient space)
- [ ] Backup retention policy confirmed (90 days recommended)
- [ ] Previous backups verified as restorable

**Backup Command:**
```bash
cd /Users/kylemerriman/Desktop/new\ agent\ setup/eros-scheduling-system/deployment
./backup_tables.sh
```

**Post-Backup Verification:**
- [ ] Backup completion confirmed
- [ ] Backup file sizes reasonable (compare to previous backups)
- [ ] Backup metadata recorded:
  ```
  Backup Timestamp: _______________
  caption_bank rows: _______________
  caption_bandit_stats rows: _______________
  active_caption_assignments rows: _______________
  Total backup size: _______________
  ```
- [ ] Backup location saved for rollback: `________________`

---

## Phase 2: Pre-Deployment Validation

### Database Health Checks

Run these queries before deployment:

```sql
-- 1. Verify table row counts
SELECT
  'caption_bank' as table_name,
  COUNT(*) as row_count,
  COUNT(DISTINCT caption_id) as unique_captions
FROM `caption_bank`;

SELECT
  'caption_bandit_stats' as table_name,
  COUNT(*) as row_count,
  COUNT(DISTINCT caption_id) as unique_captions
FROM `caption_bandit_stats`;

SELECT
  'active_caption_assignments' as table_name,
  COUNT(*) as row_count,
  COUNT(DISTINCT account_id) as unique_accounts
FROM `active_caption_assignments`;

-- 2. Verify no data corruption
SELECT
  caption_id,
  total_views,
  engagement_count,
  wilson_score_lower_bound
FROM `caption_bandit_stats`
WHERE total_views < 0
   OR engagement_count < 0
   OR wilson_score_lower_bound NOT BETWEEN 0 AND 1
LIMIT 10;

-- 3. Check for active scheduled queries
-- (Run via Cloud Console or gcloud command)
```

**Validation Checklist:**
- [ ] Row counts match expected values
- [ ] No data corruption detected
- [ ] No orphaned records found
- [ ] All foreign key relationships intact
- [ ] Scheduled queries identified and documented

### System Performance Baseline

Capture baseline metrics for comparison:

- [ ] Average query execution time: `____________ seconds`
- [ ] Average caption selection time: `____________ ms`
- [ ] Current BigQuery slot usage: `____________`
- [ ] Daily query cost: `$____________`
- [ ] Caption distribution effectiveness: `____________%`

---

## Phase 3: Deployment Execution

### Phase 1 Deployment (Critical Fixes)

**Script:** `./deploy_phase1.sh`

**Deployment Steps:**
1. [ ] Execute Phase 1 deployment script
   ```bash
   ./deploy_phase1.sh
   ```
2. [ ] Monitor deployment output for errors
3. [ ] Record deployment start time: `________________`
4. [ ] Record deployment end time: `________________`

**Post-Phase 1 Validation:**
- [ ] Wilson Score calculations verified (check values between 0-1)
- [ ] Thompson Sampling queries return valid results
- [ ] Caption locking prevents duplicate assignments
- [ ] SQL injection protection active (test with sample inputs)
- [ ] No errors in deployment log
- [ ] All validation tests passed

**Phase 1 Sign-Off:**
- [ ] Deployment Lead: _________________ Time: _______
- [ ] QA Verification: _________________ Time: _______

### Phase 2 Deployment (Performance Optimization)

**Script:** `./deploy_phase2.sh`

**Deployment Steps:**
1. [ ] Execute Phase 2 deployment script
   ```bash
   ./deploy_phase2.sh
   ```
2. [ ] Monitor deployment output for errors
3. [ ] Record deployment start time: `________________`
4. [ ] Record deployment end time: `________________`

**Post-Phase 2 Validation:**
- [ ] Performance feedback loop optimization active
- [ ] Account size classification working correctly
- [ ] Query timeouts configured (60s for most queries)
- [ ] Performance improvements measured and documented

**Performance Comparison:**
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Avg Query Time | ____s | ____s | ___% |
| Caption Selection Time | ____ms | ____ms | ___% |
| Daily Query Cost | $____ | $____ | ___% |
| Slot Usage | ____ | ____ | ___% |

**Phase 2 Sign-Off:**
- [ ] Deployment Lead: _________________ Time: _______
- [ ] Performance verified: _________________ Time: _______

---

## Phase 4: Post-Deployment Monitoring

### Immediate Post-Deployment (0-2 hours)

**Monitor every 15 minutes:**
- [ ] Error rate in application logs
- [ ] Query execution times
- [ ] Caption assignment success rate
- [ ] User-reported issues
- [ ] BigQuery slot usage and costs

**Health Check Queries:**
```bash
# Run monitoring queries
bq query --use_legacy_sql=false < monitor_deployment.sql
```

**Critical Metrics to Watch:**
- [ ] No increase in error rates
- [ ] Query performance improved or stable
- [ ] Caption distribution working correctly
- [ ] No user complaints or issues reported

### Short-term Monitoring (2-24 hours)

**Monitor every 2 hours:**
- [ ] EMV improvement trends
- [ ] Caption engagement rates
- [ ] System stability
- [ ] Cost tracking

**Daily Health Check Schedule:**
- [ ] Morning check (09:00 UTC): Review overnight metrics
- [ ] Afternoon check (15:00 UTC): Review business hours performance
- [ ] Evening check (21:00 UTC): Review daily summary

### Long-term Monitoring (1-7 days)

**Daily Reviews:**
- [ ] Day 1: Comprehensive metrics review
- [ ] Day 2: Performance trend analysis
- [ ] Day 3: Cost optimization review
- [ ] Day 7: Full deployment success evaluation

**Success Criteria:**
- [ ] 95%+ query success rate
- [ ] <5% increase in query costs
- [ ] 10%+ improvement in EMV (Expected Monetary Value)
- [ ] Zero critical bugs reported
- [ ] Zero data integrity issues

---

## Phase 5: Rollback Procedures

### Rollback Decision Criteria

**Execute rollback if ANY of the following occur:**
1. Critical bug causing data corruption
2. Query failure rate >10%
3. System performance degradation >50%
4. Cost increase >25%
5. Security vulnerability introduced
6. Unrecoverable error in deployment

### Emergency Rollback Procedure

**Script:** `./rollback.sh`

**Rollback Steps:**
1. [ ] Declare rollback decision - Time: `________________`
2. [ ] Notify all stakeholders immediately (use template below)
3. [ ] Execute rollback script:
   ```bash
   ./rollback.sh [BACKUP_TIMESTAMP]
   ```
4. [ ] Verify rollback completion
5. [ ] Validate system restored to previous state
6. [ ] Monitor system for 2 hours post-rollback
7. [ ] Schedule post-mortem meeting

**Rollback Notification Template:**
```
Subject: URGENT - EROS Scheduling System Rollback Initiated

Team,

A rollback of the EROS Scheduling System deployment has been initiated.

Rollback Time: [TIME]
Reason: [BRIEF_REASON]

Actions Taken:
- Deployment stopped
- System restored to pre-deployment state from backup
- All scheduled jobs disabled pending investigation

Expected Recovery Time: [ESTIMATED_TIME]

Investigation Status: [IN_PROGRESS/PENDING]

Point of Contact: [DEPLOYMENT_LEAD_NAME] - [EMAIL] - [PHONE]

Updates will be provided every 30 minutes.

EROS Platform Team
```

**Post-Rollback Verification:**
- [ ] All tables restored to backup state
- [ ] Row counts match pre-deployment counts
- [ ] System functionality verified
- [ ] Users notified of restoration
- [ ] Incident report created
- [ ] Root cause analysis scheduled

---

## Phase 6: Deployment Sign-Off

### Final Verification

- [ ] All deployment phases completed successfully
- [ ] All validation tests passed
- [ ] Performance improvements confirmed
- [ ] No critical issues detected
- [ ] Monitoring dashboards updated
- [ ] Documentation updated
- [ ] Team debriefing completed

### Deployment Success Confirmation

**Deployment Lead Sign-Off:**
- Name: _________________
- Date: _________________
- Time: _________________
- Status: SUCCESS / ROLLBACK REQUIRED

**Technical Lead Sign-Off:**
- Name: _________________
- Date: _________________
- Time: _________________
- Notes: _________________

**Product Owner Sign-Off:**
- Name: _________________
- Date: _________________
- Time: _________________
- Notes: _________________

---

## Phase 7: Post-Deployment Activities

### Documentation Updates

- [ ] Update system architecture documentation
- [ ] Update API documentation if applicable
- [ ] Update runbook with new procedures
- [ ] Document lessons learned
- [ ] Update deployment playbook

### Knowledge Transfer

- [ ] Brief support team on changes
- [ ] Update on-call runbook
- [ ] Share performance improvements with stakeholders
- [ ] Document troubleshooting procedures

### Continuous Improvement

- [ ] Review deployment process for improvements
- [ ] Update automation scripts based on experience
- [ ] Identify opportunities for better monitoring
- [ ] Plan next deployment cycle improvements

---

## Emergency Contacts

**Deployment Team:**
- Deployment Lead: _________________ - _________________
- Technical Lead: _________________ - _________________
- Database Admin: _________________ - _________________
- On-Call Engineer: _________________ - _________________

**Escalation Path:**
1. Deployment Lead (immediate issues)
2. Technical Lead (technical decisions)
3. Engineering Manager (escalation required)
4. CTO (critical business impact)

**External Resources:**
- Google Cloud Support: [Support Case Number]
- BigQuery Documentation: https://cloud.google.com/bigquery/docs

---

## Appendix: Quick Reference Commands

### Backup and Restore
```bash
# Backup all tables
./backup_tables.sh

# Rollback to specific backup
./rollback.sh 2025-10-31_143022
```

### Deployment
```bash
# Phase 1: Critical fixes
./deploy_phase1.sh

# Phase 2: Performance optimization
./deploy_phase2.sh
```

### Monitoring
```bash
# Run health checks
bq query --use_legacy_sql=false < monitor_deployment.sql

# Check BigQuery job status
bq ls -j -a -n 50

# View recent errors
bq ls -j -a -n 50 | grep FAILURE
```

### Emergency Commands
```bash
# Stop all scheduled queries (manual via console)
# Disable Cloud Functions (manual via console)
# Emergency rollback
./rollback.sh [BACKUP_TIMESTAMP]
```

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-31 | Deployment Engineer | Initial deployment checklist |

---

**END OF CHECKLIST**

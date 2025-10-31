# EROS Scheduling System - Deployment Automation

Complete deployment automation suite for safe, reliable deployment of EROS Scheduling System enhancements.

## Overview

This deployment package provides comprehensive automation for deploying critical bug fixes and performance optimizations to the EROS Scheduling System. All scripts are idempotent, include extensive error checking, and provide detailed logging.

## Files in This Package

### Documentation
- **PRE_DEPLOYMENT_CHECKLIST.md** - Comprehensive deployment checklist covering all phases
  - Backup procedures
  - Validation steps
  - Rollback procedures
  - Team notification templates
  - Post-deployment monitoring

### Deployment Scripts

#### 1. backup_tables.sh
Automated backup script for all critical tables with timestamp.

**Usage:**
```bash
./backup_tables.sh [PROJECT_ID] [DATASET]
./backup_tables.sh my-project-id eros_platform
```

**Features:**
- Backs up: caption_bank, caption_bandit_stats, active_caption_assignments
- Creates timestamped backups in gs://eros-platform-backups/
- Generates metadata file with row counts and sizes
- Verifies backup completion
- Automatic cleanup of backups older than 30 days

**Output:**
- Backup location: `gs://eros-platform-backups/YYYY-MM-DD_HHMMSS/`
- Metadata: `gs://eros-platform-backups/YYYY-MM-DD_HHMMSS/metadata.json`
- Local logs in /tmp/

#### 2. deploy_phase1.sh
Deploys critical bug fixes.

**Usage:**
```bash
./deploy_phase1.sh [PROJECT_ID] [DATASET]
```

**Fixes Deployed:**
1. **Wilson Score Lower Bound** - Corrected calculation with proper bounds
2. **Thompson Sampling** - Bayesian multi-armed bandit implementation
3. **Caption Locking** - Prevents duplicate caption assignments
4. **SQL Injection Protection** - Input validation and parameterized queries

**Features:**
- Automated deployment with validation tests
- Comprehensive error checking
- Rollback on failure
- Detailed logging of all operations

**Success Criteria:**
- All validation tests pass
- Wilson scores within [0, 1] range
- No SQL injection vulnerabilities
- Caption locking prevents duplicates

#### 3. deploy_phase2.sh
Deploys performance optimizations.

**Usage:**
```bash
./deploy_phase2.sh [PROJECT_ID] [DATASET]
```

**Optimizations Deployed:**
1. **Performance Feedback Loop** - Batch updates and materialized views
2. **Account Size Classification** - Improved categorization and targeting
3. **Query Timeout Configuration** - Prevents runaway queries
4. **Additional Enhancements** - Caching, indexing, optimized structures

**Features:**
- Pre/post deployment benchmarking
- Performance comparison metrics
- Cost tracking
- Automated validation

**Success Criteria:**
- Query performance improvement >10%
- No increase in error rates
- Cost increase <5%

#### 4. rollback.sh
Emergency rollback procedure.

**Usage:**
```bash
./rollback.sh                    # Use latest backup
./rollback.sh 2025-10-31_143022 # Use specific backup
```

**Features:**
- Restores tables from backup
- Creates pre-rollback snapshot
- Disables scheduled queries
- Clears caption locks
- Sends alert notifications
- Comprehensive logging

**Rollback Process:**
1. Verify backup exists
2. Confirm rollback decision
3. Create safety snapshot
4. Disable scheduled jobs
5. Restore all tables
6. Verify system health
7. Send notifications

### Monitoring

#### monitor_deployment.sql
Comprehensive SQL queries for health checks and monitoring.

**Usage:**
```bash
# Run all checks
bq query --use_legacy_sql=false < monitor_deployment.sql

# Export to CSV
bq query --use_legacy_sql=false --format=csv < monitor_deployment.sql > results.csv
```

**Monitoring Sections:**
1. **Daily Health Checks** - Table integrity, data validation
2. **Performance Monitoring** - Query times, efficiency metrics
3. **Cost Tracking** - BigQuery costs, optimization opportunities
4. **EMV Improvement** - Engagement rates, Wilson scores, ROI
5. **Deployment Success** - Overall health score, improvement metrics

**Key Metrics:**
- System Health Score (0-100)
- Query performance (p50, p95, p99)
- Error rates
- EMV improvements
- Cost per query type

## Deployment Workflow

### Complete Deployment Process

```bash
# Step 1: Review checklist
cat PRE_DEPLOYMENT_CHECKLIST.md

# Step 2: Create backup
./backup_tables.sh

# Step 3: Deploy Phase 1 (Critical Fixes)
./deploy_phase1.sh

# Wait 30 minutes, monitor for issues

# Step 4: Deploy Phase 2 (Performance Optimizations)
./deploy_phase2.sh

# Step 5: Monitor deployment
bq query --use_legacy_sql=false < monitor_deployment.sql

# If issues occur:
./rollback.sh [BACKUP_TIMESTAMP]
```

### Phased Deployment Strategy

**Phase 0: Preparation (T-24 hours)**
- [ ] Review PRE_DEPLOYMENT_CHECKLIST.md
- [ ] Notify stakeholders
- [ ] Verify prerequisites
- [ ] Schedule deployment window

**Phase 1: Backup (T-0)**
- [ ] Run backup_tables.sh
- [ ] Verify backup completion
- [ ] Record backup timestamp

**Phase 2: Deploy Critical Fixes (T+15 min)**
- [ ] Run deploy_phase1.sh
- [ ] Verify all tests pass
- [ ] Monitor for 30 minutes

**Phase 3: Deploy Optimizations (T+45 min)**
- [ ] Run deploy_phase2.sh
- [ ] Review performance benchmarks
- [ ] Monitor for 2 hours

**Phase 4: Validation (T+3 hours)**
- [ ] Run monitor_deployment.sql
- [ ] Verify success metrics
- [ ] Document results

**Phase 5: Post-Deployment (T+24 hours)**
- [ ] Daily health checks
- [ ] Performance trend analysis
- [ ] Cost review
- [ ] EMV tracking

## Configuration

### Environment Variables

Set these for convenience:
```bash
export EROS_PROJECT_ID="your-project-id"
export EROS_DATASET="eros_platform"
```

### Prerequisites

- Google Cloud SDK installed (`gcloud`, `bq`, `gsutil`)
- Authenticated with appropriate project
- BigQuery Admin permissions
- Storage Admin permissions for backup bucket
- Bash 4.0+ (macOS compatible)

### Verify Prerequisites

```bash
# Check gcloud
gcloud --version

# Check authentication
gcloud auth list

# Check BigQuery access
bq ls

# Check storage access
gsutil ls gs://eros-platform-backups/
```

## Monitoring Schedule

### Daily (First Week Post-Deployment)
```bash
# Morning health check
bq query --use_legacy_sql=false < monitor_deployment.sql | grep "Health Check"

# Afternoon performance review
bq query --use_legacy_sql=false < monitor_deployment.sql | grep "Performance"

# Evening summary
bq query --use_legacy_sql=false < monitor_deployment.sql | grep "EMV"
```

### Weekly (Ongoing)
- Run full monitoring suite
- Review cost trends
- Analyze EMV improvements
- Check for optimization opportunities

## Troubleshooting

### Backup Issues

**Problem:** Backup bucket doesn't exist
```bash
# Create bucket manually
gsutil mb gs://eros-platform-backups/
```

**Problem:** Permission denied
```bash
# Check permissions
gcloud projects get-iam-policy PROJECT_ID | grep $(gcloud config get-value account)
```

### Deployment Issues

**Problem:** Phase 1 validation tests fail
```bash
# Review logs
ls -la /tmp/eros_deployment_phase1_*/

# Check specific test results
cat /tmp/eros_deployment_phase1_*/wilson_score_fix.log
```

**Problem:** Phase 2 performance regression
```bash
# Review benchmark results
cat /tmp/eros_deployment_phase2_*/performance_benchmarks.json

# Consider rollback
./rollback.sh
```

### Rollback Issues

**Problem:** Can't find backup
```bash
# List available backups
gsutil ls gs://eros-platform-backups/

# Verify specific backup
gsutil ls gs://eros-platform-backups/YYYY-MM-DD_HHMMSS/
```

## Safety Features

### Idempotency
All scripts can be run multiple times safely:
- Backups create new timestamped versions
- Deployments use CREATE OR REPLACE
- Rollback creates safety snapshots

### Error Handling
- Exit on first error (`set -e`)
- Undefined variable protection (`set -u`)
- Pipe failure detection (`set -o pipefail`)
- Comprehensive logging
- Validation at each step

### Rollback Protection
- Pre-rollback snapshots created automatically
- Confirmation required for destructive operations
- Backup verification before restore
- System health checks after rollback

## Performance Targets

### Deployment Success Criteria
- **Query Performance:** >10% improvement
- **Error Rate:** <1%
- **Cost Increase:** <5%
- **EMV Improvement:** >10%
- **System Health Score:** >90/100

### Monitoring Thresholds
- **p95 Query Time:** <1000ms
- **Failure Rate:** <1%
- **Data Integrity:** 100% (0 corrupt records)
- **Wilson Score Range:** All values in [0, 1]

## Cost Management

### Expected Costs
- **Backup Storage:** ~$0.02/GB/month
- **Query Costs:** $5/TB processed
- **Deployment:** One-time cost <$10

### Cost Optimization
- Automated cleanup of old backups (30-day retention)
- Materialized views reduce query costs
- Query timeout configuration prevents runaway costs
- Clustering and partitioning reduce data scanned

## Support

### Log Locations
- **Backup:** `/tmp/backup_TIMESTAMP/`
- **Phase 1:** `/tmp/eros_deployment_phase1_TIMESTAMP/`
- **Phase 2:** `/tmp/eros_deployment_phase2_TIMESTAMP/`
- **Rollback:** `/tmp/eros_rollback_TIMESTAMP/`

### Emergency Contacts
- Deployment Lead: [CONTACT]
- Technical Lead: [CONTACT]
- On-Call Engineer: [CONTACT]

### Escalation Path
1. Check logs in /tmp/
2. Review monitoring queries
3. Contact deployment lead
4. Initiate rollback if needed
5. Escalate to engineering leadership

## Best Practices

### Before Deployment
1. Always run backup first
2. Review checklist completely
3. Verify prerequisites
4. Have rollback plan ready
5. Schedule during low-traffic period

### During Deployment
1. Monitor output closely
2. Don't skip validation steps
3. Wait between phases
4. Keep stakeholders updated
5. Document any anomalies

### After Deployment
1. Monitor continuously for 24 hours
2. Run health checks daily (first week)
3. Track performance trends
4. Document lessons learned
5. Update runbooks

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-31 | Initial deployment automation suite |

## License

Internal use only - EROS Platform Engineering Team

---

**Questions or Issues?**
Contact the deployment engineering team or refer to PRE_DEPLOYMENT_CHECKLIST.md for detailed procedures.

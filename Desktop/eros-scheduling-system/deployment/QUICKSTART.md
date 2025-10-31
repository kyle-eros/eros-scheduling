# EROS Scheduling System Deployment - Quick Start Guide

**5-Minute Deployment Guide for Experienced Engineers**

## Prerequisites Check (2 minutes)

```bash
# Verify tools
which bq gsutil gcloud

# Verify authentication
gcloud auth list

# Set project (replace with your project ID)
export EROS_PROJECT_ID="your-project-id"
export EROS_DATASET="eros_platform"

# Verify BigQuery access
bq ls ${EROS_PROJECT_ID}:${EROS_DATASET}
```

## Deployment Steps

### 1. Backup (5 minutes)

```bash
cd /Users/kylemerriman/Desktop/new\ agent\ setup/eros-scheduling-system/deployment

# Create backup
./backup_tables.sh

# Save the backup timestamp shown at the end
# Example: 2025-10-31_143022
```

### 2. Deploy Phase 1 - Critical Fixes (10 minutes)

```bash
# Deploy critical bug fixes
./deploy_phase1.sh

# Wait for completion and verify all tests pass
# Look for: "Phase 1 deployment completed successfully!"
```

**Monitor for 30 minutes before proceeding to Phase 2**

### 3. Deploy Phase 2 - Performance Optimizations (15 minutes)

```bash
# Deploy performance optimizations
./deploy_phase2.sh

# Review performance benchmarks
# Look for: "Phase 2 deployment completed successfully!"
```

### 4. Monitor (Ongoing)

```bash
# Run health checks
bq query --use_legacy_sql=false < monitor_deployment.sql

# Check system health score (target: >90)
# Monitor error rates (target: <1%)
# Track EMV improvements (target: >10%)
```

## Emergency Rollback

If issues detected:

```bash
# Rollback to latest backup
./rollback.sh

# Or rollback to specific backup
./rollback.sh 2025-10-31_143022
```

## Success Criteria

After deployment, verify:

- [ ] All validation tests passed
- [ ] System health score >90
- [ ] Query error rate <1%
- [ ] Performance improvement >10%
- [ ] No data integrity issues

## Files Overview

| File | Purpose | When to Use |
|------|---------|-------------|
| PRE_DEPLOYMENT_CHECKLIST.md | Comprehensive checklist | Before starting |
| backup_tables.sh | Create backups | Always run first |
| deploy_phase1.sh | Deploy critical fixes | After backup |
| deploy_phase2.sh | Deploy optimizations | After Phase 1 |
| rollback.sh | Emergency rollback | If issues occur |
| monitor_deployment.sql | Health monitoring | After deployment |
| README.md | Full documentation | For detailed info |

## Command Summary

```bash
# Complete deployment in one session
./backup_tables.sh                    # Step 1: Backup
./deploy_phase1.sh                    # Step 2: Critical fixes
# Wait 30 minutes
./deploy_phase2.sh                    # Step 3: Optimizations
bq query --use_legacy_sql=false < monitor_deployment.sql  # Step 4: Verify

# If problems occur
./rollback.sh [BACKUP_TIMESTAMP]      # Emergency rollback
```

## Timeline

| Phase | Duration | Monitoring |
|-------|----------|------------|
| Backup | 5 min | Verify completion |
| Phase 1 | 10 min | 30 min observation |
| Phase 2 | 15 min | 2 hour observation |
| Validation | 5 min | 24 hour monitoring |
| **Total** | **35 min** | **27 hours** |

## Support

- **Logs:** Check `/tmp/eros_*/` directories
- **Detailed Guide:** See `README.md`
- **Full Checklist:** See `PRE_DEPLOYMENT_CHECKLIST.md`

## Key Points

1. **Always backup first** - No exceptions
2. **Monitor between phases** - Don't rush
3. **Verify success** - Run health checks
4. **Keep logs** - You'll need them for analysis
5. **Have rollback ready** - Know your backup timestamp

---

**Ready to deploy?** Start with `./backup_tables.sh`

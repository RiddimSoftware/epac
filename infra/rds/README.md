# epac Aurora Retirement

The production Aurora Serverless v2 cluster `epac-db` is being retired after
the EPAC data paths moved to S3 and CloudFront artifacts. This directory no
longer contains provisioning automation for the database. Re-creating Aurora
should be a new infrastructure task with a fresh design, not a resurrection of
the deleted cutover script.

## Cutover checklist

Before destructive teardown, confirm the CloudWatch metrics for `epac-db` in
`us-east-1` show:

- `AWS/RDS DatabaseConnections` at zero for at least 7 consecutive days.
- `AWS/RDS ServerlessDatabaseCapacity` held at the 0.5 ACU floor for at least 7
  consecutive days.

The destructive steps are intentionally manual. Run them only after the metrics
above are captured for the PR and a human has approved the cutover window.

```bash
AWS_PROFILE=riddim-agent
AWS_REGION=us-east-1
SNAPSHOT_ID="epac-db-final-$(date +%Y%m%d)"

aws rds create-db-cluster-snapshot \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-cluster-identifier epac-db \
  --db-cluster-snapshot-identifier "$SNAPSHOT_ID"

aws rds wait db-cluster-snapshot-available \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-cluster-snapshot-identifier "$SNAPSHOT_ID"

aws rds delete-db-instance \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-instance-identifier epac-db-writer

aws rds wait db-instance-deleted \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-instance-identifier epac-db-writer

aws rds delete-db-cluster \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --db-cluster-identifier epac-db \
  --skip-final-snapshot

aws secretsmanager delete-secret \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --secret-id epac/database-url \
  --recovery-window-in-days 30
```

Keep the final snapshot for the 90-day recovery window unless a human explicitly
chooses earlier deletion. After teardown, watch production alarms for 24 hours
and confirm Cost Explorer shows `epac-db` charges drop to zero over the
following 7 days.

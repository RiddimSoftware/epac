# Fiscal Monitor Statistics

Fetches the current fiscal year's Department of Finance Canada Fiscal Monitor
HTML pages and emits monthly revenue, expense, and budgetary-balance entries.

```bash
python3 fiscal_monitor.py --output fiscal-monitor.json
ARTIFACTS_BUCKET=epac-artifacts python3 fiscal_monitor.py --s3-publish
python3 -m unittest
```

## S3 artifacts

`--s3-publish` writes `statistics/v1/fiscal-monitor/all.json` with
`x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline monthly on day 22 at
00:00 UTC, and on every manual `workflow_dispatch`.

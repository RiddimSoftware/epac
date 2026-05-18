# CPI Statistics

Fetches province-level Consumer Price Index statistics from Statistics Canada
table 18-10-0004-01 and writes the bundled iOS snapshot.

```bash
python3 cpi_statistics.py --output ../../ios/epac/cpi-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 cpi_statistics.py --s3-publish
```

The output includes the latest reference month plus 24 months of year-over-year
inflation trend data for all-items, food, shelter, and energy.

## S3 artifacts

`--s3-publish` writes `statistics/v1/cpi-statistics/all.json`, `national.json`,
and one `province-<code>.json` object per available province with
`x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline monthly on day 22 at
00:00 UTC, and on every manual `workflow_dispatch`.

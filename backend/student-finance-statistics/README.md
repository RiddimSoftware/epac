# Student Finance Statistics

Builds the bundled iOS snapshot for Canada Student Financial Assistance Program
and undergraduate tuition context.

```bash
python3 student_finance_statistics.py --output ../../ios/epac/student-finance-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 student_finance_statistics.py --s3-publish
python3 -m unittest
```

The CSFAP loan/RAP values are transcribed from the latest ESDC Statistical
Review and Annual Report because those tables are published as HTML/PDF rather
than machine-readable CSV. Tuition values are fetched from Statistics Canada
table 37-10-0120-01.

## S3 artifacts

`--s3-publish` writes `statistics/v1/student-finance-statistics/all.json` and
one `province-<code>.json` object per available province or territory with
`x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline quarterly on day 22 at
00:00 UTC in January, April, July, and October, and on every manual
`workflow_dispatch`.

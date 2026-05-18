# EI Statistics Ingest

Fetches the most recent province-level Employment Insurance monthly statistics from Statistics Canada tables produced from Service Canada and Employment and Social Development Canada administrative data.

```bash
python3 ei_statistics.py --output ../../ios/epac/ei-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 ei_statistics.py --s3-publish
python3 -m unittest
```

The output contains each province's latest reference month, regular beneficiaries, claims received, computed average weekly benefit, year-over-year claims change, and the most recent 12 monthly records used for the snapshot.

## S3 artifacts

`--s3-publish` writes `statistics/v1/ei-statistics/all.json` and one
`province-<code>.json` object per available province or territory with
`x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline quarterly on day 22 at
00:00 UTC in January, April, July, and October, and on every manual
`workflow_dispatch`.

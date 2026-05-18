# CPP/OAS Statistics

Fetches CPP retirement and OAS pension recipient counts from ESDC open-data CSVs
and composes province-level and national snapshots.

```bash
python3 cpp_oas_statistics.py --output cpp-oas-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 cpp_oas_statistics.py --s3-publish
python3 -m unittest
```

## S3 artifacts

`--s3-publish` writes `statistics/v1/cpp-oas-statistics/all.json`,
`national.json`, and one `province-<code>.json` object per province or territory
with `x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline quarterly on day 22 at
00:00 UTC in January, April, July, and October, and on every manual
`workflow_dispatch`.

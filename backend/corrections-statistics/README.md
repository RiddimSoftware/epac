# Corrections statistics

Builds the `ios/epac/corrections-statistics.json` bundle snapshot used by the
Riding Statistics, Home, and debate-context surfaces.

Sources are annual accountability publications rather than live APIs:

- Correctional Service Canada Departmental Results Report 2023-2024
- Correctional Service Canada Indigenous Corrections Accountability Framework 2023-2024
- Office of the Correctional Investigator Annual Report 2024-2025
- Statistics Canada 2021 Census Profile for Canada

Run:

```bash
python3 corrections_statistics.py --output ../../ios/epac/corrections-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 corrections_statistics.py --s3-publish
python3 -m unittest
```

The script logs structured JSON to stderr and writes the snapshot JSON to the
requested output path.

## S3 artifacts

`--s3-publish` writes `statistics/v1/corrections-statistics/all.json` with
`x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline quarterly on day 22 at
00:00 UTC in January, April, July, and October, and on every manual
`workflow_dispatch`.

# Veterans Affairs Canada statistics

Builds the bundled `ios/epac/vac-statistics.json` snapshot from published Veterans Affairs Canada reporting tables.

Sources:

- VAC Facts and Figures: program recipients, program expenditures, and provincial Veteran population from the 2021 Census. The current disability-benefit program tables include forecast rows for 2022-23 through 2026-27.
- VAC Disability Benefit Processing Summary Report, Q4 2023-2024: current national disability-benefit recipient count, backlog, pending applications, and first-application processing times.
- VAC Departmental Results Reports 2023-2024 and 2024-2025: Benefits, Services and Support spending and 16-week disability-benefit service-standard results.

Run:

```bash
python3 backend/vac-statistics/vac_statistics.py --output ios/epac/vac-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 backend/vac-statistics/vac_statistics.py --s3-publish
```

## S3 artifacts

`--s3-publish` writes `statistics/v1/vac-statistics/all.json`,
`national.json`, and one `province-<code>.json` object per available province
with `x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline quarterly on day 22 at
00:00 UTC in January, April, July, and October, and on every manual
`workflow_dispatch`.

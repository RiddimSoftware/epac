# Transport Safety Statistics

Fetches national TSB air, marine, and rail occurrence summaries plus Transport Canada road casualty rates by province.

```bash
python3 transport_safety_statistics.py --output ../../ios/epac/transport-safety-statistics.json
ARTIFACTS_BUCKET=epac-artifacts python3 transport_safety_statistics.py --s3-publish
python3 -m unittest test_transport_safety_statistics.py
```

Sources:

- Transportation Safety Board of Canada annual statistics
- Transport Canada Canadian Motor Vehicle Traffic Collision Statistics

## S3 artifacts

`--s3-publish` writes `statistics/v1/transport-safety-statistics/all.json`,
`road-national.json`, and one `road-province-<code>.json` object per province
or territory with `x-amz-meta-content-hash-sha256` metadata.

The `Publish Artifacts` workflow runs this pipeline quarterly on day 22 at
00:00 UTC in January, April, July, and October, and on every manual
`workflow_dispatch`.

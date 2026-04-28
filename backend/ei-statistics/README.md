# EI Statistics Ingest

Fetches the most recent province-level Employment Insurance monthly statistics from Statistics Canada tables produced from Service Canada and Employment and Social Development Canada administrative data.

```bash
python3 ei_statistics.py --output ../../ios/epac/ei-statistics.json
python3 -m unittest
```

The output contains each province's latest reference month, regular beneficiaries, claims received, computed average weekly benefit, year-over-year claims change, and the most recent 12 monthly records used for the snapshot.

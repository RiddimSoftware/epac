# CPI Statistics

Fetches province-level Consumer Price Index statistics from Statistics Canada
table 18-10-0004-01 and writes the bundled iOS snapshot.

```bash
python3 cpi_statistics.py --output ../../ios/epac/cpi-statistics.json
```

The output includes the latest reference month plus 24 months of year-over-year
inflation trend data for all-items, food, shelter, and energy.

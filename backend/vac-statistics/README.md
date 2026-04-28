# Veterans Affairs Canada statistics

Builds the bundled `ios/epac/vac-statistics.json` snapshot from published Veterans Affairs Canada reporting tables.

Sources:

- VAC Facts and Figures, March 2022 edition: program recipients, program expenditures, and provincial Veteran population from the 2021 Census.
- VAC Disability Benefit Processing Summary Report, Q4 2023-2024: current national disability-benefit recipient count, backlog, pending applications, and first-application processing times.
- VAC Departmental Results Reports 2023-2024 and 2024-2025: Benefits, Services and Support spending and 16-week disability-benefit service-standard results.

Run:

```bash
python3 backend/vac-statistics/vac_statistics.py --output ios/epac/vac-statistics.json
```

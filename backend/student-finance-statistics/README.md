# Student Finance Statistics

Builds the bundled iOS snapshot for Canada Student Financial Assistance Program
and undergraduate tuition context.

```bash
python3 student_finance_statistics.py --output ../../ios/epac/student-finance-statistics.json
python3 -m unittest
```

The CSFAP loan/RAP values are transcribed from the latest ESDC Statistical
Review and Annual Report because those tables are published as HTML/PDF rather
than machine-readable CSV. Tuition values are fetched from Statistics Canada
table 37-10-0120-01.

# Cabinet ingestion

`cabinet_ingest.py` fetches the current federal Cabinet from pm.gc.ca and writes
`ios/epac/cabinet-positions.json` — the JSON snapshot bundled with the iOS app.

## Run

```bash
cd /path/to/epac
python3 backend/cabinet/cabinet_ingest.py
```

Add `--dry-run` to print to stdout instead of writing the file. Use
`--output <path>` to write somewhere other than the bundled iOS path.

## When to run

Re-run after any Cabinet shuffle, then commit the updated
`ios/epac/cabinet-positions.json` alongside the iOS PR that ships it.

## Tests

```bash
cd backend/cabinet && python3 -m unittest test_cabinet_ingest.py
```

## Sources

- Cabinet composition — https://www.pm.gc.ca/en/cabinet
- Mandate letters index — https://www.pm.gc.ca/en/mandate-letters

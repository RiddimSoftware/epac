# Hansard Backfill

Bulk downloader/parser for House of Commons Hansard XML.

```bash
cd backend/hansard-backfill
DATABASE_URL=postgres://... go run . --archive-dir ../../data/hansard/raw
```

Useful local checks:

```bash
go test ./...
go run . --dry-run --sessions 45-1 --start-date 2026-01-27 --end-date 2026-01-27 --max-sittings 74 --archive-dir /tmp/epac-hansard-backfill-smoke
```

The command is idempotent:

- Raw XML is archived under `<archive-dir>/<parliament>-<session>/`.
- Existing XML is reused unless `--force` is passed.
- `speeches.intervention_id` is the database conflict key.
- Run status is written to `pipeline_health` as `hansard-backfill`.
